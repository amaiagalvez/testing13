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

MARIADB_IMAGE="mariadb:11.7"
MARIADB_CONTAINER="testing13-mariadb-$$"

# Throwaway MariaDB on a free host port; data lives in tmpfs and is removed with the container.
start_mariadb(){
    pull_image "$MARIADB_IMAGE" || return 1
    trap stop_mariadb EXIT

    docker run -d --rm --name "$MARIADB_CONTAINER" -p 127.0.0.1::3306 --tmpfs /var/lib/mysql \
        -e MARIADB_ROOT_PASSWORD=root -e MARIADB_DATABASE=laravel_phpunit \
        -e MARIADB_USER=laravel -e MARIADB_PASSWORD=laravel \
        "$MARIADB_IMAGE" --collation-server=utf8mb4_unicode_ci > /dev/null || return 1

    local attempt
    for attempt in $(seq 60); do
        if docker exec "$MARIADB_CONTAINER" healthcheck.sh --connect --innodb_initialized > /dev/null 2>&1; then
            MARIADB_PORT="$(docker port "$MARIADB_CONTAINER" 3306/tcp | head -n 1)"
            MARIADB_PORT="${MARIADB_PORT##*:}"
            return 0
        fi
        sleep 1
    done

    return 1
}

stop_mariadb(){
    docker rm -f "$MARIADB_CONTAINER" > /dev/null 2>&1 || true
}

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

# The tests in the mariadb group are skipped on SQLite; run them against a throwaway MariaDB
if grep -rqs "Group('mariadb')" "$PACKAGES_DIR/$package/tests"; then
    printf '\n>>>>> %s: phpunit (MariaDB) <<<<<<\n' "$package"
    start_mariadb || fail "Could not start MariaDB for $package."
    BASICS13_MARIADB_DATABASE=laravel_phpunit BASICS13_MARIADB_PORT="$MARIADB_PORT" \
        bash "$SCRIPT_DIR/phpunit.sh" "$package" "" mariadb
    status=$?
    stop_mariadb
    if [ "$status" -ne 0 ]; then
        fail "MariaDB phpunit failed for $package (exit code $status)." "$status"
    fi
fi

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
