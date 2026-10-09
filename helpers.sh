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
        sudo rm -Rfv "$item"
    done
}