#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/vars"

function npmInstall {
    local install_status=0

    echo -e " ${BLUE}>>>>> $1 <<<<<<${NC}"
    cd ../$1

    sudo rm package-lock.json
    sudo rm -R node_modules

    docker run -u 0 --rm \
        -v $HOME/Mahaigiana/l13/dc-data/npmCache:/npmCache \
        -v $HOME/Mahaigiana/l13/Packages:/packages \
        -v $(pwd):/app -w /app node:$NODE_VERSION \
        bash -c "npm config set cache /npmCache --global && rm -f package-lock.json  && rm -Rf node_modules && npm install"

    install_status=$?

    sudo chown -R $USER:$GROUP .

    cd ../testing13
    bash npmRunProd.sh $1
    
    echo " "

    return $install_status
}

docker pull node:$NODE_VERSION

if [ "$1" != "" ] && [ -d "$PACKAGES_DIR/$1" ]; then
    npmInstall $1
    exit $?
elif [ "$1" != "" ] && [ ! -d "$PACKAGES_DIR/$1" ]; then
    resolved=$(find_by_short "$1")
    if [ -n "$resolved" ] && [ -d "$PACKAGES_DIR/$resolved" ]; then
        npmInstall "$resolved"
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
            npmInstall $package_name || GLOBAL_STATUS=1
        fi
    done
    exit $GLOBAL_STATUS
fi
