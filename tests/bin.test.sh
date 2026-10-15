#!/bin/bash
# bash tests/bin.test.sh
#
# Runs bin/idle-sleep, bin/rearm-idle and bin/apply against stand-ins for
# omarchy-shell and systemctl in a throwaway HOME. Nothing here can suspend
# the machine or touch the real shell.json.

set -u
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

check() { # name expected actual
  if [[ $2 == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: expected [$2] got [$3]"; failures=$((failures + 1)); fi
}

mkdir -p "$work/bin" "$work/state"
# Fake omarchy-shell: replies come from files in $work/state, calls are logged.
cat >"$work/bin/omarchy-shell" <<'EOF'
#!/bin/bash
s=$FAKE_STATE
echo "$*" >>"$s/calls"
case "$1 $2" in
  "idle status")
    [[ -f $s/idle-fail ]] && exit 1
    [[ -f $s/idle-garbage ]] && { echo nonsense; exit 0; }
    printf '{"lock":%s,"screensaver":%s,"stayAwake":%s}\n' "$(cat $s/lock)" "$(cat $s/screensaver)" "$(cat $s/stay)" ;;
  "idle disable") [[ -f $s/disable-refuse ]] && { echo nope; exit 0; }; echo true >$s/stay; echo disabled ;;
  "idle enable") [[ -f $s/enable-refuse ]] && { echo nope; exit 0; }; echo false >$s/stay; echo enabled ;;
  "chyld.power status") [[ -f $s/own-fail ]] && exit 1; printf '{"idle":%s}\n' "$(cat $s/own-idle)" ;;
  "lock setBlankDelay") echo ok ;;
  *) exit 1 ;;
esac
EOF
printf '#!/bin/bash\necho "$*" >>"$FAKE_STATE/systemctl"\nexit "${FAKE_SYSTEMCTL_EXIT:-0}"\n' >"$work/bin/systemctl"
chmod +x "$work/bin/"*

export PATH="$work/bin:$PATH" HOME="$work/home" XDG_RUNTIME_DIR="$work/run" FAKE_STATE="$work/state"
mkdir -p "$HOME/.config/omarchy" "$XDG_RUNTIME_DIR"

reset() {
  rm -rf "$HOME/.local" "$work/state"
  mkdir -p "$work/state"
  echo 300 >"$work/state/lock"
  echo 150 >"$work/state/screensaver"
  echo false >"$work/state/stay"
  echo true >"$work/state/own-idle"
}

suspends() { [[ -f $work/state/systemctl ]] && wc -l <"$work/state/systemctl" || echo 0; }

# ---------------------------------------------------------- idle-sleep

sleep_case() { # name expected-exit expected-suspends
  bash "$here/bin/idle-sleep" >/dev/null
  check "idle-sleep $1: exit" "$2" "$?"
  check "idle-sleep $1: suspends" "$3" "$(suspends)"
}

reset; sleep_case "all clear" 0 1
reset; FAKE_SYSTEMCTL_EXIT=1 sleep_case "suspend fails" 1 1
reset; echo true >"$work/state/stay"; sleep_case "stay awake" 2 0
reset; mkdir -p "$HOME/.local/state/omarchy/toggles"; touch "$HOME/.local/state/omarchy/toggles/suspend-off"
sleep_case "suspend off" 2 0
reset; touch "$work/state/idle-fail"; sleep_case "idle status fails" 2 0
reset; touch "$work/state/idle-garbage"; sleep_case "idle status garbage" 2 0
reset; touch "$work/state/own-fail"; sleep_case "own status fails" 2 0
reset; echo false >"$work/state/own-idle"; sleep_case "input since idle" 2 0
reset; bash "$here/bin/idle-sleep" --dry-run >/dev/null
check "idle-sleep dry run: exit" 0 "$?"
check "idle-sleep dry run: suspends" 0 "$(suspends)"
check "idle-sleep dry run: log" "dry run: would suspend" "$(cut -d' ' -f2- "$XDG_RUNTIME_DIR/chyld-power/last-idle-sleep")"

# ---------------------------------------------------------- rearm-idle

reset; bash "$here/bin/rearm-idle" 300 150 >/dev/null 2>&1
check "rearm: exit" 0 "$?"
check "rearm: pulsed" "idle disable idle enable" "$(grep -E 'disable|enable' "$work/state/calls" | tr '\n' ' ' | sed 's/ $//')"
check "rearm: stay awake off after" false "$(cat "$work/state/stay")"

reset; echo true >"$work/state/stay"; bash "$here/bin/rearm-idle" 300 150 >/dev/null 2>&1
check "rearm stay awake on: exit" 0 "$?"
check "rearm stay awake on: untouched" "" "$(grep -E 'disable|enable' "$work/state/calls")"
check "rearm stay awake on: still on" true "$(cat "$work/state/stay")"

reset; touch "$work/state/enable-refuse"; bash "$here/bin/rearm-idle" 300 150 >/dev/null 2>&1
check "rearm enable refused: exit" 1 "$?"

reset; touch "$work/state/disable-refuse"; bash "$here/bin/rearm-idle" 300 150 >/dev/null 2>&1
check "rearm disable refused: exit" 1 "$?"
check "rearm disable refused: stay awake off" false "$(cat "$work/state/stay")"

reset; SECONDS=0; bash "$here/bin/rearm-idle" 600 150 >/dev/null 2>&1
check "rearm values never land: exit" 1 "$?"
check "rearm values never land: no pulse" "" "$(grep -E 'disable|enable' "$work/state/calls")"

# ---------------------------------------------------------- apply

json="$HOME/.config/omarchy/shell.json"
cat >"$json" <<'EOF'
{
  "version": 1,
  "idle": {
    "lock": 300
  },
  "plugins": [
    {
      "id": "other.plugin",
      "x": "é"
    }
  ]
}
EOF
chmod 640 "$json"
python3 "$here/bin/apply" --lock 600 --sleep 1200
check "apply: exit" 0 "$?"
check "apply: values" "600 1200 é" "$(jq -r '"\(.idle.lock) \(.plugins[] | select(.id == "chyld.power") | .sleep) \(.plugins[0].x)"' "$json")"
check "apply: mode kept" 640 "$(stat -c %a "$json")"
check "apply: no temp files left" "" "$(ls -A "$(dirname "$json")" | grep -v '^shell.json$')"

python3 "$here/bin/apply" --lock abc 2>/dev/null
check "apply rejects non-numbers" 1 "$?"
python3 "$here/bin/apply" --lock 999999 2>/dev/null
check "apply rejects out of range" 1 "$?"

# A writer that lands between this script's read and its replace wins: its
# change is kept, and the timer change is applied on top of it.
python3 - "$here/bin/apply" "$json" <<'EOF'
import importlib.machinery, importlib.util, json, sys
loader = importlib.machinery.SourceFileLoader("apply", sys.argv[1])
spec = importlib.util.spec_from_loader("apply", loader)
apply = importlib.util.module_from_spec(spec)
loader.exec_module(apply)
real = apply.replace_if_unchanged
raced = []
def racing(original, text):
    if not raced:
        raced.append(1)
        config = json.loads(original)
        config["bar"] = {"edited": "elsewhere"}
        with open(sys.argv[2], "w") as f:
            json.dump(config, f)
    return real(original, text)
apply.replace_if_unchanged = racing
apply.apply_timers({"screensaver": 120})
EOF
check "apply under a racing writer" "elsewhere 120 600" "$(jq -r '"\(.bar.edited) \(.idle.screensaver) \(.idle.lock)"' "$json")"

if ((failures)); then
  echo "$failures bin test(s) failed"
  exit 1
fi
echo "bin tests passed"
