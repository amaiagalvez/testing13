#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/vars"

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
    docker run --rm --entrypoint "" --network host -u "$USER:$GROUP" \
        -e XDEBUG_MODE=off -e HOME=/tmp \
        -e "BASICS13_MARIADB_DATABASE=$BASICS13_MARIADB_DATABASE" \
        -e "DB_HOST=${BASICS13_MARIADB_HOST:-127.0.0.1}" \
        -e "DB_PORT=${BASICS13_MARIADB_PORT:-3306}" \
        -e "DB_USERNAME=${BASICS13_MARIADB_USERNAME:-laravel}" \
        -e "DB_PASSWORD=${BASICS13_MARIADB_PASSWORD:-laravel}" \
        -e DB_URL= \
        -v "$(pwd)":/app-docker -w /app-docker "webdevops/php-apache-dev:$PHP_VERSION" \
        bash -c "$1"
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
        run_phpunit "XDEBUG_MODE=coverage vendor/bin/phpunit --display-phpunit-notices --coverage-html=tests/coverage/html --coverage-text" || return $?
        # Open the coverage report in the browser
        if [ -f tests/coverage/html/index.html ]; then
            xdg-open tests/coverage/html/index.html 2>/dev/null || firefox tests/coverage/html/index.html 2>/dev/null || echo "Report generated at: tests/coverage/html/index.html"
        fi
    else
        # Normal mode: run with XDEBUG_MODE=off
        run_phpunit "XDEBUG_MODE=off vendor/bin/phpunit --display-phpunit-notices"
    fi
}

pull_image "webdevops/php-apache-dev:$PHP_VERSION" || exit 1
run_tool phpunit "${1:-}" "${2:-}" "$PACKAGES"
