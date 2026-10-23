#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/vars"

# Usage: PHPUNIT_ARGS="--no-progress --filter=Name" ./phpunit.sh PRO
# Usage: BASICS13_MARIADB_DATABASE=laravel_phpunit BASICS13_MARIADB_PORT=13306 ./phpunit.sh BAS coverage mariadb
integration_mode="${3:-}"

if [ -n "$integration_mode" ] && [ "$integration_mode" != "mariadb" ]; then
    fail "Invalid integration mode: $integration_mode. Use mariadb."
fi

if [ "$integration_mode" = "mariadb" ]; then
    if [ -z "${1:-}" ] || [ -z "${BASICS13_MARIADB_DATABASE:-}" ]; then
        fail "The mariadb mode requires a package and BASICS13_MARIADB_DATABASE set to a test database."
    fi
fi

run_phpunit(){
    if [ "$integration_mode" != "mariadb" ]; then
        docker_php "$1"
        return $?
    fi

    # The host network reaches MariaDB through its published port, without depending on a Compose network.
    # Only the mariadb group: the rest of the suite already runs on SQLite.
    docker run --rm --entrypoint "" --network host -u "$USER:$GROUP" \
        -e XDEBUG_MODE=off -e HOME=/tmp \
        -e "BASICS13_MARIADB_DATABASE=$BASICS13_MARIADB_DATABASE" \
        -e DB_CONNECTION=mysql \
        -e "DB_DATABASE=$BASICS13_MARIADB_DATABASE" \
        -e "DB_HOST=${BASICS13_MARIADB_HOST:-127.0.0.1}" \
        -e "DB_PORT=${BASICS13_MARIADB_PORT:-3306}" \
        -e "DB_USERNAME=${BASICS13_MARIADB_USERNAME:-laravel}" \
        -e "DB_PASSWORD=${BASICS13_MARIADB_PASSWORD:-laravel}" \
        -e DB_URL= \
        -v "$PACKAGES_DIR":/packages \
        -v "$(pwd)":/app-docker -w /app-docker "webdevops/php-apache-dev:$PHP_VERSION" \
        bash -c "$1 --group mariadb"
}

# Appends the totals of a passing coverage run to the package history,
# as basics13/tooling/run-phpunit-with-coverage.sh does for the app.
save_coverage_summary(){
    local summary_file="tests/test-coverage-summary.txt"
    local summary

    # The C locale keeps the byte ranges of the ANSI regex valid on the host
    summary="$(LC_ALL=C sed -E 's/\x1B\[[0-9;?]*[ -/]*[@-~]//g; s/\r$//' "$1" \
        | awk '
            /^(OK \(|Tests: |Time: )/ { print; next }
            /^ *Summary:/ { in_summary = 1; next }
            in_summary && /^ *(Classes|Methods|Lines):/ { print; next }
            { in_summary = 0 }
        ' \
        | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"

    if [[ "$summary" != *Time:* || "$summary" != *Lines:* ]]; then
        printf '%s\n' 'Coverage summary could not be extracted from test output.' >&2
        return 1
    fi

    {
        printf 'Executed at: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        printf '%s\n' "$summary"
    } >> "$summary_file"
}

phpunit(){
    [ -f vendor/bin/phpunit ] || { missing_binary vendor/bin/phpunit; return 1; }
    [ -f phpunit.xml ] || [ -f phpunit.xml.dist ] || { missing_config phpunit.xml; return 1; }

    local target="${1:-}"
    local coverage_mode="${2:-}"

    # Remove the previous coverage directory if it exists
    if [ -d tests/coverage ]; then
        rm -Rf tests/coverage
    fi

    # Coverage mode: "coverage" or "c" as the second argument
    if [ "$coverage_mode" = "coverage" ] || [ "$coverage_mode" = "c" ]; then
        # For the HTML report, enable XDEBUG_MODE=coverage and generate it
        # Also display coverage summary in terminal with --coverage-text
        local output_file
        output_file="$(mktemp)"
        run_phpunit "XDEBUG_MODE=coverage vendor/bin/phpunit --display-phpunit-notices --coverage-html=tests/coverage/html --coverage-text ${PHPUNIT_ARGS:-}" | tee "$output_file"
        local test_status=${PIPESTATUS[0]}
        if [ "$test_status" -eq 0 ]; then
            save_coverage_summary "$output_file"
            test_status=$?
        fi
        rm -f "$output_file"
        [ "$test_status" -eq 0 ] || return "$test_status"
        # Open the coverage report in the browser
        if [ -f tests/coverage/html/index.html ]; then
            xdg-open tests/coverage/html/index.html 2>/dev/null || firefox tests/coverage/html/index.html 2>/dev/null || echo "Report generated at: tests/coverage/html/index.html"
        fi
    else
        # Normal mode: run with XDEBUG_MODE=off
        run_phpunit "XDEBUG_MODE=off vendor/bin/phpunit --display-phpunit-notices ${PHPUNIT_ARGS:-}"
    fi
}

pull_image "webdevops/php-apache-dev:$PHP_VERSION" || exit 1
run_tool phpunit "${1:-}" "${2:-}" "$PACKAGES"
