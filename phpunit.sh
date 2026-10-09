#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(dirname "${BASH_SOURCE[0]}")/vars"

phpunit(){
    [ -f vendor/bin/phpunit ] || { missing_binary vendor/bin/phpunit; return 1; }
    [ -f phpunit.xml ] || [ -f phpunit.xml.dist ] || { missing_config phpunit.xml; return 1; }

    local target="${1:-}"
    local coverage_mode="${2:-}"

    # Limpiar directorio de cobertura anterior si existe
    if [ -d tests/coverage ]; then
        rm -Rf tests/coverage
    fi

    # Modo coverage: segunda posición "coverage" o "c"
    if [ "$coverage_mode" = "coverage" ] || [ "$coverage_mode" = "c" ]; then
        # Para coverage HTML, activamos XDEBUG_MODE=coverage y generamos reporte HTML
        docker_php "XDEBUG_MODE=coverage vendor/bin/phpunit --coverage-html=tests/coverage/html"
        # Abrir reporte de cobertura en el navegador
        if [ -f tests/coverage/html/index.html ]; then
            xdg-open tests/coverage/html/index.html 2>/dev/null || firefox tests/coverage/html/index.html 2>/dev/null || echo "Reporte generado en: tests/coverage/html/index.html"
        fi
    else
        # Modo normal: pasar XDEBUG_MODE=off
        docker_php "XDEBUG_MODE=off vendor/bin/phpunit"
    fi
}

pull_image "webdevops/php-apache-dev:$PHP_VERSION"
run_tool phpunit "${1:-}" "${2:-}" "$PACKAGES"
