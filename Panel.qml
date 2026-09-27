import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.UPower
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Standalone panel plugin (launcher-only, no bar icon): keepLoaded in
// manifest.json keeps this Item alive for the whole shell session so the
// UPower.onBattery watcher and preset apply logic keep running whether or
// not the card is open. Summoned via the omarchy menu entry
// ("trigger.power-mode" in ~/.config/omarchy/extensions/omarchy-menu.jsonc),
// which calls `omarchy-shell shell toggle power-mode`.
//
// Nothing here is specific to one machine: the monitor, its resolutions,
// its refresh rates, its scale options, and the available power profiles
// are all read live via hyprctl/power-profiles-daemon, the same way
// Omarchy's own Display and Power panels do it. Defaults (which monitor,
// which mode, which scale, which profile) are resolved once real data
// arrives (resolveDefaults()) rather than hardcoded.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  property var monitors: []
  property var profiles: []
  property bool pendingApply: false
  property bool settingsLoaded: false

  property string monitorSetting: ""
  property string acModeSetting: ""
  property string batteryModeSetting: ""
  property string acProfile: ""
  property string batteryProfile: ""
  property string acScale: ""
  property string batteryScale: ""

  // v1 -> v2 settings migration (old versions stored a bare Hz number
  // instead of a full "WxH@Hz" mode string). -1 = nothing to migrate.
  property real pendingAcHzMigration: -1
  property real pendingBatteryHzMigration: -1

  readonly property bool onBattery: UPower.onBattery
  readonly property string activeMode: onBattery ? "battery" : "ac"
  readonly property bool batteryPresent: {
    var device = UPower.displayDevice
    return !!(device && device.isPresent)
  }

  readonly property var modesInfo: Model.modesFor(root.monitors, root.monitorSetting)

  function open(payloadJson) {
    root.opened = true
    root.refresh()
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "power-mode")
    else close()
  }

  function currentMonitor() {
    return Model.findMonitor(root.monitors, root.monitorSetting)
  }

  function profileLabel(name) {
    return Model.profileLabel(name)
  }

  // ---------------------------------------------------------- settings

  FileView {
    id: settingsFile
    path: Quickshell.env("HOME") + "/.config/omarchy/plugins/power-mode/settings.json"
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.applySettingsJson(text())
    onLoadFailed: root.applySettingsJson("{}")
  }

  function applySettingsJson(raw) {
    var parsed = {}
    try { parsed = JSON.parse(raw || "{}") || {} } catch (e) { parsed = {} }

    root.monitorSetting = String(parsed.monitor || "")
    root.acModeSetting = String(parsed.acMode || "")
    root.batteryModeSetting = String(parsed.batteryMode || "")
    root.acProfile = String(parsed.acProfile || "")
    root.batteryProfile = String(parsed.batteryProfile || "")
    root.acScale = String(parsed.acScale || "")
    root.batteryScale = String(parsed.batteryScale || "")

    root.pendingAcHzMigration = (!root.acModeSetting && parsed.acHz) ? Number(parsed.acHz) : -1
    root.pendingBatteryHzMigration = (!root.batteryModeSetting && parsed.batteryHz) ? Number(parsed.batteryHz) : -1

    root.settingsLoaded = true
    root.requestApply()
  }

  function saveSettings() {
    var data = {
      monitor: root.monitorSetting,
      acMode: root.acModeSetting,
      batteryMode: root.batteryModeSetting,
      acProfile: root.acProfile,
      batteryProfile: root.batteryProfile,
      acScale: root.acScale,
      batteryScale: root.batteryScale
    }
    settingsFile.setText(JSON.stringify(data, null, 2) + "\n")
  }

  // Fills in anything still unset once real data is available: which
  // monitor, its current mode as the starting preset, its current scale,
  // and the closest sensible power profile actually offered on this
  // machine. Also finishes any pending v1->v2 migration. Idempotent -- only
  // writes settings.json when something actually changed.
  function pickDefaultProfile(preferred) {
    for (var i = 0; i < preferred.length; i++) {
      if (root.profiles.indexOf(preferred[i]) !== -1) return preferred[i]
    }
    return root.profiles.length > 0 ? root.profiles[0] : ""
  }

  function resolveDefaults() {
    // Real settings load asynchronously (FileView), but monitors/profiles
    // fetch immediately on Component.onCompleted and can complete first.
    // Without this guard, that race could see still-blank properties, treat
    // them as "never configured", and save a snapshot of whatever's
    // currently live over the real (not-yet-loaded) saved preset.
    if (!root.settingsLoaded) return

    var mon = root.currentMonitor()
    if (!mon && root.monitors.length > 0 && !root.monitorSetting) mon = root.monitors[0]

    var changed = false

    if (mon) {
      if (root.pendingAcHzMigration >= 0) {
        root.acModeSetting = mon.width + "x" + mon.height + "@" + root.pendingAcHzMigration
        root.pendingAcHzMigration = -1
        changed = true
      }
      if (root.pendingBatteryHzMigration >= 0) {
        root.batteryModeSetting = mon.width + "x" + mon.height + "@" + root.pendingBatteryHzMigration
        root.pendingBatteryHzMigration = -1
        changed = true
      }
      if (!root.monitorSetting) { root.monitorSetting = mon.name; changed = true }
      if (!root.acModeSetting) { root.acModeSetting = mon.width + "x" + mon.height + "@" + Math.round(mon.refreshRate); changed = true }
      if (!root.batteryModeSetting) { root.batteryModeSetting = mon.width + "x" + mon.height + "@" + Math.round(mon.refreshRate); changed = true }
      if (!root.acScale) { root.acScale = String(mon.scale); changed = true }
      if (!root.batteryScale) { root.batteryScale = String(mon.scale); changed = true }
    }

    if (root.profiles.length > 0) {
      if (!root.acProfile) { root.acProfile = root.pickDefaultProfile(["performance", "balanced"]); changed = true }
      if (!root.batteryProfile) { root.batteryProfile = root.pickDefaultProfile(["power-saver", "balanced"]); changed = true }
    }

    if (changed) root.saveSettings()
  }

  function setMonitor(name) {
    if (root.monitorSetting === name) return
    root.monitorSetting = name
    // The old mode/scale likely doesn't apply to a different output.
    root.acModeSetting = ""
    root.batteryModeSetting = ""
    root.acScale = ""
    root.batteryScale = ""
    root.saveSettings()
    root.resolveDefaults()
  }

  // Picks here only stage the change to settings.json -- they never apply
  // live, even for the currently active mode. "Apply now" and the automatic
  // AC/battery-change watcher are the only things that call requestApply().
  function setMode(mode, value) {
    if (mode === "ac") root.acModeSetting = value
    else root.batteryModeSetting = value
    root.saveSettings()
  }

  function setScale(mode, value) {
    if (mode === "ac") root.acScale = value
    else root.batteryScale = value
    root.saveSettings()
  }

  function setProfile(mode, profile) {
    if (mode === "ac") root.acProfile = profile
    else root.batteryProfile = profile
    root.saveSettings()
  }

  // ---------------------------------------------------------- live data + apply

  function updateMonitors(raw) {
    root.monitors = Model.parseMonitorsJson(raw)
  }

  function updateProfiles(raw) {
    var parsed = Model.parseProfiles(raw)
    if (parsed.profiles.length === 0) return
    root.profiles = parsed.profiles
  }

  function refresh() {
    if (!monitorsProc.running) monitorsProc.running = true
    if (!profilesProc.running) profilesProc.running = true
  }

  function requestApply() {
    if (!root.settingsLoaded) return
    root.pendingApply = true
    if (!monitorsProc.running) monitorsProc.running = true
  }

  function doApply() {
    var mode = root.activeMode
    var modeString = mode === "battery" ? root.batteryModeSetting : root.acModeSetting
    var scale = mode === "battery" ? root.batteryScale : root.acScale
    var profile = mode === "battery" ? root.batteryProfile : root.acProfile
    var mon = root.currentMonitor()
    var parsed = Model.parseModeString(modeString)

    if (mon && parsed && Model.isValidScale(scale) && Model.isValidOutputName(mon.name)) {
      var lua = "hl.monitor({ output = \"" + mon.name + "\", mode = \""
        + parsed.width + "x" + parsed.height + "@" + parsed.hz + "\", position = \""
        + mon.x + "x" + mon.y + "\", scale = " + scale + " })"
      hyprProc.fallbackLine = mon.name + "," + parsed.width + "x" + parsed.height + "@" + parsed.hz
        + "," + mon.x + "x" + mon.y + "," + scale
      hyprProc.command = ["hyprctl", "eval", lua]
      hyprProc.running = true
    }

    if (profile) {
      profileProc.command = ["omarchy-powerprofiles-set", mode, profile]
      profileProc.running = true
    }
  }

  Component.onCompleted: root.refresh()

  Connections {
    target: UPower
    function onOnBatteryChanged() { root.requestApply() }
  }

  Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }

  Process {
    id: monitorsProc
    command: ["hyprctl", "-j", "monitors", "all"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.updateMonitors(text)
        root.resolveDefaults()
        if (root.pendingApply) {
          root.pendingApply = false
          root.doApply()
        }
      }
    }
  }

  Process {
    id: profilesProc
    command: ["omarchy-powerprofiles-list", "--active-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.updateProfiles(text)
        root.resolveDefaults()
      }
    }
  }

  // Hyprland's Lua-config parser needs `hyprctl eval` (verified on this
  // machine: `hyprctl keyword monitor ...` errors with "keyword can't work
  // with non-legacy parsers"). Omarchy documents Lua config as its standard
  // architecture, but if eval ever fails on a differently-configured
  // Hyprland, fall back to the legacy keyword form rather than silently
  // doing nothing.
  Process {
    id: hyprProc
    property string fallbackLine: ""
    stdout: StdioCollector { id: hyprOut; waitForEnd: true }
    onExited: function(exitCode) {
      var out = String(hyprOut.text || "").trim()
      if ((exitCode !== 0 || out !== "ok") && hyprProc.fallbackLine !== "") {
        hyprKeywordProc.command = ["hyprctl", "keyword", "monitor", hyprProc.fallbackLine]
        hyprKeywordProc.running = true
      }
    }
  }

  Process {
    id: hyprKeywordProc
    stdout: StdioCollector { waitForEnd: true }
  }

  Process {
    id: profileProc
    stdout: StdioCollector { waitForEnd: true }
  }

  // ---------------------------------------------------------- GUI

  PanelWindow {
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "power-mode"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
      anchors.fill: parent
      color: Qt.rgba(0, 0, 0, 0.55)

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.onEscapePressed: root.dismiss()

      Item {
        anchors.centerIn: parent
        width: card.implicitWidth
        height: card.implicitHeight

        MouseArea { anchors.fill: parent; onClicked: {} }

        BorderSurface {
          id: card
          color: Color.popups.background
          radius: Style.cornerRadius
          padding: Style.space(20)
          implicitWidth: column.implicitWidth + leftPadding + rightPadding
          implicitHeight: column.implicitHeight + topPadding + bottomPadding

          Column {
            id: column
            x: card.leftPadding
            y: card.topPadding
            width: Style.space(400)
            spacing: Style.space(14)

            Item {
              width: parent.width
              implicitHeight: heroLabels.implicitHeight

              Column {
                id: heroLabels
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Style.space(2)

                Text {
                  textFormat: Text.PlainText
                  text: "󰂄  Power Mode"
                  color: Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.bold: true
                  elide: Text.ElideRight
                  width: parent.width
                }

                Text {
                  textFormat: Text.PlainText
                  text: (root.onBattery ? "ON BATTERY" : "ON AC POWER") + " · " + root.monitorSetting
                  color: Color.muted
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                  elide: Text.ElideRight
                  width: parent.width
                }
              }
            }

            // ---------- Display picker (only when more than one output) ----------
            Row {
              id: monitorRow
              visible: root.monitors.length > 1
              width: parent.width
              spacing: Style.space(6)

              readonly property real cellWidth: root.monitors.length > 0
                ? (width - spacing * (root.monitors.length - 1)) / root.monitors.length
                : 0

              Repeater {
                model: root.monitors
                Button {
                  required property var modelData
                  width: monitorRow.cellWidth
                  text: modelData.name
                  fontSize: Style.font.bodySmall
                  bordered: true
                  active: root.monitorSetting === modelData.name
                  onClicked: root.setMonitor(modelData.name)
                }
              }
            }

            PanelSeparator { visible: root.monitors.length > 1; foreground: Color.popups.text }

            ModeSection {
              width: parent.width
              label: "ON AC POWER"
              active: !root.onBattery
              modeValue: root.acModeSetting
              scaleValue: root.acScale
              profileValue: root.acProfile
              onPickMode: function(m) { root.setMode("ac", m) }
              onPickScale: function(s) { root.setScale("ac", s) }
              onPickProfile: function(p) { root.setProfile("ac", p) }
            }

            PanelSeparator { visible: root.batteryPresent; foreground: Color.popups.text }

            ModeSection {
              width: parent.width
              visible: root.batteryPresent
              label: "ON BATTERY"
              active: root.onBattery
              modeValue: root.batteryModeSetting
              scaleValue: root.batteryScale
              profileValue: root.batteryProfile
              onPickMode: function(m) { root.setMode("battery", m) }
              onPickScale: function(s) { root.setScale("battery", s) }
              onPickProfile: function(p) { root.setProfile("battery", p) }
            }

            PanelSeparator { foreground: Color.popups.text }

            Item {
              width: parent.width
              implicitHeight: applyButton.implicitHeight

              Button {
                id: applyButton
                anchors.right: parent.right
                text: "Apply now"
                fontSize: Style.font.bodySmall
                bordered: true
                onClicked: root.requestApply()
              }
            }
          }
        }
      }
    }
  }

  component ModeSection: Column {
    id: section
    property string label: ""
    property bool active: false
    property string modeValue: ""
    property string scaleValue: ""
    property string profileValue: ""
    signal pickMode(string mode)
    signal pickScale(string scale)
    signal pickProfile(string profile)

    readonly property var parsedMode: Model.parseModeString(section.modeValue)
    readonly property string currentResolution: parsedMode ? (parsedMode.width + "x" + parsedMode.height) : ""
    readonly property var hzOptions: root.modesInfo.hzByResolution[section.currentResolution] || []
    readonly property var scaleOptions: parsedMode ? Model.scaleOptionsFor(parsedMode.width, parsedMode.height) : []

    spacing: Style.space(10)

    Item {
      width: parent.width
      implicitHeight: sectionHeader.implicitHeight

      PanelSectionHeader {
        id: sectionHeader
        text: section.label + (section.active ? " (ACTIVE)" : "")
        foreground: Color.popups.text
        fontFamily: Style.font.family
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // ---------- Resolution (only when the output has more than one) ----------
    Row {
      id: resRow
      visible: root.modesInfo.resolutions.length > 1
      width: parent.width
      spacing: Style.space(6)

      readonly property real cellWidth: root.modesInfo.resolutions.length > 0
        ? (width - spacing * (root.modesInfo.resolutions.length - 1)) / root.modesInfo.resolutions.length
        : 0

      Repeater {
        model: root.modesInfo.resolutions
        Button {
          required property var modelData
          width: resRow.cellWidth
          text: modelData
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          bordered: true
          active: section.currentResolution === modelData
          onClicked: {
            var hzList = root.modesInfo.hzByResolution[modelData] || []
            var hz = hzList.length > 0 ? hzList[0] : 60
            section.pickMode(modelData + "@" + hz)
          }
        }
      }
    }

    // ---------- Refresh rate, scoped to the resolution above ----------
    Row {
      id: hzRow
      width: parent.width
      spacing: Style.space(6)

      readonly property real cellWidth: section.hzOptions.length > 0
        ? (width - spacing * (section.hzOptions.length - 1)) / section.hzOptions.length
        : 0

      Repeater {
        model: section.hzOptions
        Button {
          required property var modelData
          width: hzRow.cellWidth
          text: modelData + "Hz"
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          bordered: true
          active: section.parsedMode && section.parsedMode.hz === modelData
          onClicked: section.pickMode(section.currentResolution + "@" + modelData)
        }
      }
    }

    // ---------- Scale ----------
    Row {
      id: scaleRow
      visible: section.scaleOptions.length > 1
      width: parent.width
      spacing: Style.space(6)

      readonly property real cellWidth: section.scaleOptions.length > 0
        ? (width - spacing * (section.scaleOptions.length - 1)) / section.scaleOptions.length
        : 0

      Repeater {
        model: section.scaleOptions
        Button {
          required property var modelData
          width: scaleRow.cellWidth
          text: modelData + "x"
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          bordered: true
          active: section.scaleValue === modelData
          onClicked: section.pickScale(modelData)
        }
      }
    }

    // ---------- Power profile ----------
    Row {
      id: profileRow
      width: parent.width
      spacing: Style.space(6)

      readonly property real cellWidth: root.profiles.length > 0
        ? (width - spacing * (root.profiles.length - 1)) / root.profiles.length
        : 0

      Repeater {
        model: root.profiles
        Button {
          required property var modelData
          width: profileRow.cellWidth
          text: root.profileLabel(String(modelData))
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          bordered: true
          active: section.profileValue === modelData
          onClicked: section.pickProfile(modelData)
        }
      }
    }
  }
}
