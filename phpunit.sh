#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/vars"

phpunit(){
    [ -f vendor/bin/phpunit ] || { missing_binary vendor/bin/phpunit; return 1; }
    [ -f phpunit.xml ] || [ -f phpunit.xml.dist ] || { missing_config phpunit.xml; return 1; }

    docker_php "mkdir -p tests/coverage && vendor/bin/phpunit --coverage-clover=tests/coverage/coverage.xml --coverage-text"
}

pull_image "webdevops/php-apache-dev:$PHP_VERSION"
run_tool phpunit "${1:-}" "$PACKAGES"
