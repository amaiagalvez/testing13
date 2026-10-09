#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Files
PACKAGES="$SCRIPT_DIR/01.packages.txt"
DEMOS="$SCRIPT_DIR/02.demos.txt"

not_found(){
    echo -e "❌ ${RED}ADI!!${NC} Aukeratutako paketea ez da existitzen!!"
    exit 1;
}

# basics, BAS, 1

# Extracts first comma-separated field and trims whitespace (folder name)
parse_name(){
    local name="${1%%,*}"
    echo "${name}" | xargs
}

# Extracts second comma-separated field and trims whitespace (short name)
parse_short(){
    local after="${1#*,}"
    local short="${after%%,*}"
    echo "${short}" | xargs
}

# Extracts third comma-separated field and trims whitespace (pakcage_id)
parse_package_id(){
    local after="${1#*,}"
    local after_second="${after#*,}"
    local package_id="${after_second%%,*}"
    echo "${package_id}" | xargs
}

# Contenido de los ficheros de lista que existan; los que no, se ignoran,
# asi un fichero pendiente (02.demos.txt) no rompe la ejecucion.
package_list(){
    local file
    for file in "$@"; do
        [ -f "$file" ] && cat "$file"
    done
    return 0
}

# Finds the package name (first field) whose short name (second field) matches $1
# Usage: name=$(find_by_short "BAS")
find_by_short(){
    local target="$1"
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local short
        short="$(parse_short "$line")"
        if [ "${short,,}" = "${target,,}" ]; then
            parse_name "$line"
            return 0
        fi
    done < "$PACKAGES"
    return 1
}

# Resuelve el paquete pedido: vale una carpeta de packages/ o su nombre corto.
# Usage: package=$(resolve_package "BAS")
resolve_package(){
    local candidate="$1"
    local resolved

    if [ -d "$PACKAGES_DIR/$candidate" ]; then
        echo "$candidate"
        return 0
    fi

    resolved="$(find_by_short "$candidate")"
    if [ -n "$resolved" ] && [ -d "$PACKAGES_DIR/$resolved" ]; then
        echo "$resolved"
        return 0
    fi

    return 1
}

# Crea las carpetas de cache en el host como tu usuario, para que los
# contenedores no escriban nada como root.
ensure_dirs(){
    mkdir -p "$COMPOSER_CACHE"
    mkdir -p "$NPM_CACHE"
}

# Borra una ruta; avisa si quedan restos creados como root.
remove_path(){
    local target="$1"

    [ -e "$target" ] || return 0

    if ! rm -Rf "$target" 2>/dev/null; then
        echo -e "   ${RED}Ezin da $target ezabatu: root-ek sortutako fitxategiak ditu.${NC}"
        echo -e "   ${YELLOW}Konpondu jabetza: sudo chown -R \$USER:\$GROUP .${NC}"
        return 1
    fi
}

# Avisos de los requisitos que necesita cada paquete antes de ejecutar.
missing_binary(){
    echo -e "   ${YELLOW}Ez dago $1: composerInstall.sh exekutatu aurretik.${NC}"
}

missing_config(){
    echo -e "   ${YELLOW}Ez dago $1: paketeak konfigurazioa behar du.${NC}"
}

# Descarga la imagen una sola vez, antes de recorrer los paquetes.
pull_image(){
    docker pull "$1"
}

# Contenedor PHP montado sobre el paquete actual.
docker_php(){
    docker run --rm --entrypoint "" -u "$USER:$GROUP" \
        -e HOME=/tmp \
        -v "$(pwd)":/app-docker -w /app-docker "webdevops/php-apache-dev:$PHP_VERSION" \
        bash -c "$1"
}

# Contenedor PHP con la cache de composer compartida entre paquetes.
docker_composer(){
    docker run --rm --entrypoint "" -u "$USER:$GROUP" \
        -e HOME=/tmp \
        -e COMPOSER_HOME=/tmp/composer \
        -e COMPOSER_CACHE_DIR=/composerCache \
        -v "$COMPOSER_CACHE":/composerCache \
        -v "$PACKAGES_DIR":/packages \
        -v "$(pwd)":/app-docker -w /app-docker "webdevops/php-apache-dev:$PHP_VERSION" \
        bash -c "$1"
}

# Contenedor Node montado sobre el paquete actual.
docker_node(){
    docker run --rm --entrypoint "" -u "$USER:$GROUP" \
        -e HOME=/tmp \
        -e NPM_CONFIG_CACHE=/npmCache \
        -e NPM_CONFIG_UPDATE_NOTIFIER=false \
        -v "$NPM_CACHE":/npmCache \
        -v "$PACKAGES_DIR":/packages \
        -v "$(pwd)":/app-docker -w /app-docker "node:$NODE_VERSION" \
        bash -c "$1"
}

run_repo_command() {
    local repo_path="$1"
    local command_name="$2"

    if command -v "$command_name" >/dev/null 2>&1; then
        (cd "$repo_path" && "$command_name") < /dev/tty > /dev/tty 2>&1
        return
    fi

    (
        cd "$repo_path" && \
        bash --rcfile "$HOME/.bashrc" -ic '
            set +m
            shopt -s expand_aliases
            type "$1" >/dev/null 2>&1 || exit 127
            eval "$1"
        ' _ "$command_name"
    ) < /dev/tty > /dev/tty 2>&1
}

clear_public(){
    local items=(
        "public/css"
        "public/img"
        "public/js"
        "public/docs"
        "public/app"
        "public/basics13"
    )

    local item
    for item in "${items[@]}"; do
        rm -Rfv "$item"
    done
}

# Ejecuta <accion> dentro de <paquete> y vuelve siempre al directorio inicial.
# Usage: run_in_package phpunit basics13
run_in_package(){
    local action="$1"
    local package="$2"

    echo -e " ${BLUE}>>>>> $package <<<<<<${NC}"

    ( cd "$PACKAGES_DIR/$package" && "$action" "$package" )
    local status=$?

    echo " "

    return $status
}

# Punto de entrada comun de todos los scripts: ejecuta <accion> sobre el
# paquete pedido o, si no se pasa ninguno, sobre todos los de las listas.
# Usage: run_tool <accion> <paquete|vacio> [ficheros-de-lista...]
run_tool(){
    local action="$1"
    local target="$2"
    shift 2

    if [ -n "$target" ]; then
        local package
        package="$(resolve_package "$target")" || not_found

        run_in_package "$action" "$package"
        exit $?
    fi

    local status=0
    local line package_name
    while IFS= read -r line; do
        package_name="$(parse_name "$line")"
        [ -z "$package_name" ] && continue
        [ -d "$PACKAGES_DIR/$package_name" ] || continue

        run_in_package "$action" "$package_name" || status=1
    done < <(package_list "$@")

    exit $status
}
