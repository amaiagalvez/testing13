#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/vars"

function composerInstall {
    local install_status=0

    echo -e " ${BLUE}>>>>> $1 <<<<<<${NC}"
    cd ../$1

    sudo rm -f composer.lock
    sudo rm -rf vendor
    sudo rm -rf tests/coverage

    docker run -u 0 --rm \
        -v $HOME/Mahaigiana/l13/dc-data/composerCache:/composerCache \
        -v $HOME/Mahaigiana/l13/Packages:/packages \
        -v $(pwd):/app -w /app webdevops/php-apache-dev:$PHP_VERSION \
        bash -c "composer config -g cache-dir /composerCache; rm -Rf vendor/iztkoop && rm -f composer.lock && composer --no-progress --optimize-autoloader install && { composer show | grep izt || true; }"

    install_status=$?

    sudo chown -R $USER:$GROUP .

    cd ../testing13
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
