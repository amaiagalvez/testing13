#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/vars"

reformat(){
    [ -f vendor/bin/pint ] || { missing_binary vendor/bin/pint; return 1; }

    docker_php "vendor/bin/pint"
}

pull_image "webdevops/php-apache-dev:$PHP_VERSION" || exit 1
run_tool reformat "${1:-}" "$PACKAGES"
