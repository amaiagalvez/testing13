#!/bin/bash

# Parse the full workflow before a pull can modify this running script.
{
set -euo pipefail

fail(){
    printf '\033[0;31mError: %s\033[0m\n' "$1" >&2
    exit "${2:-1}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# l13
printf '\n>>>>> Updating l13 <<<<<<\n'
git -C "$SCRIPT_DIR/.." pull --ff-only < /dev/null || {
    status=$?
    fail "Could not update l13 (exit code $status). Stopping." "$status"
}

# testing13
printf '\n>>>>> Updating testing13 <<<<<<\n'
git -C "$SCRIPT_DIR" pull --ff-only < /dev/null || {
    status=$?
    fail "Could not update testing13 (exit code $status). Stopping." "$status"
}

# documentation13
printf '\n>>>>> Updating documentation13 <<<<<<\n'
if [ ! -d "$SCRIPT_DIR/../documentation13" ]; then
    git clone "https://github.com/amaiagalvez/documentation13.git" "$SCRIPT_DIR/../documentation13" < /dev/null || {
        status=$?
        fail "Could not clone documentation13 (exit code $status). Stopping." "$status"
    }
fi

git -C "$SCRIPT_DIR/../documentation13" pull --ff-only < /dev/null || {
    status=$?
    fail "Could not update documentation13 (exit code $status). Stopping." "$status"
}
    
# packages    
mkdir -p "$SCRIPT_DIR/../packages" || fail "Could not create the packages directory."

source "$SCRIPT_DIR/helpers.sh"

[ -f "$PACKAGES" ] || fail "$PACKAGES not found."
if [ "${1:-}" = "all" ]; then
    [ -f "$SCRIPT_DIR/runAll.sh" ] || fail "runAll.sh not found."
fi

packages=()
while IFS= read -r line || [ -n "$line" ]; do
    package="$(parse_name "$line")" || fail "Could not read the package: $line."
    [ -n "$package" ] || continue

    [[ "$package" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || fail "Invalid package name: $package."
    packages+=("$package")
done < "$PACKAGES"

[ "${#packages[@]}" -gt 0 ] || fail "No packages found in $PACKAGES."

for package in "${packages[@]}"; do
    if [ -d "$PACKAGES_DIR/$package" ]; then
        printf 'Keeping existing package: %s\n' "$package"
        continue
    fi

    printf '\n>>>>> Cloning %s <<<<<<\n' "$package"
    git clone "https://github.com/amaiagalvez/$package.git" "$PACKAGES_DIR/$package" < /dev/null || {
        status=$?
        fail "Could not clone $package (exit code $status). runAll will not be executed." "$status"
    }
done

for package in "${packages[@]}"; do
    printf '\n>>>>> Updating %s <<<<<<\n' "$package"
    changes="$(git -C "$PACKAGES_DIR/$package" status --porcelain --untracked-files=all)" || {
        status=$?
        fail "Could not check the working tree for $package (exit code $status). Stopping." "$status"
    }
    if [ -n "$changes" ]; then
        printf '\033[0;31m%s\033[0m\n' "$changes" >&2
        fail "$package has uncommitted changes or untracked files. Commit or stash them before continuing. Stopping."
    fi

    git -C "$PACKAGES_DIR/$package" pull --ff-only < /dev/null || {
        status=$?
        fail "Could not update $package (exit code $status). Check the Git error and any uncommitted changes. Stopping." "$status"
    }

    for branch in master develop; do
        printf '\n>>>>> Updating %s: %s <<<<<<\n' "$package" "$branch"
        git -C "$PACKAGES_DIR/$package" switch "$branch" < /dev/null || {
            status=$?
            fail "Could not switch $package to $branch (exit code $status). Check the Git error and any uncommitted changes. Stopping." "$status"
        }

        git -C "$PACKAGES_DIR/$package" pull --ff-only < /dev/null || {
            status=$?
            fail "Could not update $package on $branch (exit code $status). Check the Git error and any uncommitted changes. Stopping." "$status"
        }
    done
done

if [ "${1:-}" = "all" ]; then
    for package in "${packages[@]}"; do
        bash "$SCRIPT_DIR/runAll.sh" "$package" || {
            status=$?
            fail "runAll failed for $package (exit code $status)." "$status"
        }
    done
fi

shopt -s nullglob
link_scripts=("$SCRIPT_DIR"/agents/link-*.sh)
shopt -u nullglob

[ "${#link_scripts[@]}" -gt 0 ] || fail "No link scripts found in $SCRIPT_DIR/agents."

for script in "${link_scripts[@]}"; do
    printf '\n>>>>> %s <<<<<<\n' "$(basename "$script")"
    bash "$script" "$SCRIPT_DIR/.." || {
        status=$?
        fail "$(basename "$script") failed (exit code $status)." "$status"
    }
done

printf '\nProcess completed for all packages.\n'
}
