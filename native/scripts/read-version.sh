#!/bin/sh
set -eu

cd "$(dirname "$0")/.."

release_version="${1:-}"
if [ -z "$release_version" ]; then
    release_version=$(tr -d '[:space:]' < VERSION)
fi

case "$release_version" in
    *[!0-9.]* | '')
        echo "invalid BubbleSearch version: $release_version" >&2
        echo "expected three numeric components, for example 1.0.6" >&2
        exit 1
        ;;
esac

if ! printf '%s\n' "$release_version" | grep -Eq '^[0-9]+(\.[0-9]+){2}$'; then
    echo "invalid BubbleSearch version: $release_version" >&2
    echo "expected three numeric components, for example 1.0.6" >&2
    exit 1
fi

printf '%s\n' "$release_version"
