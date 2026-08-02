#!/bin/zsh

set -euo pipefail

repo_dir=${0:a:h:h}
configuration=${1:-debug}

if [[ "$configuration" != "debug" && "$configuration" != "release" ]]; then
    print -u2 "Usage: $0 [debug|release]"
    exit 2
fi

swift build --package-path "$repo_dir" --configuration "$configuration" --arch arm64 >&2

binary_path="$repo_dir/.build/arm64-apple-macosx/$configuration/TWMac"
app_path="$repo_dir/build/TW Mac.app"
contents_path="$app_path/Contents"

mkdir -p "$contents_path/MacOS" "$contents_path/Resources"
install -m 755 "$binary_path" "$contents_path/MacOS/TWMac"
install -m 644 "$repo_dir/Resources/Info.plist" "$contents_path/Info.plist"

signing_identity=${TW_MAC_SIGNING_IDENTITY:--}
if [[ "$signing_identity" == "-" ]]; then
    codesign \
        --force \
        --sign - \
        --identifier dev.ggp.tw-mac \
        --requirements '=designated => identifier "dev.ggp.tw-mac"' \
        "$app_path" >&2
else
    codesign --force --sign "$signing_identity" "$app_path" >&2
fi

print "$app_path"
