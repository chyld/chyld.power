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
off (`Model.normalize`, the one place the order is decided). The service
applies the same floor, so a hand-edited `sleep` that is too short is raised,
not obeyed. With lock-explorer's Keep display on set there is no display-off,
and sleep only has to follow the lock. Sleep is off until you pick a time.

Idle sleep waits while an app blocks idle (video, calls), while Stay Awake is
on, and when suspend is turned off with `omarchy toggle suspend`; it also
checks there has been no input since the idle report. Any check it cannot make
counts as "don't suspend". A skipped or failed sleep is tried again every
minute for as long as the machine stays idle. Omarchy locks the session before
every suspend. The Sleep button is a direct request and always suspends.

The shell's idle monitor stops firing once its timeout changes
([omarchy#8038](https://github.com/omacom/omarchy/issues/8038)), so after any
change to `idle.lock` or `idle.screensaver` (from the panel or by hand) this
plugin switches it off and on again (`bin/rearm-idle`). The only switch the
shell offers is Stay Awake (`omarchy-shell idle disable`/`enable`), which is
persisted and ends an idle cycle in progress, so the script checks each reply,
turns Stay Awake back off if it is interrupted, and logs a failure otherwise.
Without the pulse, the idle lock would never fire again until the shell
restarts.

Timer saves rewrite `shell.json`, which the shell and other plugins also write.
`bin/apply` takes a lock and only replaces the file if it still holds what it
read, starting again from the newer version otherwise.

## Commands sent to the system

What each action actually runs, from the command this plugin (or the shell)
starts down to the command that does the work.

| Action | Started by | Command started | What that runs |
|---|---|---|---|
| Lock | Lock button | `omarchy-system-lock` | `omarchy-shell lock lock` (the lock screen), `hyprctl switchxkblayout all 0`, `1password --lock` if 1Password is running, then kills the screensaver (`ttfx`, `org.omarchy.screensaver`) |
| Lock | idle, after `idle.lock` | the shell's idle service runs `omarchy-system-lock` | same as the button |
| Sleep | Sleep button | `systemctl suspend` | logind announces `PrepareForSleep`; `omarchy-system-sleep-monitor` (holding a delay inhibitor) runs `omarchy-system-sleep-lock`, which locks and waits for the lock to be secure before the machine sleeps |
| Sleep | idle, after `sleep` | `bin/idle-sleep` | reads `omarchy-shell idle status`, `~/.local/state/omarchy/toggles/suspend-off` and `omarchy-shell chyld.power status`; if all clear, `systemctl suspend` (locked first, as above) |
| Reboot | Reboot button, confirmed | `omarchy system reboot` | `systemd-run --user … omarchy-system reboot --execute`: an OSD message, `omarchy-hyprland-window-close-all --wait` (2 s limit), then `systemctl reboot --no-wall` |
| Shut down | Shut down button, confirmed | `omarchy system shutdown` | as reboot, under `systemd-inhibit --what=sleep:idle:handle-lid-switch`, ending in `systemctl poweroff --no-wall` |
| Screensaver | idle, after `idle.screensaver` | the shell's idle service runs `bash -lc '[[ $(omarchy-shell lock isLocked) == "true" ]] \|\| omarchy-launch-screensaver'` | opens a terminal of class `org.omarchy.screensaver` on each monitor through `hyprctl dispatch`; does nothing when the screensaver is turned off (`screensaver-off` toggle) |
| Display off | lock-explorer, `blankMs` after the lock | `omarchy-brightness-keyboard off; omarchy-brightness-display off` | `hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })'`; with Keep display on (or HDMI blank suppression) only the keyboard backlight goes off |

The plugin starts the button commands and `bin/idle-sleep` itself. The
screensaver, idle lock and display off are run by the shell and lock-explorer;
the plugin only sets their timers (`shell.json`, and
`omarchy-shell lock setBlankDelay` for display off).

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

`Service.qml` stays loaded across plugin reloads (`keepLoaded`); run
`omarchy restart shell` after editing it.

Tests: `node tests/model.test.js` and `bash tests/bin.test.sh` (the scripts,
against stand-ins for `omarchy-shell` and `systemctl`)
