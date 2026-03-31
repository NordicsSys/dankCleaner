pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool cleanupCache: true
    property bool cleanupTrash: true
    property bool cleanupBrowserCache: true
    property bool cleanupTmp: false
    property int tmpAgeDays: 3
    property string cacheExcludeNames: ""
    property string diskAnalyzerPaths: "~/Downloads\n~/Documents\n~/Videos\n~/Pictures"

    property bool running: false
    property string statusText: "Idle"
    property real totalCleanupBytes: 0
    property string totalCleanupLabel: "0 B reclaimable"
    property string totalCleanupShort: "0B"

    property real cacheBytes: 0
    property real trashBytes: 0
    property real browserCacheBytes: 0
    property real tmpBytes: 0

    property real lastCleanupBytes: 0
    property string lastCleanupLabel: "0 B"

    property var diskTopDirs: []
    property var diskCategoryBuckets: []
    property real diskTotalBytes: 0
    property real diskHomeTotalBytes: 0
    property real diskLastAnalyzedTime: 0   // ms since epoch
    property string diskScopePath: ""      // "" = overview, else path we're drilled into
    property var diskScopeStack: []        // stack of path or "" for back navigation
    property bool refreshPending: false

    // Docker
    property bool dockerAvailable: false
    property string dockerTotalSize: "0 B"
    property string dockerReclaimable: "0 B"
    property var dockerBreakdown: []  // list of { type, size, reclaimable, reclaimablePct }

    readonly property string homeDir: Quickshell.env("HOME") || ""

    Component {
        id: cmdRunner
        Process {
            id: cmdProc
            property string shellCmd: ""
            property var onFinished: null
            command: ["bash", "-lc", shellCmd]
            stdout: StdioCollector {
                onStreamFinished: {
                    if (cmdProc.onFinished) cmdProc.onFinished(text);
                }
            }
            stderr: StdioCollector {}
            onExited: {
                cmdProc.destroy();
            }
        }
    }

    function run(shellCmd, cb) {
        var p = cmdRunner.createObject(root, { shellCmd: shellCmd, onFinished: cb });
        p.running = true;
    }

    // find/rm/du/docker often exit non-zero on partial errors; Quickshell may report
    // that as "Theme worker failed (1)". We only rely on stdout in callbacks here.
    function runQuietExit(shellCmd, cb) {
        var body = String(shellCmd).replace(/;+\s*$/, "").trim();
        var wrapped = (body ? body + "; " : "") + "exit 0";
        run(wrapped, cb);
    }

    function shellQuote(input) {
        return "'" + String(input).replace(/'/g, "'\"'\"'") + "'";
    }

    function formatBytes(bytes) {
        var v = Number(bytes) || 0;
        if (v <= 0) return "0 B";
        var units = ["B", "KB", "MB", "GB", "TB"];
        var u = 0;
        while (v >= 1024 && u < units.length - 1) {
            v /= 1024;
            u++;
        }
        var precision = v >= 10 || u === 0 ? 0 : 1;
        return v.toFixed(precision) + " " + units[u];
    }

    function formatShort(bytes) {
        var text = formatBytes(bytes);
        return text.replace(" ", "");
    }

    function parseNumber(text) {
        var n = parseInt(String(text).trim(), 10);
        return isNaN(n) ? 0 : n;
    }

    function expandTilde(pathValue) {
        if (!pathValue) return "";
        var p = String(pathValue).trim();
        if (p.indexOf("~/") === 0) return root.homeDir + p.substring(1);
        if (p === "~") return root.homeDir;
        return p;
    }

    function safeHomePath(pathValue) {
        if (!root.homeDir) return false;
        var p = expandTilde(pathValue);
        return p.length > 1 && p.indexOf(root.homeDir + "/") === 0;
    }

    function normalizePaths(rawValue, fallbackPaths) {
        var raw = String(rawValue || "").split(/\n|,/);
        var out = [];
        for (var i = 0; i < raw.length; i++) {
            var item = expandTilde(raw[i]);
            if (!item || !safeHomePath(item)) continue;
            if (out.indexOf(item) === -1) out.push(item);
        }
        if (out.length === 0) out = fallbackPaths;
        return out;
    }

    readonly property string cacheRootPath: root.homeDir ? root.homeDir + "/.cache" : ""

    function parseCacheExcludeNames() {
        var base = root.cacheRootPath;
        if (!base)
            return [];
        var rawList = String(root.cacheExcludeNames || "").split(/\n|,/);
        var out = [];
        for (var i = 0; i < rawList.length; i++) {
            var token = String(rawList[i]).trim();
            if (!token)
                continue;
            var name = "";
            var full = expandTilde(token);
            if (full.indexOf(base + "/") === 0) {
                var rel = full.substring(base.length + 1);
                if (!rel)
                    continue;
                name = rel.split("/")[0];
            } else if (token.indexOf("/") === -1 && token.indexOf("..") === -1) {
                name = token;
            } else {
                continue;
            }
            if (!/^[a-zA-Z0-9._-]+$/.test(name))
                continue;
            if (out.indexOf(name) === -1)
                out.push(name);
        }
        return out;
    }

    function cacheCleanPruneNames() {
        var names = ["mozilla", "google-chrome", "chromium"];
        var user = parseCacheExcludeNames();
        for (var j = 0; j < user.length; j++) {
            if (names.indexOf(user[j]) === -1)
                names.push(user[j]);
        }
        return names;
    }

    function buildCacheFindNegations() {
        var names = cacheCleanPruneNames();
        var parts = [];
        for (var i = 0; i < names.length; i++) {
            parts.push("! -name " + shellQuote(names[i]));
        }
        return parts.join(" ");
    }

    function shellCmdCacheSizeEstimate() {
        var names = cacheCleanPruneNames();
        var loop = "s=0; ";
        for (var i = 0; i < names.length; i++) {
            var n = names[i];
            loop += "d=$(du -sb \"$HOME/.cache/" + n + "\" 2>/dev/null | awk '{print $1}'); ";
            loop += "s=$((s+${d:-0})); ";
        }
        return "t=$(du -sb \"$HOME/.cache\" 2>/dev/null | awk '{print $1}'); " + loop + "echo $((t-s))";
    }

    function refreshAll() {
        if (running) {
            refreshPending = true;
            return;
        }
        running = true;
        statusText = "Scanning cleanup categories";
        estimateCleanup(function() {
            statusText = "Analyzing disk usage";
            scanDiskUsage(function() {
                finishRunning("Ready");
            });
        });
    }

    function updateTotals() {
        totalCleanupBytes = (cleanupCache ? cacheBytes : 0)
            + (cleanupTrash ? trashBytes : 0)
            + (cleanupBrowserCache ? browserCacheBytes : 0)
            + (cleanupTmp ? tmpBytes : 0);
        totalCleanupLabel = formatBytes(totalCleanupBytes) + " reclaimable";
        totalCleanupShort = formatShort(totalCleanupBytes);
    }

    function estimateCleanup(done) {
        var steps = [];

        steps.push(function(next) {
            if (!cleanupCache) {
                cacheBytes = 0;
                next();
                return;
            }
            runQuietExit(shellCmdCacheSizeEstimate(), function(out) {
                cacheBytes = Math.max(0, parseNumber(out));
                next();
            });
        });

        steps.push(function(next) {
            if (!cleanupTrash) {
                trashBytes = 0;
                next();
                return;
            }
            var cmd = "du -sb \"$HOME/.local/share/Trash/files\" \"$HOME/.local/share/Trash/info\" 2>/dev/null | awk '{sum+=$1} END{print sum+0}'";
            runQuietExit(cmd, function(out) {
                trashBytes = parseNumber(out);
                next();
            });
        });

        steps.push(function(next) {
            if (!cleanupBrowserCache) {
                browserCacheBytes = 0;
                next();
                return;
            }
            var cmd = "du -sb \"$HOME/.cache/mozilla\" \"$HOME/.cache/google-chrome\" \"$HOME/.cache/chromium\" 2>/dev/null | awk '{sum+=$1} END{print sum+0}'";
            runQuietExit(cmd, function(out) {
                browserCacheBytes = parseNumber(out);
                next();
            });
        });

        steps.push(function(next) {
            if (!cleanupTmp) {
                tmpBytes = 0;
                next();
                return;
            }
            var age = Math.max(1, parseInt(tmpAgeDays) || 3);
            var cmd = "find /tmp -maxdepth 1 -user \"$USER\" -mtime +" + age + " -print0 2>/dev/null | du --files0-from=- -cb 2>/dev/null | tail -n 1 | awk '{print $1+0}'";
            runQuietExit(cmd, function(out) {
                tmpBytes = parseNumber(out);
                next();
            });
        });

        runSequence(steps, function() {
            updateTotals();
            if (done) done();
        });
    }

    function runSequence(steps, onDone) {
        var i = 0;
        function next() {
            if (i >= steps.length) {
                if (onDone)
                    onDone();
                return;
            }
            var step = steps[i++];
            step(next);
        }
        next();
    }

    function finishRunning(nextStatus) {
        running = false;
        statusText = nextStatus;
        if (refreshPending) {
            refreshPending = false;
            Qt.callLater(refreshAll);
        }
    }

    function diskLastAnalyzedLabel() {
        var t = diskLastAnalyzedTime;
        if (!t || t <= 0) return "Never";
        var sec = (Date.now() - t) / 1000;
        if (sec < 60) return "Just now";
        if (sec < 3600) return Math.floor(sec / 60) + " min ago";
        if (sec < 86400) return Math.floor(sec / 3600) + " h ago";
        return Math.floor(sec / 86400) + " day(s) ago";
    }

    function scanHomeTotal(done) {
        if (!root.homeDir) {
            diskHomeTotalBytes = 0;
            if (done) done();
            return;
        }
        runQuietExit("du -sb " + shellQuote(root.homeDir) + " 2>/dev/null | awk '{print $1}'", function(out) {
            diskHomeTotalBytes = parseNumber(out);
            if (done) done();
        });
    }

    function summarizeCategoryForPath(pathValue) {
        var p = String(pathValue || "").toLowerCase();
        if (p.indexOf("/videos") >= 0 || p.indexOf("/video") >= 0
            || p.indexOf("/music") >= 0 || p.indexOf("/pictures") >= 0
            || p.indexOf("/photos") >= 0 || p.indexOf("/images") >= 0) {
            return "Media";
        }
        if (p.indexOf("/documents") >= 0 || p.indexOf("/document") >= 0
            || p.indexOf("/books") >= 0 || p.indexOf("/notes") >= 0) {
            return "Documents";
        }
        if (p.indexOf("/downloads") >= 0 || p.indexOf("/archive") >= 0
            || p.indexOf("/backup") >= 0) {
            return "Archives";
        }
        if (p.indexOf("/projects") >= 0 || p.indexOf("/code") >= 0
            || p.indexOf("/src") >= 0 || p.indexOf("/dev") >= 0) {
            return "Code";
        }
        return "Other";
    }

    function scanDiskUsage(done) {
        diskScopePath = "";
        diskScopeStack = [];
        var paths = normalizePaths(root.diskAnalyzerPaths, [root.homeDir + "/Downloads", root.homeDir + "/Documents", root.homeDir + "/Videos", root.homeDir + "/Pictures"]);
        var rows = [];
        var steps = [];
        var bucketMap = {};

        steps.push(function(next) {
            scanHomeTotal(function() { next(); });
        });

        for (var i = 0; i < paths.length; i++) {
            (function(searchPath) {
                steps.push(function(next) {
                    if (!safeHomePath(searchPath)) {
                        next();
                        return;
                    }
                    var cmd = "find " + shellQuote(searchPath) + " -mindepth 1 -maxdepth 1 -print0 2>/dev/null | du --files0-from=- -sb 2>/dev/null";
                    runQuietExit(cmd, function(out) {
                        var lines = String(out).split("\n");
                        var hasRows = false;
                        for (var j = 0; j < lines.length; j++) {
                            var line = lines[j].trim();
                            if (!line) continue;
                            var parts = line.split(/\t+/);
                            if (parts.length < 2) continue;
                            var itemPath = parts.slice(1).join("\t");
                            var itemSize = parseNumber(parts[0]);
                            if (!safeHomePath(itemPath) || itemSize <= 0) continue;
                            hasRows = true;
                            rows.push({
                                path: itemPath,
                                size: itemSize,
                                label: itemPath.split("/").pop()
                            });
                            var key = summarizeCategoryForPath(itemPath);
                            bucketMap[key] = (bucketMap[key] || 0) + itemSize;
                        }

                        if (!hasRows) {
                            runQuietExit("du -sb " + shellQuote(searchPath) + " 2>/dev/null | awk '{print $1\"\\t\"$2}'", function(singleOut) {
                                var singleParts = String(singleOut).trim().split(/\t+/);
                                if (singleParts.length >= 2) {
                                    var onePath = singleParts.slice(1).join("\t");
                                    var oneSize = parseNumber(singleParts[0]);
                                    if (safeHomePath(onePath) && oneSize > 0) {
                                        rows.push({
                                            path: onePath,
                                            size: oneSize,
                                            label: onePath.split("/").pop()
                                        });
                                        var oneKey = summarizeCategoryForPath(onePath);
                                        bucketMap[oneKey] = (bucketMap[oneKey] || 0) + oneSize;
                                    }
                                }
                                next();
                            });
                            return;
                        }
                        next();
                    });
                });
            })(paths[i]);
        }

        runSequence(steps, function() {
            rows.sort(function(a, b) { return b.size - a.size; });
            diskTopDirs = rows.slice(0, 20);
            diskTotalBytes = 0;
            for (var k = 0; k < rows.length; k++) {
                diskTotalBytes += rows[k].size;
            }
            var bucketRows = [];
            for (var name in bucketMap) {
                bucketRows.push({ name: name, size: bucketMap[name] });
            }
            bucketRows.sort(function(a, b) { return b.size - a.size; });
            diskCategoryBuckets = bucketRows;
            diskLastAnalyzedTime = Date.now();
            if (done) done();
        });
    }

    function scanDiskUsageAtPath(pathValue, done) {
        if (!pathValue || !safeHomePath(pathValue)) {
            if (done) done();
            return;
        }
        var cmd = "find " + shellQuote(pathValue) + " -mindepth 1 -maxdepth 1 -print0 2>/dev/null | du --files0-from=- -sb 2>/dev/null";
        runQuietExit(cmd, function(out) {
            var rows = [];
            var bucketMap = {};
            var lines = String(out).split("\n");
            var hasRows = false;
            for (var j = 0; j < lines.length; j++) {
                var line = lines[j].trim();
                if (!line) continue;
                var parts = line.split(/\t+/);
                if (parts.length < 2) continue;
                var itemPath = parts.slice(1).join("\t");
                var itemSize = parseNumber(parts[0]);
                if (!safeHomePath(itemPath) || itemSize <= 0) continue;
                hasRows = true;
                rows.push({
                    path: itemPath,
                    size: itemSize,
                    label: itemPath.split("/").pop()
                });
                var key = summarizeCategoryForPath(itemPath);
                bucketMap[key] = (bucketMap[key] || 0) + itemSize;
            }
            if (!hasRows) {
                runQuietExit("du -sb " + shellQuote(pathValue) + " 2>/dev/null | awk '{print $1\"\\t\"$2}'", function(singleOut) {
                    var singleParts = String(singleOut).trim().split(/\t+/);
                    if (singleParts.length >= 2) {
                        var oneSize = parseNumber(singleParts[0]);
                        if (oneSize > 0) {
                            diskTopDirs = [{ path: pathValue, size: oneSize, label: pathValue.split("/").pop() }];
                            diskTotalBytes = oneSize;
                            diskCategoryBuckets = [{ name: summarizeCategoryForPath(pathValue), size: oneSize }];
                        } else {
                            diskTopDirs = [];
                            diskTotalBytes = 0;
                            diskCategoryBuckets = [];
                        }
                    } else {
                        diskTopDirs = [];
                        diskTotalBytes = 0;
                        diskCategoryBuckets = [];
                    }
                    diskLastAnalyzedTime = Date.now();
                    if (done) done();
                });
                return;
            }
            rows.sort(function(a, b) { return b.size - a.size; });
            diskTopDirs = rows.slice(0, 20);
            diskTotalBytes = 0;
            for (var k = 0; k < rows.length; k++) diskTotalBytes += rows[k].size;
            var bucketRows = [];
            for (var name in bucketMap) bucketRows.push({ name: name, size: bucketMap[name] });
            bucketRows.sort(function(a, b) { return b.size - a.size; });
            diskCategoryBuckets = bucketRows;
            diskLastAnalyzedTime = Date.now();
            if (done) done();
        });
    }

    function drillIntoPath(pathValue) {
        if (running || !pathValue) return;
        var stack = (diskScopeStack || []).slice();
        stack.push(diskScopePath);
        diskScopeStack = stack;
        diskScopePath = pathValue;
        running = true;
        statusText = "Scanning folder";
        scanDiskUsageAtPath(pathValue, function() {
            finishRunning("Idle");
        });
    }

    function drillBack() {
        if (running || (diskScopeStack && diskScopeStack.length === 0)) return;
        var stack = (diskScopeStack || []).slice();
        var parent = stack.pop();
        diskScopeStack = stack;
        diskScopePath = parent;
        running = true;
        statusText = "Loading";
        if (parent === "") {
            scanDiskUsage(function() {
                finishRunning("Idle");
            });
        } else {
            scanDiskUsageAtPath(parent, function() {
                finishRunning("Idle");
            });
        }
    }

    function cleanNow() {
        if (running) return;
        running = true;
        statusText = "Running cleanup";
        var before = totalCleanupBytes;
        var steps = [];

        if (cleanupCache) {
            steps.push(function(next) {
                // Keep browser caches separate under cleanupBrowserCache toggle.
                var neg = buildCacheFindNegations();
                var cmd = "if [ -d \"$HOME/.cache\" ]; then find \"$HOME/.cache\" -mindepth 1 -maxdepth 1 " + neg + " -exec rm -rf -- {} + 2>/dev/null; fi";
                runQuietExit(cmd, function() { next(); });
            });
        }

        if (cleanupTrash) {
            steps.push(function(next) {
                var cmd = "rm -rf \"$HOME/.local/share/Trash/files\"/* \"$HOME/.local/share/Trash/info\"/* 2>/dev/null || true";
                runQuietExit(cmd, function() { next(); });
            });
        }

        if (cleanupBrowserCache) {
            steps.push(function(next) {
                var cmd = "rm -rf \"$HOME/.cache/mozilla\" \"$HOME/.cache/google-chrome\" \"$HOME/.cache/chromium\" 2>/dev/null || true";
                runQuietExit(cmd, function() { next(); });
            });
        }

        if (cleanupTmp) {
            steps.push(function(next) {
                var age = Math.max(1, parseInt(tmpAgeDays) || 3);
                var cmd = "find /tmp -maxdepth 1 -user \"$USER\" -mtime +" + age + " -exec rm -rf -- {} + 2>/dev/null || true";
                runQuietExit(cmd, function() { next(); });
            });
        }

        runSequence(steps, function() {
            // Only refresh cleanup totals after "Clean Now". Skip scanDiskUsage here
            // to avoid flooding the shell theme worker. User can refresh disk tab manually.
            Qt.callLater(function() {
                estimateCleanup(function() {
                    var reclaimed = Math.max(0, before - totalCleanupBytes);
                    lastCleanupBytes = reclaimed;
                    lastCleanupLabel = formatBytes(reclaimed);
                    finishRunning("Cleanup completed");
                });
            });
        });
    }

    // ---- Docker ----
    property string dockerPruneFilter: ""       // e.g. "24h" for --filter "until=24h"
    property bool dockerSystemPruneVolumes: false
    property bool dockerSystemPruneAll: true

    function parseDockerSize(str) {
        if (!str || typeof str !== "string") return 0;
        var s = str.replace(/\s*\([^)]*\)\s*$/, "").trim();  // strip " (65%)"
        s = s.replace(/(\d+(?:[.,]\d+)?)\s*([KMGTP])iB/gi, function(_, num, pfx) {
            return String(num).replace(",", ".") + " " + pfx.toUpperCase() + "B";
        });
        var m = s.match(/^([\d.]+)\s*([KMGTP]?B)$/i);
        if (!m) return 0;
        var n = parseFloat(String(m[1]).replace(",", "."));
        if (isNaN(n)) return 0;
        var u = (m[2] || "B").toUpperCase();
        if (u === "B") return n;
        if (u === "KB") return n * 1024;
        if (u === "MB") return n * 1024 * 1024;
        if (u === "GB") return n * 1024 * 1024 * 1024;
        if (u === "TB") return n * 1024 * 1024 * 1024 * 1024;
        return n;
    }

    function checkDocker(done) {
        runQuietExit("command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 && echo ok", function(out) {
            dockerAvailable = (String(out).trim() === "ok");
            if (done) done();
        });
    }

    function refreshDocker(done) {
        if (!dockerAvailable) {
            if (done) done();
            return;
        }
        // docker system df: table with TYPE, TOTAL, ACTIVE, SIZE, RECLAIMABLE
        runQuietExit("docker system df 2>/dev/null", function(out) {
            var lines = String(out).trim().split("\n");
            var breakdown = [];
            var totalBytes = 0;
            var reclaimableBytes = 0;
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i].trim();
                if (!line || line.indexOf("TYPE") === 0) continue;
                var cols = line.split(/\s{2,}/).map(function(c) { return c.trim(); });
                if (cols.length < 5) continue;
                var typeName = cols.slice(0, cols.length - 4).join(" ");
                var sizeStr = cols[cols.length - 2];
                var reclaimStr = cols[cols.length - 1];
                var sizeB = parseDockerSize(sizeStr);
                var reclaimB = parseDockerSize(reclaimStr);
                totalBytes += sizeB;
                reclaimableBytes += reclaimB;
                var pct = sizeB > 0 ? Math.round(100 * reclaimB / sizeB) : 0;
                breakdown.push({
                    type: typeName,
                    size: sizeStr,
                    reclaimable: reclaimStr,
                    reclaimableBytes: reclaimB,
                    reclaimablePct: pct
                });
            }
            dockerBreakdown = breakdown;
            dockerTotalSize = formatBytes(totalBytes);
            dockerReclaimable = formatBytes(reclaimableBytes);
            if (done) done();
        });
    }

    function dockerPruneFilterArgs() {
        var f = String(dockerPruneFilter || "").trim();
        if (!f) return "";
        return " --filter \"until=" + f.replace(/"/g, "") + "\"";
    }

    function dockerPruneContainers(done) {
        if (running || !dockerAvailable) return;
        running = true;
        statusText = "Pruning Docker containers";
        var cmd = "docker container prune -f" + dockerPruneFilterArgs() + " 2>/dev/null";
        runQuietExit(cmd, function() {
            Qt.callLater(function() {
                refreshDocker(function() {
                    finishRunning("Idle");
                    if (done) done();
                });
            });
        });
    }

    function dockerPruneImages(done) {
        if (running || !dockerAvailable) return;
        running = true;
        statusText = "Pruning Docker images";
        var cmd = "docker image prune -af 2>/dev/null";  // -a = all unused, -f = force
        runQuietExit(cmd, function() {
            Qt.callLater(function() {
                refreshDocker(function() {
                    finishRunning("Idle");
                    if (done) done();
                });
            });
        });
    }

    function dockerPruneVolumes(done) {
        if (running || !dockerAvailable) return;
        running = true;
        statusText = "Pruning Docker volumes";
        var cmd = "docker volume prune -f 2>/dev/null";
        runQuietExit(cmd, function() {
            Qt.callLater(function() {
                refreshDocker(function() {
                    finishRunning("Idle");
                    if (done) done();
                });
            });
        });
    }

    function dockerPruneBuildCache(done) {
        if (running || !dockerAvailable) return;
        running = true;
        statusText = "Pruning Docker build cache";
        var cmd = "docker builder prune -af 2>/dev/null";
        runQuietExit(cmd, function() {
            Qt.callLater(function() {
                refreshDocker(function() {
                    finishRunning("Idle");
                    if (done) done();
                });
            });
        });
    }

    function dockerSystemPrune(done) {
        if (running || !dockerAvailable) return;
        running = true;
        statusText = "Docker system prune";
        var cmd = "docker system prune -f";
        if (dockerSystemPruneAll) cmd += " -a";
        if (dockerSystemPruneVolumes) cmd += " --volumes";
        cmd += dockerPruneFilterArgs() + " 2>/dev/null";
        runQuietExit(cmd, function() {
            Qt.callLater(function() {
                refreshDocker(function() {
                    finishRunning("Idle");
                    if (done) done();
                });
            });
        });
    }
}
