#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

usage(){
    printf 'Usage: bash %s <package|short-name> [c] [dusk]\n' "${BASH_SOURCE[0]}"
    printf '  c     Run phpunit with coverage\n'
    printf '  dusk  Also run Dusk browser tests\n'
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi

if [ "$#" -lt 1 ] || [ "$#" -gt 3 ] || [ -z "$1" ]; then
    usage >&2
    exit 1
fi

package="$(resolve_package "$1")" || not_found

coverage_mode=""
run_dusk=false

# Parse optional arguments (c and dusk in any order)
for arg in "${@:2}"; do
    case "$arg" in
        c) coverage_mode="coverage" ;;
        dusk) run_dusk=true ;;
        *) fail "Unknown argument: $arg. Use 'c' for coverage, 'dusk' for browser tests." ;;
    esac
done

for script in dumpAutoload composerInstall reformat review phpunit; do
    printf '\n>>>>> %s: %s <<<<<<\n' "$package" "$script"

    args=("$package")
    if [ "$script" = "phpunit" ] && [ -n "$coverage_mode" ]; then
        args+=("$coverage_mode")
    fi

    bash "$SCRIPT_DIR/$script.sh" "${args[@]}"
    status=$?
    if [ "$status" -ne 0 ]; then
        fail "$script failed for $package (exit code $status)." "$status"
    fi
done

# Run Dusk tests if requested
if [ "$run_dusk" = true ]; then
    printf '\n>>>>> %s: Dusk <<<<<<\n' "$package"
    bash "$SCRIPT_DIR/dusktest.sh" "$package"
    status=$?
    if [ "$status" -ne 0 ]; then
        fail "Dusk tests failed for $package (exit code $status)." "$status"
    fi
fi

printf '\nProcess completed for %s.\n' "$package"
