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
PROJECTS_DIR="$SCRIPT_DIR/../projects"
mkdir -p "$PROJECTS_DIR" || fail "Could not create the projects directory."

if [ -L "$PROJECTS_DIR/packages" ]; then
    [ "$(readlink "$PROJECTS_DIR/packages")" = "../packages" ] || fail "projects/packages points to an unexpected location."
elif [ -e "$PROJECTS_DIR/packages" ]; then
    fail "projects/packages already exists and is not a symlink."
else
    ln -s ../packages "$PROJECTS_DIR/packages" || fail "Could not link projects/packages."
fi

source "$SCRIPT_DIR/helpers.sh"

[ -f "$PACKAGES" ] || fail "$PACKAGES not found."
PROJECTS="$SCRIPT_DIR/02.projects.txt"
[ -f "$PROJECTS" ] || fail "$PROJECTS not found."

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

projects=()
while IFS= read -r line || [ -n "$line" ]; do
    project="$(parse_name "$line")" || fail "Could not read the project: $line."
    [ -n "$project" ] || continue

    [[ "$project" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || fail "Invalid project name: $project."
    projects+=("$project")
done < "$PROJECTS"

repositories=("${packages[@]}" "${projects[@]}")
repository_paths=()
for package in "${packages[@]}"; do
    repository_paths+=("$PACKAGES_DIR/$package")
done
for project in "${projects[@]}"; do
    repository_paths+=("$PROJECTS_DIR/$project")
done

for index in "${!repositories[@]}"; do
    repository="${repositories[$index]}"
    repository_path="${repository_paths[$index]}"
    if [ -d "$repository_path" ]; then
        printf 'Keeping existing repository: %s\n' "$repository"
        continue
    fi

    printf '\n>>>>> Cloning %s <<<<<<\n' "$repository"
    git clone "https://github.com/amaiagalvez/$repository.git" "$repository_path" < /dev/null || {
        status=$?
        fail "Could not clone $repository (exit code $status). Stopping." "$status"
    }
done

for index in "${!repositories[@]}"; do
    repository="${repositories[$index]}"
    repository_path="${repository_paths[$index]}"
    printf '\n>>>>> Updating %s <<<<<<\n' "$repository"
    changes="$(git -C "$repository_path" status --porcelain --untracked-files=all)" || {
        status=$?
        fail "Could not check the working tree for $repository (exit code $status). Stopping." "$status"
    }
    if [ -n "$changes" ]; then
        printf '\033[0;31m%s\033[0m\n' "$changes" >&2
        fail "$repository has uncommitted changes or untracked files. Commit or stash them before continuing. Stopping."
    fi

    git -C "$repository_path" pull --ff-only < /dev/null || {
        status=$?
        fail "Could not update $repository (exit code $status). Check the Git error and any uncommitted changes. Stopping." "$status"
    }

    for branch in master develop; do
        printf '\n>>>>> Updating %s: %s <<<<<<\n' "$repository" "$branch"
        git -C "$repository_path" switch "$branch" < /dev/null || {
            status=$?
            fail "Could not switch $repository to $branch (exit code $status). Check the Git error and any uncommitted changes. Stopping." "$status"
        }

        git -C "$repository_path" pull --ff-only < /dev/null || {
            status=$?
            fail "Could not update $repository on $branch (exit code $status). Check the Git error and any uncommitted changes. Stopping." "$status"
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

printf '\nProcess completed for all packages and projects.\n'
}
