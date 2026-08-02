#!/bin/zsh

set -euo pipefail

repo_dir=${0:a:h:h}
app_path=$($repo_dir/scripts/build-app.sh debug)

exec "$app_path/Contents/MacOS/TWMac"
