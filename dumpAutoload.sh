#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/vars"

dumpAutoload(){
    [ -f composer.json ] || { missing_config composer.json; return 1; }

    ensure_dirs || return 1

    docker_composer "composer dump-autoload --optimize --no-interaction && composer clear-cache --no-interaction && if [ -f artisan ]; then php artisan optimize:clear --no-interaction; fi"
}

pull_image "webdevops/php-apache-dev:$PHP_VERSION" || exit 1
run_tool dumpAutoload "${1:-}" "$PACKAGES"
