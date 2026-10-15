// node tests/model.test.js
const assert = require("assert")
const M = require("../Model.js")

assert.strictEqual(M.formatSeconds(0), "Off")
assert.strictEqual(M.formatSeconds(45), "45 s")
assert.strictEqual(M.formatSeconds(300), "5 min")
assert.strictEqual(M.formatSeconds(5400), "1 h 30 min")
assert.strictEqual(M.formatMs(5000), "5 s")
// Hours round to whole minutes before splitting, never "1 h 60 min".
assert.strictEqual(M.formatSeconds(7170), "2 h")
assert.strictEqual(M.formatSeconds(7199), "2 h")
assert.strictEqual(M.formatSeconds(3599), "59 min 59 s")

assert.strictEqual(M.LOCK_OPTIONS[M.nearestIndex(M.LOCK_OPTIONS, 300)], 300)
assert.strictEqual(M.LOCK_OPTIONS[M.nearestIndex(M.LOCK_OPTIONS, 290)], 300)
// The shell's default screensaver sits on a notch.
assert.strictEqual(M.SCREENSAVER_OPTIONS[M.nearestIndex(M.SCREENSAVER_OPTIONS, 150)], 150)

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
// Past the last notch the minimum itself is saved, not the last notch.
assert.strictEqual(M.snapSleep(10800, 10800, 5000), 10860)
assert.strictEqual(M.snapSleep(600, 10800, 3600000), 14400)
// With the display kept on there is no display-off to wait for.
assert.strictEqual(M.snapSleep(300, 300, 3600000, true), 300)

// No slider combination saves a sleep before lock + display off, or a
// screensaver at or after the lock.
for (const lock of M.LOCK_OPTIONS) for (const blankMs of M.BLANK_OPTIONS)
  for (const sleep of M.SLEEP_OPTIONS) for (const screensaver of M.SCREENSAVER_OPTIONS) {
    const t = M.normalize({ screensaver, lock, blankMs, sleep })
    assert.strictEqual(t.lock, lock)
    assert.strictEqual(t.blankMs, blankMs)
    assert.strictEqual(t.sleep === 0, sleep === 0)
    if (t.sleep > 0) assert.ok(t.sleep >= M.minSleepFor(lock, blankMs), JSON.stringify(t))
    if (t.screensaver > 0 && lock > 0) assert.ok(t.screensaver < lock, JSON.stringify(t))
  }

// Raising the lock and then lowering sleep, as two quick picks, still ends in
// order when the second pick is measured against the first.
const afterLock = M.normalize({ screensaver: 0, lock: 3600, blankMs: 5000, sleep: 1800 })
assert.strictEqual(afterLock.sleep, 5400)
const afterSleep = M.normalize(Object.assign({}, afterLock, { sleep: 600 }))
assert.strictEqual(afterSleep.sleep, 5400)

// The service applies the same floor to hand-edited values.
assert.strictEqual(M.effectiveSleep({ sleep: 0, lock: 300, blankMs: 5000 }), 0)
assert.strictEqual(M.effectiveSleep({ sleep: 60, lock: 300, blankMs: 5000 }), 305)
assert.strictEqual(M.effectiveSleep({ sleep: 60, lock: 300, blankMs: 5000, keepDisplayOn: true }), 300)
assert.strictEqual(M.effectiveSleep({ sleep: 3600, lock: 300, blankMs: 5000 }), 3600)

// The screensaver always comes before the lock.
assert.strictEqual(M.snapScreensaver(0, 60), 0)
assert.strictEqual(M.snapScreensaver(120, 0), 120)
assert.strictEqual(M.snapScreensaver(120, 300), 120)
assert.strictEqual(M.snapScreensaver(300, 300), 180)
assert.strictEqual(M.snapScreensaver(600, 60), 30)
assert.strictEqual(M.snapScreensaver(3600, 3600), 2700)
assert.strictEqual(M.snapScreensaver(60, 30), 0)

const cfg = M.parseConfig(JSON.stringify({
  version: 1,
  idle: { lock: 600 },
  bar: { layout: { right: [{ id: "chyld.power", sleep: 2700 }] } },
  plugins: [{ id: "io.github.sirjul1337.lock-explorer", blankMs: 30000 }]
}))
assert.deepStrictEqual(cfg, { valid: true, lock: 600, screensaver: 150, sleep: 2700, blankMs: 30000, keepDisplayOn: false, dryRun: false })

const defaults = M.parseConfig('{"version":1}')
assert.strictEqual(defaults.valid, true)
assert.strictEqual(defaults.lock, 300)
// Adding the widget without a sleep key never arms a suspend.
assert.strictEqual(defaults.sleep, 0)
assert.strictEqual(defaults.blankMs, 5000)
assert.strictEqual(defaults.screensaver, 150)
assert.strictEqual(M.parseConfig(JSON.stringify({ version: 1, idle: { lock: 90.7, screensaver: 0 } })).lock, 90)
assert.strictEqual(M.parseConfig(JSON.stringify({ version: 1, idle: { screensaver: 0 } })).screensaver, 0)
assert.strictEqual(M.parseConfig(JSON.stringify({ version: 1, idle: { lock: "<b>x</b>" } })).lock, 300)
assert.strictEqual(M.parseConfig(JSON.stringify({ version: 1, plugins: [
  { id: "io.github.sirjul1337.lock-explorer", keepDisplayOn: true }] })).keepDisplayOn, true)

// Only what the shell itself accepts is valid: an object with version 1.
for (const bad of ["not json", "[]", "true", '"x"', "null", "{}", '{"version":2}'])
  assert.strictEqual(M.parseConfig(bad).valid, false, bad)

console.log("model tests passed")
