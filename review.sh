#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/vars"

review(){
    [ -f vendor/bin/phpstan ] || { missing_binary vendor/bin/phpstan; return 1; }
    [ -f phpstan.neon ] || [ -f phpstan.neon.dist ] || { missing_config phpstan.neon; return 1; }

    docker_php "vendor/bin/phpstan analyse --memory-limit=1G"
}

pull_image "webdevops/php-apache-dev:$PHP_VERSION"
run_tool review "${1:-}" "$PACKAGES"
