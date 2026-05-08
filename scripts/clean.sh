#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
build_dir="$repo_root/build"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/amprev"

all_flag=false

for arg in "$@"; do
    case "$arg" in
        --all)
            all_flag=true
            ;;
        *)
            printf 'Unknown argument: %s\n' "$arg" >&2
            exit 1
            ;;
    esac
done

rm -rf "$build_dir"

if [[ "$all_flag" == true ]]; then
    rm -rf "$cache_dir"
fi
