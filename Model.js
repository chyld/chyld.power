// Pure helpers shared by the panel and the service. No QML, so tests can
// load this file under node.

var PLUGIN_ID = "chyld.power"
var LOCK_EXPLORER_ID = "io.github.sirjul1337.lock-explorer"

var DEFAULT_LOCK = 300
var DEFAULT_SCREENSAVER = 150
var DEFAULT_BLANK_MS = 5000
var DEFAULT_SLEEP = 1800

// Seconds of idle before the screensaver, the lock and sleep. 0 is off. All
// three count from the last input and share one scale, so their sliders line
// up: the same knob position is the same time on each.
var IDLE_OPTIONS = [0, 30, 60, 120, 180, 300, 600, 900, 1200, 1800, 2700, 3600, 5400, 7200, 10800]
var SCREENSAVER_OPTIONS = IDLE_OPTIONS
var LOCK_OPTIONS = IDLE_OPTIONS
var SLEEP_OPTIONS = IDLE_OPTIONS
// Milliseconds after the lock before lock-explorer blanks the display. It
// accepts 1s to 60min and has no off.
var BLANK_OPTIONS = [5000, 10000, 15000, 30000, 60000, 120000, 300000, 600000, 1800000, 3600000]

function nearestIndex(options, value) {
  var best = 0
  for (var i = 1; i < options.length; i++) {
    if (Math.abs(options[i] - value) < Math.abs(options[best] - value)) best = i
  }
  return best
}

function formatSeconds(seconds) {
  var s = Math.round(Number(seconds) || 0)
  if (s <= 0) return "Off"
  if (s < 60) return s + " s"
  if (s < 3600) {
    var m = Math.floor(s / 60)
    var rest = s % 60
    return rest ? m + " min " + rest + " s" : m + " min"
  }
  var h = Math.floor(s / 3600)
  var mins = Math.round((s % 3600) / 60)
  return mins ? h + " h " + mins + " min" : h + " h"
}

function formatMs(ms) {
  return formatSeconds(Math.round((Number(ms) || 0) / 1000))
}

// Sleep must come after the lock and the display-off that follows it.
function minSleepFor(lockSeconds, blankMs) {
  return lockSeconds > 0 ? lockSeconds + Math.ceil(blankMs / 1000) : 0
}

function snapSleep(sleepSeconds, lockSeconds, blankMs) {
  if (!(sleepSeconds > 0)) return 0
  var min = minSleepFor(lockSeconds, blankMs)
  if (sleepSeconds >= min) return sleepSeconds
  for (var i = 0; i < SLEEP_OPTIONS.length; i++) {
    if (SLEEP_OPTIONS[i] >= min) return SLEEP_OPTIONS[i]
  }
  return SLEEP_OPTIONS[SLEEP_OPTIONS.length - 1]
}

// The screensaver must come before the lock, or the lock skips it.
function snapScreensaver(screensaverSeconds, lockSeconds) {
  if (!(screensaverSeconds > 0)) return 0
  if (!(lockSeconds > 0) || screensaverSeconds < lockSeconds) return screensaverSeconds
  for (var i = SCREENSAVER_OPTIONS.length - 1; i >= 0; i--) {
    if (SCREENSAVER_OPTIONS[i] > 0 && SCREENSAVER_OPTIONS[i] < lockSeconds) return SCREENSAVER_OPTIONS[i]
  }
  return 0
}

function clampInt(value, min, max, fallback) {
  var n = Number(value)
  if (!isFinite(n)) return fallback
  return Math.max(min, Math.min(max, Math.round(n)))
}

// Same reading of idle.* as the shell's idle service (IdleModel.js), so the
// values here match what `omarchy-shell idle status` reports.
function idleSeconds(value, fallback) {
  var n = Number(value)
  if (!isFinite(n) || n < 0) return fallback
  return Math.floor(n)
}

function findEntry(config, id) {
  var layout = config && config.bar && config.bar.layout
  var sections = ["left", "center", "right", "tray"]
  for (var s = 0; layout && s < sections.length; s++) {
    var list = layout[sections[s]]
    if (!Array.isArray(list)) continue
    for (var i = 0; i < list.length; i++) {
      if (list[i] && list[i].id === id) return list[i]
    }
  }
  var plugins = config && Array.isArray(config.plugins) ? config.plugins : []
  for (var j = 0; j < plugins.length; j++) {
    if (plugins[j] && plugins[j].id === id) return plugins[j]
  }
  return null
}

// Read the three timers out of shell.json text. Bad or missing values fall
// back to the defaults the shell and lock-explorer themselves use.
function parseConfig(text) {
  var config = null
  try { config = JSON.parse(String(text || "")) } catch (e) { config = null }
  var idle = config && config.idle && typeof config.idle === "object" ? config.idle : {}
  var own = findEntry(config, PLUGIN_ID) || {}
  var lockExplorer = findEntry(config, LOCK_EXPLORER_ID) || {}
  return {
    valid: !!config,
    lock: idleSeconds(idle.lock, DEFAULT_LOCK),
    screensaver: idleSeconds(idle.screensaver, DEFAULT_SCREENSAVER),
    sleep: own.sleep === undefined ? DEFAULT_SLEEP : clampInt(own.sleep, 0, 86400, DEFAULT_SLEEP),
    blankMs: lockExplorer.blankMs === undefined
      ? DEFAULT_BLANK_MS : clampInt(lockExplorer.blankMs, 1000, 3600000, DEFAULT_BLANK_MS),
    dryRun: own.dryRun === true
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    LOCK_OPTIONS: LOCK_OPTIONS,
    SCREENSAVER_OPTIONS: SCREENSAVER_OPTIONS,
    BLANK_OPTIONS: BLANK_OPTIONS,
    SLEEP_OPTIONS: SLEEP_OPTIONS,
    nearestIndex: nearestIndex,
    formatSeconds: formatSeconds,
    formatMs: formatMs,
    minSleepFor: minSleepFor,
    snapSleep: snapSleep,
    snapScreensaver: snapScreensaver,
    parseConfig: parseConfig
  }
}
