#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/vars"

function phpunit {
    local phpunit_status=0

    echo -e " ${BLUE}>>>>> $1 <<<<<<${NC}"
    cd "$PACKAGES_DIR/$1"

    if [ ! -f vendor/bin/phpunit ]; then
        echo -e "   ${YELLOW}Ez dago vendor/bin/phpunit: composerInstall.sh exekutatu aurretik.${NC}"
        cd "$SCRIPT_DIR"
        return 1
    fi

    if [ ! -f phpunit.xml ] && [ ! -f phpunit.xml.dist ]; then
        echo -e "   ${YELLOW}Ez dago phpunit.xml: paketeak konfigurazioa behar du.${NC}"
        cd "$SCRIPT_DIR"
        return 1
    fi

    docker run --rm --entrypoint "" -u $USER:$GROUP \
        -e HOME=/tmp \
        -e XDEBUG_MODE=coverage \
        -v $(pwd):/app-docker -w /app-docker webdevops/php-apache-dev:$PHP_VERSION \
        bash -c "mkdir -p tests/coverage && vendor/bin/phpunit --coverage-clover=tests/coverage/coverage.xml --coverage-text"

    phpunit_status=$?

    cd "$SCRIPT_DIR"
    echo " "

    return $phpunit_status
}

docker pull webdevops/php-apache-dev:$PHP_VERSION

if [ "$1" != "" ] && [ -d "$PACKAGES_DIR/$1" ]; then
    phpunit $1
    exit $?
elif [ "$1" != "" ] && [ ! -d "$PACKAGES_DIR/$1" ]; then
    resolved=$(find_by_short "$1")
    if [ -n "$resolved" ] && [ -d "$PACKAGES_DIR/$resolved" ]; then
        phpunit "$resolved"
        exit $?
    fi
    not_found
else
    GLOBAL_STATUS=0
    for item in $(cat $PACKAGES)
    do
        package_name="$(parse_name "$item")"
        [ -z "$package_name" ] && continue

        if [ "$package_name" != "" ] && [ -d "$PACKAGES_DIR/$package_name" ]; then
            phpunit $package_name || GLOBAL_STATUS=1
        fi
    done
    exit $GLOBAL_STATUS
fi
