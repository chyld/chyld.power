# chyld.power

Power actions and the idle sequence for Omarchy, in one bar panel.

**Buttons:** Lock, Sleep, Reboot, Shut down. Reboot and Shut down ask first.

**When idle:** screensaver → lock → display off → sleep.

| Step | Counts from | Saved in |
|---|---|---|
| Screensaver | last input | `idle.screensaver` in `shell.json`, run by the shell's idle service |
| Lock | last input | `idle.lock` in `shell.json`, run by the shell's idle service |
| Display off | the lock | lock-explorer's `blankMs`, set through `omarchy-shell lock setBlankDelay` |
| Sleep | last input | `sleep` on this plugin's bar entry, run by `Service.qml` |

The screensaver is always kept before the lock, and sleep after lock + display
off. It waits while an app blocks
idle (video, calls), while Stay Awake is on, and when suspend is turned off
with `omarchy toggle suspend`. Omarchy locks the session before every suspend.

The shell's idle monitor stops firing once its timeout changes, so after any
change to `idle.lock` or `idle.screensaver` (from the panel or by hand) this
plugin switches it off and on again (`bin/rearm-idle`). Without that, the idle
lock would never fire again until the shell restarts.

## Files

- `BarWidget.qml`, `Panel.qml`: the bar icon and its panel
- `Service.qml`: the idle-sleep timer
- `Model.js`: timer options and `shell.json` parsing
- `bin/apply`: saves timer changes, one at a time
- `bin/idle-sleep`: the suspend step and its checks
- `bin/rearm-idle`: rebuilds the shell's idle monitor after a timer change

## Debugging

    omarchy-shell chyld.power status
    journalctl --user -f | grep chyld.power

Set `"dryRun": true` on the `chyld.power` bar entry to log instead of
suspending; the last result is in `$XDG_RUNTIME_DIR/chyld-power/last-idle-sleep`.

Tests: `node tests/model.test.js`
