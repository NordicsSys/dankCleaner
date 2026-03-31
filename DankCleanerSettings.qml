import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "dankCleaner"

    StyledText {
        width: parent.width
        text: "Dank Cleaner Settings"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "Safe mode cleaner: user cache, trash, browser cache, and optional old /tmp files."
        wrapMode: Text.WordWrap
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    StyledRect {
        width: parent.width
        height: cleanupColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: cleanupColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Cleanup Categories"
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                font.weight: Font.Medium
            }

            ToggleSetting {
                settingKey: "cleanupCache"
                label: "Clean ~/.cache"
                description: "Remove cache files from your home cache directory"
                defaultValue: true
            }

            StringSetting {
                settingKey: "cacheExcludeNames"
                label: "Never remove under ~/.cache (names)"
                description: "Top-level names kept when cleaning cache (comma or newline). Example: yay keeps ~/.cache/yay including vcs.json"
                placeholder: "yay"
                defaultValue: ""
            }

            ToggleSetting {
                settingKey: "cleanupTrash"
                label: "Clean Trash"
                description: "Empty ~/.local/share/Trash/files and info"
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "cleanupBrowserCache"
                label: "Clean browser cache"
                description: "Cleans mozilla/chrome/chromium cache directories if present"
                defaultValue: true
            }

            ToggleSetting {
                settingKey: "cleanupTmp"
                label: "Clean old /tmp files (user-owned only)"
                description: "Only removes /tmp entries owned by your user and older than threshold"
                defaultValue: false
            }

            StringSetting {
                settingKey: "tmpAgeDays"
                label: "Age threshold for /tmp (days)"
                description: "Files older than this are eligible for cleanup"
                placeholder: "3"
                defaultValue: "3"
            }
        }
    }

    StyledRect {
        width: parent.width
        height: analysisColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: analysisColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Disk Analyzer"
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                font.weight: Font.Medium
            }

            StringSetting {
                settingKey: "diskAnalyzerPaths"
                label: "Disk analyzer paths"
                description: "Top-level usage chart source paths (home folder only). Prefer non-overlapping roots so the Paths total does not double-count."
                placeholder: "~/Downloads,~/Documents,~/Videos,~/Pictures"
                defaultValue: "~/Downloads\n~/Documents\n~/Videos\n~/Pictures"
            }
        }
    }

    StyledRect {
        width: parent.width
        height: dockerColumn.implicitHeight + Theme.spacingL * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh

        Column {
            id: dockerColumn
            anchors.fill: parent
            anchors.margins: Theme.spacingL
            spacing: Theme.spacingM

            StyledText {
                text: "Docker cleanup"
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                font.weight: Font.Medium
            }

            ToggleSetting {
                settingKey: "dockerSystemPruneVolumes"
                label: "Include volumes in full prune"
                description: "When using System prune, also remove unused volumes (--volumes)"
                defaultValue: false
            }

            ToggleSetting {
                settingKey: "dockerSystemPruneAll"
                label: "Remove all unused images in full prune"
                description: "When using System prune, use -a to remove all unused images, not just dangling"
                defaultValue: true
            }

            StringSetting {
                settingKey: "dockerPruneFilter"
                label: "Time filter (e.g. 24h, 168h)"
                description: "Optional: only remove resources older than this (used with container prune and system prune)"
                placeholder: ""
                defaultValue: ""
            }
        }
    }
}
