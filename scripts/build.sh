#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
build_dir="$repo_root/build"
run_app=false

for arg in "$@"; do
    case "$arg" in
        --run)
            run_app=true
            ;;
        *)
            printf 'Unknown argument: %s\n' "$arg" >&2
            exit 1
            ;;
    esac
done

if [[ ! -d "$build_dir" || ! -f "$build_dir/build.ninja" ]]; then
    meson setup "$build_dir" "$repo_root"
else
    meson setup --reconfigure "$build_dir" "$repo_root"
fi

meson compile -C "$build_dir"

schema_dir="$build_dir/data"
# Compile the project schema only when the build has staged the expected XML.
if [[ -f "$schema_dir/bar.astware.amprev.gschema.xml" ]]; then
    glib-compile-schemas "$schema_dir"
fi

if [[ "$run_app" == true ]]; then
    if [[ -z "${WEBKIT_DISABLE_COMPOSITING_MODE:-}" ]]; then
        export WEBKIT_DISABLE_COMPOSITING_MODE=1
    fi
    if [[ -z "${GSK_RENDERER:-}" ]]; then
        export GSK_RENDERER=cairo
    fi
    if [[ -z "${AMPREV_RESOURCE_DIR:-}" ]]; then
        export AMPREV_RESOURCE_DIR="$repo_root/data/resources"
    fi
    if [[ -z "${AMPREV_ICON_DIR:-}" ]]; then
        export AMPREV_ICON_DIR="$build_dir/data/icons"
    fi
    if [[ -z "${AMPREV_SCHEMA_DIR:-}" ]]; then
        export AMPREV_SCHEMA_DIR="$build_dir/data"
    fi
    if [[ -z "${GSETTINGS_SCHEMA_DIR:-}" && -f "$schema_dir/gschemas.compiled" ]]; then
        export GSETTINGS_SCHEMA_DIR="$schema_dir"
    fi
    exec "$build_dir/src/amprev"
fi
