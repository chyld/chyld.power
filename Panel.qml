import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "chyld.power"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  readonly property string shellJsonPath: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
  readonly property string applyScript: localPath("bin/apply")

  property var config: Model.parseConfig("")
  property string errorMessage: ""
  property string confirmAction: ""
  // Timer changes not yet seen in shell.json: sent to bin/apply, and waiting
  // behind it. Every pick is measured against these on top of the file, so a
  // quick second change never undoes the first one's ordering.
  property var sentArgs: null
  property var queuedArgs: null
  readonly property var timers: Object.assign({
    screensaver: root.config.screensaver,
    lock: root.config.lock,
    blankMs: root.config.blankMs,
    sleep: root.config.sleep,
    keepDisplayOn: root.config.keepDisplayOn
  }, root.sentArgs || {}, root.queuedArgs || {})

  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.font.family

  function localPath(relative) {
    var s = String(Qt.resolvedUrl(relative))
    return s.indexOf("file://") === 0 ? s.substring(7) : ""
  }

  function open() {
    root.confirmAction = ""
    root.errorMessage = ""
    shellJson.reload()
    root.controller.show()
  }

  function close() {
    root.confirmAction = ""
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  // ---------------------------------------------------------- actions

  function run(command) {
    root.close()
    Quickshell.execDetached(command)
  }

  function confirmed() {
    var action = root.confirmAction
    root.confirmAction = ""
    if (action === "reboot") run(["omarchy", "system", "reboot"])
    else if (action === "shutdown") run(["omarchy", "system", "shutdown"])
  }

  // ---------------------------------------------------------- timers

  // Changes go through one script, one call at a time, so the lock-explorer
  // save and this plugin's own write to shell.json never overlap.
  function apply(args) {
    var merged = Object.assign({}, root.queuedArgs || {}, args)
    if (applyProcess.running) {
      root.queuedArgs = merged
      return
    }
    root.queuedArgs = null
    if (Object.keys(merged).length === 0) return
    root.sentArgs = Object.assign({}, root.sentArgs || {}, merged)
    var flags = { screensaver: "--screensaver", lock: "--lock", blankMs: "--blank", sleep: "--sleep" }
    var command = ["python3", root.applyScript]
    for (var key in merged) command.push(flags[key], String(merged[key]))
    root.errorMessage = ""
    applyProcess.command = command
    applyProcess.running = true
  }

  // Set one timer, let Model.normalize keep the order, and save whatever moved.
  function pick(key, value) {
    var current = root.timers
    var proposed = Object.assign({}, current)
    proposed[key] = value
    var next = Model.normalize(proposed)
    var args = {}
    var keys = ["screensaver", "lock", "blankMs", "sleep"]
    for (var i = 0; i < keys.length; i++) {
      if (next[keys[i]] !== current[keys[i]]) args[keys[i]] = next[keys[i]]
    }
    if (Object.keys(args).length > 0) apply(args)
  }

  FileView {
    id: shellJson
    path: root.shellJsonPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      var next = Model.parseConfig(text())
      if (next.valid) root.config = next
      // What was sent has landed (or failed and is shown as an error).
      if (!applyProcess.running && !root.queuedArgs) root.sentArgs = null
    }
    onFileChanged: reload()
  }

  Process {
    id: applyProcess
    stderr: StdioCollector {
      id: applyErrors
    }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        root.errorMessage = applyErrors.text.trim().replace(/^chyld\.power: /, "") || "Could not save the change"
      shellJson.reload()
      if (root.queuedArgs) Qt.callLater(function() { root.apply({}) })
    }
  }

  // ---------------------------------------------------------- view

  component PlainText: Text {
    textFormat: Text.PlainText
    color: root.fg
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  component ActionButton: Button {
    property bool urgent: false
    width: (actionRow.width - actionRow.spacing * 3) / 4
    bordered: true
    foreground: urgent && hot ? Color.urgent : root.fg
    fontFamily: root.fontFamily
    fontSize: Style.font.bodySmall
  }

  component TimerRow: Column {
    id: row
    property string title: ""
    property string caption: ""
    property var options: []
    property real current: 0
    property var format: function(v) { return String(v) }
    property real preview: current
    signal picked(real value)

    width: parent ? parent.width : 0
    spacing: Style.space(2)

    Item {
      width: parent.width
      implicitHeight: titleText.implicitHeight

      PlainText {
        id: titleText
        text: row.title
        font.bold: true
      }

      PlainText {
        anchors.right: parent.right
        text: row.format(slider.dragging ? row.preview : row.current)
      }
    }

    PlainText {
      text: row.caption
      opacity: 0.55
      font.pixelSize: Style.font.caption
    }

    PanelSlider {
      id: slider
      width: parent.width
      bar: root.bar
      minimum: 0
      maximum: row.options.length - 1
      step: 1
      integer: true
      tickCount: row.options.length
      value: Model.nearestIndex(row.options, row.current)
      onMoved: function(v) { row.preview = row.options[Math.round(v)] }
      onReleased: function(v) {
        var picked = row.options[Math.round(v)]
        if (picked !== row.current) row.picked(picked)
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.confirmAction !== "") root.confirmAction = ""
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        PlainText {
          text: "Power"
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Row {
          id: actionRow
          visible: root.confirmAction === ""
          width: parent.width
          spacing: Style.space(6)

          ActionButton {
            iconText: "󰌾"
            text: "Lock"
            onClicked: root.run(["omarchy-system-lock"])
          }
          ActionButton {
            iconText: "󰒲"
            text: "Sleep"
            onClicked: root.run(["systemctl", "suspend"])
          }
          ActionButton {
            iconText: "󰜉"
            text: "Reboot"
            urgent: true
            onClicked: root.confirmAction = "reboot"
          }
          ActionButton {
            iconText: "󰐥"
            text: "Shut down"
            urgent: true
            onClicked: root.confirmAction = "shutdown"
          }
        }

        Item {
          visible: root.confirmAction !== ""
          width: parent.width
          implicitHeight: Math.max(confirmText.implicitHeight, confirmButtons.implicitHeight)

          PlainText {
            id: confirmText
            anchors.verticalCenter: parent.verticalCenter
            text: root.confirmAction === "reboot" ? "Reboot now?" : "Shut down now?"
            font.bold: true
          }

          Row {
            id: confirmButtons
            anchors.right: parent.right
            spacing: Style.space(6)

            Button {
              text: "Cancel"
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: root.confirmAction = ""
            }
            Button {
              text: root.confirmAction === "reboot" ? "Reboot" : "Shut down"
              bordered: true
              foreground: Color.urgent
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: root.confirmed()
            }
          }
        }

        PanelSeparator {
          width: parent.width
          foreground: root.fg
        }

        PanelSectionHeader {
          text: "WHEN IDLE"
          foreground: root.fg
          fontFamily: root.fontFamily
        }

        TimerRow {
          title: "1  Screensaver"
          caption: "After this long without input, always before the lock"
          options: Model.SCREENSAVER_OPTIONS
          current: root.timers.screensaver
          format: Model.formatSeconds
          onPicked: function(v) { root.pick("screensaver", v) }
        }

        TimerRow {
          title: "2  Lock"
          caption: "After this long without input"
          options: Model.LOCK_OPTIONS
          current: root.timers.lock
          format: Model.formatSeconds
          onPicked: function(v) { root.pick("lock", v) }
        }

        TimerRow {
          title: "3  Display off"
          caption: root.timers.keepDisplayOn
            ? "Kept on: lock-explorer's Keep display on is set"
            : "After the screen locks (set in lock-explorer)"
          options: Model.BLANK_OPTIONS
          current: root.timers.blankMs
          format: Model.formatMs
          onPicked: function(v) { root.pick("blankMs", v) }
        }

        TimerRow {
          title: "4  Sleep"
          caption: "After this long without input, always after display off"
          options: Model.SLEEP_OPTIONS
          current: root.timers.sleep
          format: Model.formatSeconds
          onPicked: function(v) { root.pick("sleep", v) }
        }

        PlainText {
          width: parent.width
          text: "Sleep waits while video or a call blocks idle, or Stay Awake is on."
          opacity: 0.55
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        PlainText {
          visible: root.errorMessage !== ""
          width: parent.width
          text: root.errorMessage
          color: Color.urgent
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
