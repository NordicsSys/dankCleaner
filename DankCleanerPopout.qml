import QtQuick
import QtQuick.Layouts
import qs.Common
import qs.Widgets

Column {
    id: root
    spacing: Theme.spacingS

    function maxDiskRowSize() {
        var rows = CleanerService.diskTopDirs || [];
        if (rows.length === 0) return 1;
        var maxV = rows[0].size || 1;
        return Math.max(1, maxV);
    }

    function pieColor(index) {
        var palette = [
            Theme.primary,
            "#4CAF50",
            "#FF9800",
            "#03A9F4",
            "#AB47BC",
            "#EF5350"
        ];
        return palette[index % palette.length];
    }

    DankTabBar {
        id: tabBar
        width: parent.width - Theme.spacingS * 2
        anchors.horizontalCenter: parent.horizontalCenter
        currentIndex: 0
        model: [
            { text: "Cleanup", icon: "cleaning_services" },
            { text: "Docker", icon: "storage" },
            { text: "Disk Analyzer", icon: "pie_chart" }
        ]
        onTabClicked: function(index) { tabBar.currentIndex = index; }
    }

    Item {
        visible: tabBar.currentIndex === 0
        width: parent.width
        height: parent.height - tabBar.height - Theme.spacingS * 2

        Column {
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            spacing: Theme.spacingS

            Rectangle {
                width: parent.width
                height: 52
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh

                Row {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS
                    spacing: Theme.spacingS

                    Column {
                        width: parent.width - cleanButton.width - Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        StyledText {
                            text: "Reclaimable space: " + CleanerService.formatBytes(CleanerService.totalCleanupBytes)
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            color: Theme.surfaceText
                            width: parent.width
                            elide: Text.ElideRight
                        }

                        StyledText {
                            text: CleanerService.statusText + " • Last clean: " + CleanerService.lastCleanupLabel
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            width: parent.width
                            elide: Text.ElideRight
                        }
                    }

                    DankButton {
                        id: cleanButton
                        text: CleanerService.running ? "Working..." : "Clean Now"
                        iconName: "auto_fix_high"
                        enabled: !CleanerService.running
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: CleanerService.cleanNow()
                    }
                }
            }

            GridLayout {
                width: parent.width
                columns: 2
                columnSpacing: Theme.spacingS
                rowSpacing: Theme.spacingS

                Repeater {
                    model: [
                        {
                            label: "User Cache",
                            enabled: CleanerService.cleanupCache,
                            value: CleanerService.cacheBytes
                        },
                        {
                            label: "Trash",
                            enabled: CleanerService.cleanupTrash,
                            value: CleanerService.trashBytes
                        },
                        {
                            label: "Browser Cache",
                            enabled: CleanerService.cleanupBrowserCache,
                            value: CleanerService.browserCacheBytes
                        },
                        {
                            label: "Old /tmp (user only)",
                            enabled: CleanerService.cleanupTmp,
                            value: CleanerService.tmpBytes
                        }
                    ]

                    Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        height: 62
                        radius: Theme.cornerRadius
                        color: Theme.surfaceContainerHigh

                        Column {
                            anchors.fill: parent
                            anchors.margins: Theme.spacingS
                            spacing: Theme.spacingXS

                            StyledText {
                                text: modelData.label
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }

                            StyledText {
                                text: CleanerService.formatBytes(modelData.value)
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Bold
                                color: modelData.enabled ? Theme.primary : Theme.surfaceVariantText
                            }

                            StyledText {
                                text: modelData.enabled ? "Enabled" : "Disabled"
                                font.pixelSize: Theme.fontSizeSmall
                                color: modelData.enabled ? Theme.primary : Theme.surfaceVariantText
                            }
                        }
                    }
                }
            }

            Row {
                width: parent.width
                spacing: Theme.spacingS

                DankButton {
                    text: "Rescan"
                    iconName: "refresh"
                    enabled: !CleanerService.running
                    onClicked: CleanerService.refreshAll()
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Safe mode: only user-space cache/temp/trash paths are touched."
                    font.pixelSize: Theme.fontSizeXSmall
                    color: Theme.surfaceVariantText
                    width: parent.width - 120
                    elide: Text.ElideRight
                }
            }
        }
    }

    Item {
        visible: tabBar.currentIndex === 2
        width: parent.width
        height: parent.height - tabBar.height - Theme.spacingS * 2

        Column {
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            spacing: Theme.spacingS

            Rectangle {
                id: diskHeaderRect
                width: parent.width
                height: diskHeaderColumn.implicitHeight + Theme.spacingS * 2
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh

                Row {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS
                    spacing: Theme.spacingS

                    Column {
                        id: diskHeaderColumn
                        width: parent.width - diskHeaderButtons.width - Theme.spacingS
                        spacing: 2
                        anchors.verticalCenter: parent.verticalCenter

                        StyledText {
                            width: parent.width
                            text: CleanerService.diskScopePath
                                ? ("In: " + (CleanerService.diskScopePath.indexOf(CleanerService.homeDir) === 0
                                    ? "~" + CleanerService.diskScopePath.substring(CleanerService.homeDir.length)
                                    : CleanerService.diskScopePath) + " • " + CleanerService.formatBytes(CleanerService.diskTotalBytes))
                                : ("Home: " + CleanerService.formatBytes(CleanerService.diskHomeTotalBytes)
                                    + "  •  Paths: " + CleanerService.formatBytes(CleanerService.diskTotalBytes))
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            color: Theme.surfaceText
                            elide: Text.ElideMiddle
                        }

                        StyledText {
                            text: "Last analyzed: " + CleanerService.diskLastAnalyzedLabel()
                            font.pixelSize: Theme.fontSizeXSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    Row {
                        id: diskHeaderButtons
                        spacing: Theme.spacingXS
                        anchors.verticalCenter: parent.verticalCenter

                        DankButton {
                            visible: CleanerService.diskScopeStack.length > 0
                            text: "Back"
                            iconName: "arrow_back"
                            enabled: !CleanerService.running
                            onClicked: CleanerService.drillBack()
                        }
                        DankButton {
                            text: "Analyze"
                            iconName: "refresh"
                            enabled: !CleanerService.running
                            onClicked: CleanerService.scanDiskUsage()
                        }
                    }
                }
            }

            Row {
                width: parent.width
                height: parent.height - diskHeaderRect.height - Theme.spacingS
                spacing: Theme.spacingS

                Rectangle {
                    width: parent.width * 0.62
                    height: parent.height
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        spacing: Theme.spacingXS

                        StyledText {
                            text: "Top directories"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        Flickable {
                            width: parent.width
                            height: parent.height - 24
                            contentHeight: diskBars.implicitHeight
                            clip: true

                            Column {
                                id: diskBars
                                width: parent.width
                                spacing: Theme.spacingXS

                                Repeater {
                                    model: CleanerService.diskTopDirs

                                    Item {
                                        required property var modelData
                                        width: diskBars.width
                                        height: diskRowCol.implicitHeight

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: CleanerService.drillIntoPath(modelData.path)
                                        }

                                        Column {
                                            id: diskRowCol
                                            width: parent.width
                                            spacing: 2

                                            StyledText {
                                                width: parent.width
                                                text: modelData.path
                                                elide: Text.ElideMiddle
                                                font.pixelSize: Theme.fontSizeXSmall
                                                color: Theme.surfaceVariantText
                                            }

                                            Rectangle {
                                                width: parent.width
                                                height: 10
                                                radius: 5
                                                color: Theme.surfaceVariant

                                                Rectangle {
                                                    width: Math.max(
                                                        2,
                                                        parent.width * (modelData.size / root.maxDiskRowSize())
                                                    )
                                                    height: parent.height
                                                    radius: parent.radius
                                                    color: Theme.primary
                                                }
                                            }

                                            StyledText {
                                                text: CleanerService.formatBytes(modelData.size)
                                                font.pixelSize: Theme.fontSizeXSmall
                                                color: Theme.surfaceText
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    visible: CleanerService.diskTopDirs.length === 0
                                    width: parent.width
                                    height: 56
                                    color: "transparent"
                                    StyledText {
                                        anchors.centerIn: parent
                                        text: CleanerService.running ? "Analyzing..." : "No disk data available."
                                        color: Theme.surfaceVariantText
                                        font.pixelSize: Theme.fontSizeSmall
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width * 0.38 - Theme.spacingS
                    height: parent.height
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh

                    Column {
                        anchors.fill: parent
                        anchors.margins: Theme.spacingS
                        spacing: Theme.spacingS

                        StyledText {
                            text: "Category split"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        Canvas {
                            id: pieCanvas
                            width: Math.min(parent.width, 140)
                            height: width
                            anchors.horizontalCenter: parent.horizontalCenter

                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                var buckets = CleanerService.diskCategoryBuckets || [];
                                var total = 0;
                                for (var i = 0; i < buckets.length; i++) total += buckets[i].size;
                                if (total <= 0) return;

                                var cx = width / 2;
                                var cy = height / 2;
                                var r = Math.min(cx, cy) - 4;
                                var start = -Math.PI / 2;

                                for (var j = 0; j < buckets.length; j++) {
                                    var part = buckets[j].size / total;
                                    var end = start + (Math.PI * 2 * part);
                                    ctx.beginPath();
                                    ctx.moveTo(cx, cy);
                                    ctx.arc(cx, cy, r, start, end, false);
                                    ctx.closePath();
                                    ctx.fillStyle = root.pieColor(j);
                                    ctx.fill();
                                    start = end;
                                }

                                ctx.beginPath();
                                ctx.arc(cx, cy, r * 0.5, 0, Math.PI * 2, false);
                                ctx.fillStyle = Theme.surfaceContainerHigh;
                                ctx.fill();
                            }

                            Connections {
                                target: CleanerService
                                function onDiskCategoryBucketsChanged() {
                                    pieCanvas.requestPaint();
                                }
                            }
                        }

                        Flickable {
                            width: parent.width
                            height: parent.height - pieCanvas.height - 56
                            contentHeight: legendColumn.implicitHeight
                            clip: true

                            Column {
                                id: legendColumn
                                width: parent.width
                                spacing: Theme.spacingXS

                                Repeater {
                                    model: CleanerService.diskCategoryBuckets
                                    Row {
                                        required property var modelData
                                        required property int index
                                        width: legendColumn.width
                                        spacing: Theme.spacingXS

                                        Rectangle {
                                            width: 10
                                            height: 10
                                            radius: 5
                                            color: root.pieColor(index)
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        StyledText {
                                            width: parent.width - 16
                                            text: modelData.name + " • " + CleanerService.formatBytes(modelData.size)
                                            elide: Text.ElideRight
                                            font.pixelSize: Theme.fontSizeXSmall
                                            color: Theme.surfaceText
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Item {
        visible: tabBar.currentIndex === 1
        width: parent.width
        height: parent.height - tabBar.height - Theme.spacingS * 2

        Connections {
            target: tabBar
            function onCurrentIndexChanged() {
                if (tabBar.currentIndex === 1) {
                    CleanerService.checkDocker(function() {
                        CleanerService.refreshDocker(function() {});
                    });
                }
            }
        }
        Component.onCompleted: {
            if (tabBar.currentIndex === 1) {
                CleanerService.checkDocker(function() {
                    CleanerService.refreshDocker(function() {});
                });
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: Theme.spacingS
            spacing: Theme.spacingS

            Rectangle {
                width: parent.width
                height: 52
                radius: Theme.cornerRadius
                color: Theme.surfaceContainerHigh

                Row {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS
                    spacing: Theme.spacingS

                    Column {
                        width: parent.width - dockerRefreshBtn.width - Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        StyledText {
                            text: CleanerService.dockerAvailable
                                  ? ("Docker storage: " + CleanerService.dockerTotalSize + " • Reclaimable: " + CleanerService.dockerReclaimable)
                                  : "Docker not detected. Install Docker or ensure it's in PATH."
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            color: Theme.surfaceText
                            width: parent.width
                            elide: Text.ElideRight
                        }

                        StyledText {
                            visible: CleanerService.dockerAvailable
                            text: CleanerService.statusText + " • Tap Refresh to scan"
                            font.pixelSize: Theme.fontSizeXSmall
                            color: Theme.surfaceVariantText
                            width: parent.width
                            elide: Text.ElideRight
                        }
                    }

                    DankButton {
                        id: dockerRefreshBtn
                        text: "Refresh"
                        iconName: "refresh"
                        enabled: !CleanerService.running
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: {
                            CleanerService.checkDocker(function() {
                                CleanerService.refreshDocker(function() {});
                            });
                        }
                    }
                }
            }

            Item {
                visible: !CleanerService.dockerAvailable
                width: parent.width
                height: 40
                StyledText {
                    anchors.centerIn: parent
                    text: "Start Docker daemon or install Docker to use this tab."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }

            Flickable {
                visible: CleanerService.dockerAvailable
                width: parent.width
                height: parent.height - 60
                clip: true
                contentHeight: dockerColumn.implicitHeight

                Column {
                    id: dockerColumn
                    width: parent.width
                    spacing: Theme.spacingS

                    Repeater {
                        model: CleanerService.dockerBreakdown

                        Rectangle {
                            required property var modelData
                            width: dockerColumn.width
                            height: 36
                            radius: 4
                            color: Qt.rgba(Theme.surfaceVariant.r, Theme.surfaceVariant.g, Theme.surfaceVariant.b, 0.3)

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.spacingS
                                anchors.rightMargin: Theme.spacingS
                                spacing: Theme.spacingS
                                anchors.verticalCenter: parent.verticalCenter

                                StyledText {
                                    text: modelData.type
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceText
                                    width: 100
                                }
                                StyledText {
                                    text: modelData.size
                                    font.pixelSize: Theme.fontSizeXSmall
                                    color: Theme.surfaceVariantText
                                }
                                StyledText {
                                    text: modelData.reclaimable
                                    font.pixelSize: Theme.fontSizeXSmall
                                    color: Theme.primary
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.surfaceVariant
                    }

                    StyledText {
                        text: "Selective cleanup"
                        font.pixelSize: Theme.fontSizeXSmall
                        font.weight: Font.Medium
                        color: Theme.surfaceVariantText
                    }

                    Flow {
                        width: parent.width
                        spacing: Theme.spacingS

                        DankButton {
                            text: "Containers"
                            iconName: "stop_circle"
                            enabled: !CleanerService.running
                            onClicked: CleanerService.dockerPruneContainers(function() {})
                        }
                        DankButton {
                            text: "Images"
                            iconName: "image"
                            enabled: !CleanerService.running
                            onClicked: CleanerService.dockerPruneImages(function() {})
                        }
                        DankButton {
                            text: "Volumes"
                            iconName: "folder"
                            enabled: !CleanerService.running
                            onClicked: CleanerService.dockerPruneVolumes(function() {})
                        }
                        DankButton {
                            text: "Build cache"
                            iconName: "build"
                            enabled: !CleanerService.running
                            onClicked: CleanerService.dockerPruneBuildCache(function() {})
                        }
                    }

                    StyledText {
                        text: "Full cleanup"
                        font.pixelSize: Theme.fontSizeXSmall
                        font.weight: Font.Medium
                        color: Theme.surfaceVariantText
                    }

                    DankButton {
                        text: "System prune"
                        iconName: "delete_sweep"
                        enabled: !CleanerService.running
                        onClicked: CleanerService.dockerSystemPrune(function() {})
                    }

                    StyledText {
                        visible: CleanerService.dockerPruneFilter.length > 0
                        text: "Time filter: " + CleanerService.dockerPruneFilter
                        font.pixelSize: Theme.fontSizeXSmall
                        color: Theme.surfaceVariantText
                    }
                }
            }
        }
    }

}
