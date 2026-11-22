#!/bin/bash
# Usage: scripts/run.sh [--build | --render | --install]
#   (none)     build Debug and (re)launch it from the build dir
#   --build    build Debug only
#   --render   build Debug, then write PNGs to build/render and exit
#   --install  build Release, copy to /Applications and launch from there
set -euo pipefail
cd "$(dirname "$0")/.."
root=$(pwd)

mode=${1:-}
case "$mode" in
  ""|--build|--render|--install) ;;
  *) echo "usage: scripts/run.sh [--build | --render | --install]" >&2; exit 2 ;;
esac

# The installed copy runs all day, so it gets the optimised build; Debug keeps fast rebuilds for dev runs.
config=Debug
if [ "$mode" = --install ]; then config=Release; fi

xcodegen generate --quiet
xcodebuild build \
  -scheme Vitals \
  -configuration "$config" \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData \
  -quiet

app="$root/build/DerivedData/Build/Products/$config/Vitals.app"
pidfile="$root/build/vitals.pid"

# Waits up to 5 s for a pid to exit.
wait_gone() {
  local i=0
  while kill -0 "$1" 2>/dev/null && [ $i -lt 20 ]; do sleep 0.25; i=$((i + 1)); done
  if kill -0 "$1" 2>/dev/null; then echo "pid $1 still running after 5 s" >&2; return 1; fi
}

# Kills only the pid this script launched last time, and only if it is still Vitals.
kill_previous() {
  [ -f "$pidfile" ] || return 0
  local old
  old=$(cat "$pidfile")
  if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
    case "$(ps -o comm= -p "$old")" in
      *Vitals) kill "$old"; wait_gone "$old" ;;
    esac
  fi
}

launch() {
  nohup "$1/Contents/MacOS/Vitals" >/dev/null 2>&1 &
  echo $! > "$pidfile"
  echo "Vitals running, pid $(cat "$pidfile") ($1)"
}

case "$mode" in
  --build)
    echo "built $app"
    ;;
  --render)
    out="$root/build/render"
    mkdir -p "$out"
    find "$out" -name '*.png' -delete
    "$app/Contents/MacOS/Vitals" --render "$out" > "$root/build/render.log" 2>&1 &
    pid=$!
    i=0
    while kill -0 "$pid" 2>/dev/null && [ $i -lt 120 ]; do sleep 0.5; i=$((i + 1)); done
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid"
      echo "render timed out" >&2
      exit 1
    fi
    set +e; wait "$pid"; status=$?; set -e
    cat "$root/build/render.log"
    if [ $status -ne 0 ]; then echo "render failed with status $status" >&2; exit $status; fi
    ;;
  --install)
    kill_previous
    for pid in $(pgrep -x Vitals || true); do
      if ps -o command= -p "$pid" | grep -q '^/Applications/Vitals.app/'; then kill "$pid"; wait_gone "$pid"; fi
    done
    # ditto merges into an existing bundle; stale files break the code signature seal.
    /bin/rm -rf /Applications/Vitals.app
    ditto "$app" /Applications/Vitals.app
    launch /Applications/Vitals.app
    ;;
  "")
    kill_previous
    launch "$app"
    ;;
esac
