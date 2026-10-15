import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Model.js" as Model

// Idle sleep. The shell already locks on idle (idle.lock) and lock-explorer
// blanks the display after the lock; this adds the last step, suspend.
//
// The sleep timeout lives on chyld.power's entry in shell.json, which this
// reads directly so it follows edits from the panel or by hand.
Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string shellJsonPath: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
  readonly property string idleSleepScript: localPath("bin/idle-sleep")
  readonly property string rearmIdleScript: localPath("bin/rearm-idle")

  property var config: Model.parseConfig("")
  // Off until shell.json has been read, so the default never arms a timer.
  // Never earlier than lock + display off, even when shell.json says so.
  readonly property int sleepSeconds: config.valid ? Model.effectiveSleep(config) : 0
  // The shell's idle timers as last seen; "" until shell.json is first read.
  readonly property string idleTimers: config.valid ? config.lock + " " + config.screensaver : ""
  property string seenIdleTimers: ""

  function localPath(relative) {
    var s = String(Qt.resolvedUrl(relative))
    return s.indexOf("file://") === 0 ? s.substring(7) : ""
  }

  FileView {
    id: shellJson
    path: root.shellJsonPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      var next = Model.parseConfig(text())
      if (next.valid) root.config = next
    }
    onFileChanged: reload()
  }

  // The monitor is built only once the real timeout is known, and rebuilt
  // when it changes: one switched on after the fact never reported idle.
  onSleepSecondsChanged: rearm()

  function rearm() {
    var raised = root.sleepSeconds > root.config.sleep ? " (raised from " + root.config.sleep + "s to follow lock + display off)" : ""
    console.log("chyld.power: idle sleep " + (root.sleepSeconds > 0 ? "after " + root.sleepSeconds + "s" + raised : "off"))
    retrySleep.stop()
    monitorLoader.active = false
    monitorLoader.active = root.sleepSeconds > 0
  }

  // The shell's IdleMonitor goes quiet once its timeout changes, so the idle
  // lock would never fire again until a shell restart. Rebuild it after every
  // change; the value at startup is already right.
  onIdleTimersChanged: {
    if (root.idleTimers === "") return
    var first = root.seenIdleTimers === ""
    root.seenIdleTimers = root.idleTimers
    if (!first) rearmShellIdle()
  }

  function rearmShellIdle() {
    if (root.rearmIdleScript === "") return
    if (rearmProcess.running) {
      rearmAgain.restart()
      return
    }
    rearmProcess.command = ["bash", root.rearmIdleScript, String(root.config.lock), String(root.config.screensaver)]
    rearmProcess.running = true
  }

  function sleepNow() {
    if (root.idleSleepScript === "" || sleepProcess.running) return
    console.log("chyld.power: idle for " + root.sleepSeconds + "s, sleeping")
    sleepProcess.command = root.config.dryRun
      ? ["bash", root.idleSleepScript, "--dry-run"]
      : ["bash", root.idleSleepScript]
    sleepProcess.running = true
  }

  LazyLoader {
    id: monitorLoader
    active: false

    // respectInhibitors keeps a playing video or call from sleeping the machine.
    IdleMonitor {
      timeout: Math.max(1, root.sleepSeconds)
      respectInhibitors: true
      onIsIdleChanged: {
        console.log("chyld.power: idle monitor " + (isIdle ? "idle" : "active"))
        if (isIdle) root.sleepNow()
        else retrySleep.stop()
      }
    }
  }

  // bin/idle-sleep exits 0 once it has suspended (or dry-run logged), 2 when
  // it skipped (Stay Awake, suspend off, input since idle, a check it could
  // not make) and anything else when suspend failed.
  Process {
    id: sleepProcess
    stdout: StdioCollector {
      onStreamFinished: if (text.trim() !== "") console.log(text.trim())
    }
    onExited: function(exitCode) {
      if (exitCode === 0) return
      if (exitCode !== 2) console.warn("chyld.power: idle sleep failed, exit " + exitCode)
      // Still idle, so nothing else will bring this back: look again later,
      // in case Stay Awake or suspend-off has been turned off meanwhile.
      if (monitorLoader.item && monitorLoader.item.isIdle) retrySleep.restart()
    }
  }

  Timer {
    id: retrySleep
    interval: 60000
    onTriggered: if (monitorLoader.item && monitorLoader.item.isIdle) root.sleepNow()
  }

  Process {
    id: rearmProcess
    stdout: StdioCollector {
      onStreamFinished: if (text.trim() !== "") console.log(text.trim())
    }
    stderr: StdioCollector {
      onStreamFinished: if (text.trim() !== "") console.warn(text.trim())
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("chyld.power: rebuilding the shell idle monitor failed, exit " + exitCode)
    }
  }

  // A change that lands while a rebuild is running gets its own rebuild after.
  Timer {
    id: rearmAgain
    interval: 200
    onTriggered: root.rearmShellIdle()
  }

  IpcHandler {
    target: "chyld.power"

    function status(): string {
      return JSON.stringify({
        sleepSeconds: root.sleepSeconds,
        dryRun: root.config.dryRun === true,
        monitorActive: monitorLoader.item !== null,
        monitorTimeout: monitorLoader.item ? monitorLoader.item.timeout : 0,
        idle: monitorLoader.item ? monitorLoader.item.isIdle : false,
        configuredSleep: root.config.sleep,
        sleeping: sleepProcess.running,
        retrying: retrySleep.running,
        idleTimers: root.seenIdleTimers
      })
    }
  }
}
