import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    popoutWidth: 640
    popoutHeight: 440

    property string _settingsSignature: ""

    function _settingsSignatureFrom(data) {
        if (!data) return "";
        return [
            data.cleanupCache !== false,
            data.cleanupTrash !== false,
            data.cleanupBrowserCache !== false,
            data.cleanupTmp === true,
            String(parseInt(data.tmpAgeDays, 10) || 3),
            String(data.diskAnalyzerPaths || ""),
            String(data.cacheExcludeNames || ""),
            String(data.dockerPruneFilter || ""),
            data.dockerSystemPruneVolumes === true,
            data.dockerSystemPruneAll !== false
        ].join("\x1e");
    }

    onPluginDataChanged: {
        if (!pluginData) return;
        var nextSig = _settingsSignatureFrom(pluginData);
        CleanerService.cleanupCache = pluginData.cleanupCache !== false;
        CleanerService.cleanupTrash = pluginData.cleanupTrash !== false;
        CleanerService.cleanupBrowserCache = pluginData.cleanupBrowserCache !== false;
        CleanerService.cleanupTmp = pluginData.cleanupTmp === true;
        CleanerService.tmpAgeDays = parseInt(pluginData.tmpAgeDays, 10) || 3;
        CleanerService.diskAnalyzerPaths = pluginData.diskAnalyzerPaths || "~/Downloads\n~/Documents\n~/Videos\n~/Pictures";
        CleanerService.cacheExcludeNames = pluginData.cacheExcludeNames || "";
        CleanerService.dockerPruneFilter = pluginData.dockerPruneFilter || "";
        CleanerService.dockerSystemPruneVolumes = pluginData.dockerSystemPruneVolumes === true;
        CleanerService.dockerSystemPruneAll = pluginData.dockerSystemPruneAll !== false;
        if (nextSig === _settingsSignature)
            return;
        _settingsSignature = nextSig;
        Qt.callLater(function() {
            CleanerService.refreshAll();
        });
    }

    popoutContent: Component {
        PopoutComponent {
            DankCleanerPopout {
                width: popoutWidth
                height: popoutHeight - Theme.spacingXS * 2
            }
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                name: CleanerService.running ? "hourglass_top" : "cleaning_services"
                color: CleanerService.running ? "#FF9800" : Theme.primary
                size: root.iconSize
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: CleanerService.running ? "Scanning..." : CleanerService.totalCleanupLabel
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 2

            DankIcon {
                name: CleanerService.running ? "hourglass_top" : "cleaning_services"
                color: CleanerService.running ? "#FF9800" : Theme.primary
                size: root.iconSize
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: CleanerService.running ? "..." : CleanerService.totalCleanupShort
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeXSmall
            }
        }
    }
}
