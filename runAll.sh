#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

usage(){
    printf 'Usage: bash %s <package|short-name>\n' "${BASH_SOURCE[0]}"
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    usage >&2
    exit 1
fi

package="$(resolve_package "$1")" || not_found

for script in dumpAutoload composerInstall reformat review phpunit; do
    printf '\n>>>>> %s: %s <<<<<<\n' "$package" "$script"

    args=("$package")
    if [ "$script" = "phpunit" ]; then
        args+=(coverage)
    fi

    bash "$SCRIPT_DIR/$script.sh" "${args[@]}"
    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'Error: %s failed for %s (exit code %s).\n' "$script" "$package" "$status" >&2
        exit "$status"
    fi
done

printf '\nProcess completed for %s.\n' "$package"
