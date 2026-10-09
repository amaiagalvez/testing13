#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/vars"

composerInstall(){
    local package="$1"

    remove_path vendor || return 1
    remove_path composer.lock
    remove_path tests/coverage

    ensure_dirs

    docker_composer "composer --no-progress --optimize-autoloader install && { composer show | grep izt || true; }"
}

pull_image "webdevops/php-apache-dev:$PHP_VERSION"
run_tool composerInstall "${1:-}" "$PACKAGES"
