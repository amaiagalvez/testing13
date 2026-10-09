#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/vars"

function npmRunProd {
    local install_status=0

    echo -e " ${BLUE}>>>>> $1 <<<<<<${NC}"
    cd "$PACKAGES_DIR/$1"

    clear_public
    ensure_dirs

    docker run --rm --entrypoint "" -u $USER:$GROUP \
        -e HOME=/tmp \
        -e NPM_CONFIG_CACHE=/npmCache \
        -e NPM_CONFIG_UPDATE_NOTIFIER=false \
        -v $NPM_CACHE:/npmCache \
        -v $PACKAGES_DIR:/packages \
        -v $(pwd):/app-docker -w /app-docker node:$NODE_VERSION \
        bash -c "npm run prod"

    install_status=$?

    cd "$SCRIPT_DIR"
    echo " "

    return $install_status
}

docker pull node:$NODE_VERSION

if [ "$1" != "" ] && [ -d "$PACKAGES_DIR/$1" ]; then
    npmRunProd $1
    exit $?
elif [ "$1" != "" ] && [ ! -d "$PACKAGES_DIR/$1" ]; then
    resolved=$(find_by_short "$1")
    if [ -n "$resolved" ] && [ -d "$PACKAGES_DIR/$resolved" ]; then
        npmRunProd "$resolved"
        exit $?
    fi
    not_found
else
    GLOBAL_STATUS=0
    for item in $(cat $PACKAGES $DEMOS)
    do
        package_name="$(parse_name "$item")"
        [ -z "$package_name" ] && continue

        if [ "$package_name" != "" ] && [ -d "$PACKAGES_DIR/$package_name" ]; then
            npmRunProd $package_name || GLOBAL_STATUS=1
        fi
    done
    exit $GLOBAL_STATUS
fi
