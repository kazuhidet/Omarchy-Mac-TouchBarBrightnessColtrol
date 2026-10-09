import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Touch Bar brightness, modeled on the built-in Display panel (omarchy.monitor).
// All hardware work goes through the CLI so the keys, the sync service and this
// panel share one code path: omarchy-brightness-touchbar sets the level and
// omarchy-brightness-touchbar-sync-mode switches the sync service. The commands
// run from this plugin's own bin/, so the slider works right after
// `omarchy plugin add`, before omarchy-brightness-touchbar-setup has linked them.
Panel {
  id: root
  moduleName: "kazu.touchbar"
  ipcTarget: "kazu.touchbar"
  manageIpc: false

  // Same glyph as the Touch Bar OSD, so the bar, panel and OSD read as one control.
  readonly property string touchbarIcon: "󰌓"

  property int brightnessPercent: 0
  property int pendingBrightnessPercent: 0
  property bool brightnessSetQueued: false
  property bool brightnessAvailable: false
  property string syncMode: "off"
  // The sync service, key bindings and PATH links come from the setup command.
  property bool setupDone: true
  // tiny-dfr's AdaptiveBrightness rewrites the Touch Bar whenever the display
  // brightness changes, overriding both this slider and the sync service.
  property bool tinyDfrAdaptive: false

  readonly property string binDir: String(Qt.resolvedUrl("bin")).replace(/^file:\/\//, "")

  // Carry sub-notch touchpad deltas between wheel events.
  property real wheelAccumulator: 0

  // "off" is labeled Manual: the service is stopped and only the keys and
  // this slider move the Touch Bar.
  readonly property var syncModes: [
    { value: "keyboard", label: "Keyboard" },
    { value: "ambient", label: "Ambient" },
    { value: "off", label: "Manual" }
  ]

  // Cursor model shared by keyboard and mouse, as in the Display panel:
  //   "brightness" - single slider row, selectedIndex = -1 sentinel
  //   "sync"       - horizontal row of sync mode pills
  //   "tinydfr"    - single fix button, only while tiny-dfr is adaptive
  property string focusSection: "brightness"
  property int selectedIndex: -1
  property bool cursorActive: false

  readonly property var visibleSections: !brightnessAvailable ? []
    : tinyDfrAdaptive ? ["brightness", "sync", "tinydfr"] : ["brightness", "sync"]

  function sectionFirstIndex(section) {
    if (section === "brightness") return -1
    if (section === "tinydfr") return 0
    return Math.max(0, syncModeIndex(syncMode))
  }

  function moveCursor(delta) {
    var sections = visibleSections
    if (!sections.length) return
    var sIdx = sections.indexOf(focusSection)
    var next = sIdx < 0 ? 0 : Math.max(0, Math.min(sections.length - 1, sIdx + delta))
    if (next === sIdx) return
    focusSection = sections[next]
    selectedIndex = sectionFirstIndex(focusSection)
  }

  function moveCursorH(delta) {
    if (focusSection !== "sync") return
    var next = selectedIndex + delta
    if (next < 0) next = 0
    if (next > syncModes.length - 1) next = syncModes.length - 1
    selectedIndex = next
  }

  function adjustBrightness(delta) {
    if (focusSection !== "brightness" || !brightnessAvailable) return
    setBrightness(root.brightnessPercent + delta)
  }

  function activateCursor() {
    if (focusSection === "tinydfr") { runTinyDfrFix(); return }
    if (focusSection === "sync" && !setupDone) { runSetup(); return }
    if (focusSection === "sync" && selectedIndex >= 0 && selectedIndex < syncModes.length)
      setSyncMode(syncModes[selectedIndex].value)
  }

  function syncModeIndex(mode) {
    for (var i = 0; i < syncModes.length; i++) {
      if (syncModes[i].value === mode) return i
    }
    return -1
  }

  function clampBrightness(value) {
    var n = Number(value)
    if (!isFinite(n)) return 1
    return Math.max(1, Math.min(100, Math.round(n)))
  }

  function syncLabel(mode) {
    if (mode === "keyboard") return "Follows keyboard backlight"
    if (mode === "ambient") return "Follows ambient light"
    return "Manual control"
  }

  // Run a plugin command with bin/ first on PATH, so the scripts find each other
  // whether or not setup has linked them into ~/.local/bin.
  function binCommand(args) {
    return ["bash", "-c", 'PATH="$0:$PATH"; exec "$@"', root.binDir].concat(args)
  }

  function runSetup() {
    setupProc.command = ["omarchy-launch-floating-terminal-with-presentation",
                         root.binDir + "/omarchy-brightness-touchbar-setup install --bindings"]
    if (!setupProc.running) setupProc.running = true
  }

  // Writing /etc/tiny-dfr needs sudo, so it runs in a terminal that can prompt.
  function runTinyDfrFix() {
    setupProc.command = ["omarchy-launch-floating-terminal-with-presentation",
                         root.binDir + "/omarchy-brightness-touchbar-setup tiny-dfr"]
    if (!setupProc.running) setupProc.running = true
  }

  function brightnessIpc(percent) {
    root.setBrightness(Number(percent))
    return "got " + root.pendingBrightnessPercent
  }

  function stateIpc() {
    return JSON.stringify({
      brightness: root.brightnessPercent,
      brightnessAvailable: root.brightnessAvailable,
      syncMode: root.syncMode,
      tinyDfrAdaptive: root.tinyDfrAdaptive
    })
  }

  IpcHandler {
    target: "kazu.touchbar"

    function brightness(percent: string): string { return root.brightnessIpc(percent) }
    function syncMode(mode: string): void { root.setSyncMode(mode) }
    function state(): string { return root.stateIpc() }
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function show() { root.open() }
    function hide() { root.close() }
  }

  function refresh() {
    // A read racing our own write can report the old level and bounce the
    // slider; the next tick picks up the settled value instead.
    if (setBrightnessProc.running || brightnessDebounce.running) return
    if (!stateProc.running) stateProc.running = true
  }

  function setBrightness(value) {
    var percent = clampBrightness(value)
    root.brightnessPercent = percent
    root.pendingBrightnessPercent = percent

    if (setBrightnessProc.running) {
      root.brightnessSetQueued = true
      return
    }

    root.brightnessSetQueued = false
    setBrightnessProc.command = binCommand(["omarchy-brightness-touchbar", "--no-osd", percent + "%"])
    setBrightnessProc.running = true
  }

  function previewBrightness(value) {
    root.brightnessPercent = clampBrightness(value)
    brightnessDebounce.restart()
  }

  function showBrightnessOsd(percent) {
    if (!bar || !bar.shell) return
    // omarchy-osd shows an unrecognized icon name as a literal glyph.
    bar.shell.summon("omarchy.osd", JSON.stringify({
      icon: root.touchbarIcon,
      value: percent
    }))
  }

  function setSyncMode(mode) {
    if (syncModeIndex(mode) < 0 || modeProc.running) return
    root.syncMode = mode
    modeProc.command = binCommand(["omarchy-brightness-touchbar-sync-mode", mode])
    modeProc.running = true
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (opened) {
      refresh()
      focusSection = "brightness"
      selectedIndex = -1
      cursorActive = false
    }
  }

  // The sync service moves the Touch Bar on its own, so poll a little faster
  // than the Display panel while open to keep the slider honest.
  Timer {
    interval: 2000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: stateProc
    command: root.binCommand(["bash", "-c",
      "omarchy-brightness-touchbar || echo unavailable; omarchy-brightness-touchbar-sync-mode; "
      + "[[ -f $HOME/.config/systemd/user/omarchy-brightness-touchbar-sync.service ]] && echo setup || echo missing; "
      + "omarchy-brightness-touchbar-setup tiny-dfr --check"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var brightness = String(lines[0] || "").trim()
        root.brightnessAvailable = brightness !== "unavailable" && brightness !== ""
        root.brightnessPercent = root.brightnessAvailable ? Math.max(0, Math.min(100, parseInt(brightness, 10))) : 0
        var mode = String(lines[1] || "").trim()
        root.syncMode = root.syncModeIndex(mode) >= 0 ? mode : "off"
        root.setupDone = String(lines[2] || "").trim() !== "missing"
        root.tinyDfrAdaptive = String(lines[3] || "").trim() === "adaptive"
        if (!root.tinyDfrAdaptive && root.focusSection === "tinydfr") {
          root.focusSection = "sync"
          root.selectedIndex = root.sectionFirstIndex("sync")
        }
      }
    }
  }

  Timer {
    id: brightnessDebounce
    interval: 180
    repeat: false
    onTriggered: root.setBrightness(root.brightnessPercent)
  }

  Process {
    id: setBrightnessProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: {
      if (running) return
      if (root.brightnessSetQueued) root.setBrightness(root.pendingBrightnessPercent)
    }
  }

  // The setup runs in a terminal so its output and any failure stay visible.
  Process {
    id: setupProc
    stdout: StdioCollector { waitForEnd: true }
  }

  Process {
    id: modeProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.touchbarIcon
    onPressed: function(b) { root.toggle() }
    onWheelMoved: function(delta) {
      if (!root.brightnessAvailable) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps === 0) return
      root.setBrightness(root.brightnessPercent + wheel.steps * 5)
      root.showBrightnessOsd(root.brightnessPercent)
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) {
          if (root.focusSection === "brightness") root.adjustBrightness(dx * 5)
          else if (root.focusSection === "sync") root.moveCursorH(dx)
        }
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: panelColumn
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Style.space(14)

        // ---------- Hero: Touch Bar icon · title/status ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.touchbarIcon
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              text: "Touch Bar"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.brightnessAvailable ? root.syncLabel(root.syncMode).toUpperCase() : "NO TOUCH BAR FOUND"
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        // ---------- Brightness ----------
        PanelSeparator {
          visible: root.brightnessAvailable
          foreground: root.bar.foreground
        }

        Column {
          visible: root.brightnessAvailable
          width: parent.width
          spacing: Style.space(6)

          Item {
            width: parent.width
            implicitHeight: Math.max(brightnessHeader.implicitHeight, brightnessPercent.implicitHeight)

            PanelSectionHeader {
              id: brightnessHeader
              text: "BRIGHTNESS"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: brightnessPercent
              textFormat: Text.PlainText
              text: {
                var p = Math.round(brightnessSlider.dragging ? brightnessSlider.liveValue : root.brightnessPercent)
                return p > 0 ? p + "%" : "OFF"
              }
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          CursorSurface {
            id: brightnessRow
            width: parent.width
            height: brightnessSlider.implicitHeight + Style.spacing.controlGap
            hasCursor: root.cursorActive && root.focusSection === "brightness" && root.selectedIndex === -1
            foreground: root.bar.foreground
            outline: true

            PanelSlider {
              id: brightnessSlider
              bar: root.bar
              anchors.fill: parent
              anchors.leftMargin: Style.space(6)
              anchors.rightMargin: Style.space(6)
              minimum: 1
              maximum: 100
              step: 1
              value: root.brightnessPercent
              integer: true
              onMoved: function(v) { root.previewBrightness(v) }
              onReleased: function(v) {
                brightnessDebounce.stop()
                root.setBrightness(v)
              }
            }

            HoverHandler {
              onHoveredChanged: if (hovered) {
                root.cursorActive = true
                root.focusSection = "brightness"
                root.selectedIndex = -1
              }
            }
          }
        }

        // ---------- Sync ----------
        PanelSeparator {
          visible: root.brightnessAvailable
          foreground: root.bar.foreground
        }

        Column {
          visible: root.brightnessAvailable
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "SYNC"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          // Before setup there is no sync service to switch, so offer setup instead.
          Button {
            visible: !root.setupDone
            width: parent.width
            text: "Set up sync service and keys"
            fontSize: Style.font.caption
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            onClicked: root.runSetup()
          }

          Grid {
            id: syncRow
            visible: root.setupDone
            width: parent.width
            columns: root.syncModes.length
            spacing: Style.spacing.xs

            readonly property real cellWidth: (width - spacing * (columns - 1)) / columns

            Repeater {
              model: root.syncModes

              SyncPill {
                required property var modelData
                required property int index

                mode: modelData.value
                label: modelData.label
                pillIndex: index
                width: syncRow.cellWidth
              }
            }
          }

          // Moving the slider or pressing the keys always wins over sync until the
          // source changes (see omarchy-brightness-touchbar-sync).
          Text {
            visible: root.setupDone && root.syncMode !== "off"
            textFormat: Text.PlainText
            text: "Adjusting by hand pauses sync until the "
                  + (root.syncMode === "ambient" ? "room light changes." : "keyboard backlight changes.")
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            width: parent.width
          }
        }

        // ---------- tiny-dfr ----------
        PanelSeparator {
          visible: root.brightnessAvailable && root.tinyDfrAdaptive
          foreground: root.bar.foreground
        }

        Column {
          visible: root.brightnessAvailable && root.tinyDfrAdaptive
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "TINY-DFR"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Text {
            textFormat: Text.PlainText
            text: "tiny-dfr resets the Touch Bar whenever the display brightness changes."
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            width: parent.width
          }

          Button {
            width: parent.width
            text: "Turn off tiny-dfr adaptive brightness"
            fontSize: Style.font.caption
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            verticalPadding: Style.spacing.controlPaddingY
            bordered: true
            hasCursor: root.cursorActive && root.focusSection === "tinydfr"
            onClicked: root.runTinyDfrFix()
            onHovered: function(isHovered) {
              if (!isHovered) return
              root.cursorActive = true
              root.focusSection = "tinydfr"
              root.selectedIndex = 0
            }
          }
        }

        Item {
          width: parent.width
          height: Style.space(4)
        }
      }
    }
  }

  component SyncPill: Button {
    id: pill
    required property string mode
    required property string label
    required property int pillIndex

    text: label
    fontSize: Style.font.caption
    foreground: root.bar.foreground
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.sm
    verticalPadding: Style.spacing.controlPaddingY
    bordered: true

    active: root.syncMode === mode
    hasCursor: root.cursorActive && root.focusSection === "sync" && root.selectedIndex === pillIndex

    onClicked: root.setSyncMode(mode)
    onHovered: function(isHovered) {
      if (!isHovered) return
      root.cursorActive = true
      root.focusSection = "sync"
      root.selectedIndex = pill.pillIndex
    }
  }
}
