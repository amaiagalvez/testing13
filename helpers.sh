#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$(cd "$SCRIPT_DIR/../packages" && pwd)"

# Colors
RED='\033[0;31m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Errors in red on stderr; the second argument is the exit code.
fail(){
    printf "❌ ${RED}Error: %s${NC}\n" "$1" >&2
    exit "${2:-1}"
}

# Git

# Fails when the repository has local changes or untracked files; git pull
# would not notice them, so the pull has to be blocked explicitly.
assert_clean_tree(){
    local repo_path="$1"
    local name="$2"
    local status=0

    local changes
    changes="$(git -C "$repo_path" status --porcelain --untracked-files=all)" || {
        status=$?
        fail "Could not check the working tree for $name (exit code $status). Stopping." "$status"
    }

    if [ -n "$changes" ]; then
        printf "${RED}%s${NC}\n" "$changes" >&2
        fail "$name has uncommitted changes or untracked files. Commit or stash them before continuing. Stopping."
    fi
}

# Fast-forwards the repository.
# Usage: pull_repo "$SCRIPT_DIR" testing13
pull_repo(){
    local repo_path="$1"
    local name="$2"
    local status=0

    git -C "$repo_path" pull --ff-only < /dev/null || {
        status=$?
        fail "Could not update $name (exit code $status). Check the Git error and any uncommitted changes. Stopping." "$status"
    }
}

# Checks the working tree and then fast-forwards the repository.
# Usage: update_repo "$SCRIPT_DIR/.." l13
update_repo(){
    local repo_path="$1"
    local name="$2"

    assert_clean_tree "$repo_path" "$name"
    pull_repo "$repo_path" "$name"
}

# Files
PACKAGES="$SCRIPT_DIR/01.packages.txt"
DEMOS="$SCRIPT_DIR/02.projects.txt"

not_found(){
    fail "The selected package does not exist."
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

# Content of the list files that exist
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

# Resolves the requested package: either a packages/ folder or its short name.
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

# Creates the cache folders on the host as your user, so the containers
# never write anything as root.
ensure_dirs(){
    mkdir -p "$COMPOSER_CACHE"
    mkdir -p "$NPM_CACHE"
}

# Deletes a path; warns when root-owned leftovers remain.
remove_path(){
    local target="$1"

    [ -e "$target" ] || return 0

    if ! rm -Rf "$target" 2>/dev/null; then
        echo -e "   ${RED}Cannot remove $target: it contains files created by root.${NC}"
        echo -e "   ${YELLOW}Fix ownership: sudo chown -R \$USER:\$GROUP .${NC}"
        return 1
    fi
}

# Warnings about what each package requires before running.
missing_binary(){
    echo -e "   ${YELLOW}$1 not found: run composerInstall.sh first.${NC}"
}

missing_config(){
    echo -e "   ${YELLOW}$1 not found: the package requires configuration.${NC}"
}

# Reuses the local image; only pulls it when missing.
pull_image(){
    if docker image inspect "$1" >/dev/null 2>&1; then
        printf 'Using local image: %s\n' "$1"
        return 0
    fi

    docker pull "$1"
}

# PHP container mounted on the current package.
docker_php(){
    docker run --rm --entrypoint "" -u "$USER:$GROUP" \
        -e XDEBUG_MODE=off -e HOME=/tmp \
        -v "$PACKAGES_DIR":/packages \
        -v "$(pwd)":/app-docker -w /app-docker "webdevops/php-apache-dev:$PHP_VERSION" \
        bash -c "$1"
}

# PHP container with the Composer cache shared across packages.
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

# Node container mounted on the current package.
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

# Runs <action> inside <package> and always returns to the starting directory.
# Usage: run_in_package phpunit basics13
run_in_package(){
    local action="$1"
    local package="$2"
    local coverage_mode="${3:-}"

    echo -e " ${BLUE}>>>>> $package <<<<<<${NC}"

    ( cd "$PACKAGES_DIR/$package" && "$action" "$package" "$coverage_mode" )
    local status=$?

    echo " "

    return $status
}

# Common entry point of every script: runs <action> on the requested
# package or, when none is given, on every package in the lists.
# Usage: run_tool <action> <package|empty> [list-files...]
run_tool(){
    local action="$1"
    local target="$2"
    shift 2

    if [ -n "$target" ]; then
        local package
        package="$(resolve_package "$target")" || not_found

        # Pass remaining args (coverage mode) to run_in_package
        run_in_package "$action" "$package" "$@"
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
