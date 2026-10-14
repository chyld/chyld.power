// node tests/model.test.js
const assert = require("assert")
const M = require("../Model.js")

assert.strictEqual(M.formatSeconds(0), "Off")
assert.strictEqual(M.formatSeconds(45), "45 s")
assert.strictEqual(M.formatSeconds(300), "5 min")
assert.strictEqual(M.formatSeconds(5400), "1 h 30 min")
assert.strictEqual(M.formatMs(5000), "5 s")

assert.strictEqual(M.nearestIndex(M.LOCK_OPTIONS, 300), 5)
assert.strictEqual(M.nearestIndex(M.LOCK_OPTIONS, 290), 5)

// Screensaver, lock and sleep share one scale, so equal times line up.
assert.strictEqual(M.SCREENSAVER_OPTIONS, M.LOCK_OPTIONS)
assert.strictEqual(M.SLEEP_OPTIONS, M.LOCK_OPTIONS)
assert.ok(M.nearestIndex(M.SCREENSAVER_OPTIONS, 180) < M.nearestIndex(M.LOCK_OPTIONS, 300))

// Sleep never lands before lock + display off.
assert.strictEqual(M.snapSleep(0, 300, 5000), 0)
assert.strictEqual(M.snapSleep(300, 300, 5000), 600)
assert.strictEqual(M.snapSleep(1800, 300, 5000), 1800)
assert.strictEqual(M.snapSleep(300, 0, 5000), 300)
assert.strictEqual(M.snapSleep(600, 3600, 3600000), 7200)

// The screensaver always comes before the lock.
assert.strictEqual(M.snapScreensaver(0, 60), 0)
assert.strictEqual(M.snapScreensaver(120, 0), 120)
assert.strictEqual(M.snapScreensaver(120, 300), 120)
assert.strictEqual(M.snapScreensaver(300, 300), 180)
assert.strictEqual(M.snapScreensaver(600, 60), 30)
assert.strictEqual(M.snapScreensaver(3600, 3600), 2700)
assert.strictEqual(M.snapScreensaver(60, 30), 0)

const cfg = M.parseConfig(JSON.stringify({
  idle: { lock: 600 },
  bar: { layout: { right: [{ id: "chyld.power", sleep: 2700 }] } },
  plugins: [{ id: "io.github.sirjul1337.lock-explorer", blankMs: 30000 }]
}))
assert.deepStrictEqual(cfg, { valid: true, lock: 600, screensaver: 150, sleep: 2700, blankMs: 30000, dryRun: false })

const defaults = M.parseConfig("{}")
assert.strictEqual(defaults.lock, 300)
assert.strictEqual(defaults.sleep, 1800)
assert.strictEqual(defaults.blankMs, 5000)
assert.strictEqual(defaults.screensaver, 150)
assert.strictEqual(M.parseConfig(JSON.stringify({ idle: { lock: 90.7, screensaver: 0 } })).lock, 90)
assert.strictEqual(M.parseConfig(JSON.stringify({ idle: { screensaver: 0 } })).screensaver, 0)
assert.strictEqual(M.parseConfig("not json").valid, false)
assert.strictEqual(M.parseConfig(JSON.stringify({ idle: { lock: "<b>x</b>" } })).lock, 300)

console.log("model tests passed")
