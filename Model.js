// Pure helpers shared by the panel and the service. No QML, so tests can
// load this file under node.

var PLUGIN_ID = "chyld.power"
var LOCK_EXPLORER_ID = "io.github.sirjul1337.lock-explorer"

var DEFAULT_LOCK = 300
var DEFAULT_SCREENSAVER = 150
var DEFAULT_BLANK_MS = 5000
// Sleep stays off until it is picked: adding the widget never arms a suspend.
var DEFAULT_SLEEP = 0

// Seconds of idle before the screensaver, the lock and sleep. 0 is off. All
// three count from the last input and share one scale, so their sliders line
// up: the same knob position is the same time on each.
// 150 is the shell's default screensaver, so a reset lands on a notch.
var IDLE_OPTIONS = [0, 30, 60, 120, 150, 180, 300, 600, 900, 1200, 1800, 2700, 3600, 5400, 7200, 10800]
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
  // Round to whole minutes first, so 7199 s reads "2 h", not "1 h 60 min".
  var total = Math.round(s / 60)
  var h = Math.floor(total / 60)
  var mins = total % 60
  return mins ? h + " h " + mins + " min" : h + " h"
}

function formatMs(ms) {
  return formatSeconds(Math.round((Number(ms) || 0) / 1000))
}

// Sleep must come after the lock and the display-off that follows it. With
// lock-explorer keeping the display on there is no display-off to wait for.
function minSleepFor(lockSeconds, blankMs, keepDisplayOn) {
  if (!(lockSeconds > 0)) return 0
  return lockSeconds + (keepDisplayOn ? 0 : Math.ceil(blankMs / 1000))
}

// Too short a sleep moves up to the next notch, or past the last notch to the
// minimum itself (rounded up to a minute): never below the minimum.
function snapSleep(sleepSeconds, lockSeconds, blankMs, keepDisplayOn) {
  if (!(sleepSeconds > 0)) return 0
  var min = minSleepFor(lockSeconds, blankMs, keepDisplayOn)
  if (sleepSeconds >= min) return sleepSeconds
  for (var i = 0; i < SLEEP_OPTIONS.length; i++) {
    if (SLEEP_OPTIONS[i] >= min) return SLEEP_OPTIONS[i]
  }
  return Math.ceil(min / 60) * 60
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

// The one place the order is kept: given every timer as it would be saved,
// move the screensaver and sleep so the sequence holds. The lock and the
// display-off are never moved; they are what the others are measured from.
function normalize(timers) {
  var t = timers || {}
  return {
    screensaver: snapScreensaver(t.screensaver, t.lock),
    lock: t.lock,
    blankMs: t.blankMs,
    sleep: snapSleep(t.sleep, t.lock, t.blankMs, t.keepDisplayOn === true),
    keepDisplayOn: t.keepDisplayOn === true
  }
}

// The sleep the service acts on. A hand edit can skip the panel's rules, so
// the floor is applied here too.
function effectiveSleep(config) {
  if (!config || !(config.sleep > 0)) return 0
  return Math.max(config.sleep, minSleepFor(config.lock, config.blankMs, config.keepDisplayOn === true))
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
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

// Read the timers out of shell.json text. Bad or missing values fall back to
// the defaults the shell and lock-explorer themselves use. A file the shell
// itself would reject (not an object, or no version 1) is not valid here
// either, so it never drives a timer.
function parseConfig(text) {
  var config = null
  try { config = JSON.parse(String(text || "")) } catch (e) { config = null }
  if (!isPlainObject(config) || config.version !== 1) config = null
  var idle = config && isPlainObject(config.idle) ? config.idle : {}
  var own = findEntry(config, PLUGIN_ID) || {}
  var lockExplorer = findEntry(config, LOCK_EXPLORER_ID) || {}
  return {
    valid: !!config,
    lock: idleSeconds(idle.lock, DEFAULT_LOCK),
    screensaver: idleSeconds(idle.screensaver, DEFAULT_SCREENSAVER),
    sleep: own.sleep === undefined ? DEFAULT_SLEEP : clampInt(own.sleep, 0, 86400, DEFAULT_SLEEP),
    blankMs: lockExplorer.blankMs === undefined
      ? DEFAULT_BLANK_MS : clampInt(lockExplorer.blankMs, 1000, 3600000, DEFAULT_BLANK_MS),
    keepDisplayOn: lockExplorer.keepDisplayOn === true,
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
    normalize: normalize,
    effectiveSleep: effectiveSleep,
    parseConfig: parseConfig
  }
}
