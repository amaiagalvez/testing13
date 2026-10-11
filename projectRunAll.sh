#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

usage(){
    printf 'Usage: bash %s <project|short-name>\n' "${BASH_SOURCE[0]}"
}

fail(){
    printf 'Error: %s\n' "$1" >&2
    exit "${2:-1}"
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
    usage >&2
    exit 1
fi

projects_file="$SCRIPT_DIR/02.projects.txt"
if [ ! -f "$projects_file" ]; then
    printf 'Error: project list not found: %s.\n' "$projects_file" >&2
    exit 1
fi

project=""
while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    name="$(parse_name "$line")"
    short="$(parse_short "$line")"
    if [ "${name,,}" = "${1,,}" ] || [ "${short,,}" = "${1,,}" ]; then
        project="$name"
        break
    fi
done < "$projects_file"

if [ -z "$project" ]; then
    printf 'Error: project not found: %s.\n' "$1" >&2
    exit 1
fi

[[ "$project" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || fail "Invalid project name: $project."

project_dir="$SCRIPT_DIR/../projects/$project"
if [ ! -d "$project_dir" ]; then
    mkdir -p "$SCRIPT_DIR/../projects" || fail "Could not create the projects directory."
    printf '\n>>>>> Cloning %s <<<<<<\n' "$project"
    git clone "https://github.com/amaiagalvez/$project.git" "$project_dir" < /dev/null || {
        status=$?
        fail "Could not clone $project (exit code $status)." "$status"
    }
fi

cd "$project_dir" || exit 1

[ -e .git ] || fail "$project is not a Git repository."

changes="$(git status --porcelain --untracked-files=all)" || {
    status=$?
    fail "Could not check the working tree for $project (exit code $status)." "$status"
}
if [ -n "$changes" ]; then
    printf '%s\n' "$changes" >&2
    fail "$project has uncommitted changes or untracked files. Commit or stash them before continuing."
fi

git symbolic-ref --quiet --short HEAD > /dev/null || fail "$project has no active branch. Switch to a branch before continuing."

printf '\n>>>>> Updating %s: current branch <<<<<<\n' "$project"
git pull --ff-only < /dev/null || {
    status=$?
    fail "Could not update $project on the current branch (exit code $status)." "$status"
}

for branch in master develop; do
    printf '\n>>>>> Updating %s: %s <<<<<<\n' "$project" "$branch"
    git switch "$branch" < /dev/null || {
        status=$?
        fail "Could not switch $project to $branch (exit code $status)." "$status"
    }
    git pull --ff-only < /dev/null || {
        status=$?
        fail "Could not update $project on $branch (exit code $status)." "$status"
    }
done

if [ ! -f docker-compose.yml ]; then
    printf 'Error: docker-compose.yml not found for %s.\n' "$project" >&2
    exit 1
fi

services="$(docker compose --profile '*' config --services)"
status=$?
if [ "$status" -ne 0 ]; then
    printf 'Error: cannot read Compose services for %s (exit code %s).\n' "$project" "$status" >&2
    exit "$status"
fi

declare -A action_services
for action in composer reformat review phpunit; do
    while IFS= read -r service; do
        if [[ "$service" = *-"$action" ]]; then
            if [ -n "${action_services[$action]:-}" ]; then
                printf 'Error: multiple Compose services match %s for %s.\n' "$action" "$project" >&2
                exit 1
            fi
            action_services[$action]="$service"
        fi
    done <<< "$services"

    if [ -z "${action_services[$action]:-}" ]; then
        printf 'Error: Compose service ending in -%s not found for %s.\n' "$action" "$project" >&2
        exit 1
    fi
done

for script in dumpAutoload composerInstall reformat review phpunit; do
    printf '\n>>>>> %s: %s <<<<<<\n' "$project" "$script"

    case "$script" in
        dumpAutoload)
            docker compose --profile composer run --rm -e XDEBUG_MODE=off \
                --entrypoint bash "${action_services[composer]}" -c \
                'composer dump-autoload --optimize --no-interaction && composer clear-cache --no-interaction && if [ -f artisan ]; then php artisan optimize:clear --no-interaction; fi'
            ;;
        composerInstall)
            docker compose --profile composer run --rm -e XDEBUG_MODE=off \
                "${action_services[composer]}"
            ;;
        phpunit)
            docker compose --profile phpunit run --rm -e XDEBUG_MODE=coverage \
                "${action_services[phpunit]}"
            ;;
        *)
            docker compose --profile "$script" run --rm -e XDEBUG_MODE=off \
                "${action_services[$script]}"
            ;;
    esac

    status=$?
    if [ "$status" -ne 0 ]; then
        printf 'Error: %s failed for %s (exit code %s).\n' "$script" "$project" "$status" >&2
        exit "$status"
    fi
done

printf '\nProcess completed for %s.\n' "$project"
