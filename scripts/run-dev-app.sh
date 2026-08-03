#!/bin/zsh

set -euo pipefail

repo_dir=${0:a:h:h}
build_log=$(mktemp -t tw-mac-build)
trap 'rm -f "$build_log"' EXIT

if ! app_path=$("$repo_dir/scripts/build-app.sh" debug 2>"$build_log"); then
    cat "$build_log" >&2
    exit 1
fi

rm -f "$build_log"
trap - EXIT

exec "$app_path/Contents/MacOS/TWMac"
