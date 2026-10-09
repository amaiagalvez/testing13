#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/vars"

function composerInstall {
    local install_status=0

    echo -e " ${BLUE}>>>>> $1 <<<<<<${NC}"
    cd "$PACKAGES_DIR/$1"

    remove_path vendor || return 1
    remove_path composer.lock
    remove_path tests/coverage

    ensure_dirs

    docker run --rm --entrypoint "" -u $USER:$GROUP \
        -e HOME=/tmp \
        -e COMPOSER_HOME=/tmp/composer \
        -e COMPOSER_CACHE_DIR=/composerCache \
        -v $COMPOSER_CACHE:/composerCache \
        -v $PACKAGES_DIR:/packages \
        -v $(pwd):/app-docker -w /app-docker webdevops/php-apache-dev:$PHP_VERSION \
        bash -c "composer --no-progress --optimize-autoloader install && { composer show | grep izt || true; }"

    install_status=$?

    cd "$SCRIPT_DIR"
    echo " "

    return $install_status
}

docker pull webdevops/php-apache-dev:$PHP_VERSION

if [ "$1" != "" ] && [ -d "$PACKAGES_DIR/$1" ]; then
    composerInstall $1
    exit $?
elif [ "$1" != "" ] && [ ! -d "$PACKAGES_DIR/$1" ]; then
    resolved=$(find_by_short "$1")
    if [ -n "$resolved" ] && [ -d "$PACKAGES_DIR/$resolved" ]; then
        composerInstall "$resolved"
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
            composerInstall $package_name || GLOBAL_STATUS=1
        fi
    done
    exit $GLOBAL_STATUS
fi
