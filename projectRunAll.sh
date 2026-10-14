#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

usage(){
    printf 'Usage: bash %s <project|short-name>\n' "${BASH_SOURCE[0]}"
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
    fail "Project list not found: $projects_file."
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
    fail "Project not found: $1."
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

git symbolic-ref --quiet --short HEAD > /dev/null || fail "$project has no active branch. Switch to a branch before continuing."

printf '\n>>>>> Updating %s: current branch <<<<<<\n' "$project"
git pull --ff-only < /dev/null || {
    status=$?
    fail "Could not update $project on the current branch (exit code $status)." "$status"
}

if [ ! -f docker-compose.yml ]; then
    fail "docker-compose.yml not found for $project."
fi

services="$(docker compose --profile '*' config --services)"
status=$?
if [ "$status" -ne 0 ]; then
    fail "Cannot read Compose services for $project (exit code $status)." "$status"
fi

declare -A action_services
for action in composer npm-all reformat review phpunit dusk; do
    while IFS= read -r service; do
        if [[ "$service" = *-"$action" ]]; then
            if [ -n "${action_services[$action]:-}" ]; then
                fail "Multiple Compose services match $action for $project."
            fi
            action_services[$action]="$service"
        fi
    done <<< "$services"

    if [ -z "${action_services[$action]:-}" ]; then
        fail "Compose service ending in -$action not found for $project."
    fi
done

for script in dumpAutoload composerInstall npm-all reformat review phpunit dusk; do
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
        dusk)
            docker compose --profile dusk run --rm -e XDEBUG_MODE=off \
                "${action_services[dusk]}" \
                php vendor/bin/phpunit -c /packages/basics13/tooling/phpunit.dusk.xml
            ;;
        *)
            docker compose --profile "$script" run --rm -e XDEBUG_MODE=off \
                "${action_services[$script]}"
            ;;
    esac

    status=$?
    if [ "$status" -ne 0 ]; then
        fail "$script failed for $project (exit code $status)." "$status"
    fi
done

printf '\nProcess completed for %s.\n' "$project"
