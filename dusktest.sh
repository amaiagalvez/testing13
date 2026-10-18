#!/bin/bash

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

usage(){
    cat <<'USAGE'
Usage: bash testing13/dusktest.sh [package|short-name|all|app] [Dusk options...]

Without a target, runs the browser suites of all installed packages.
app runs only the consuming application's browser tests.
Packages without browser tests are skipped in all mode.
PRO selects the integrated project and epic flows from entity-projects13
when projects13 has no standalone browser suite.

Examples:
  bash testing13/dusktest.sh
  bash testing13/dusktest.sh CUSPRO
  bash testing13/dusktest.sh PRO
  bash testing13/dusktest.sh CUSPRO --filter=ProjectCrudTest
  bash testing13/dusktest.sh app
  DUSK_PROJECT=d13 bash testing13/dusktest.sh CUSPRO

DUSK_PROJECT selects the consuming project by folder name or alias (default: demo13).
The project must have installed dependencies, built assets, phpunit.dusk.xml,
and a Compose service ending in -dusk. That service and its dependencies are
started automatically and left running. Tests use the project's Dusk database;
do not run them concurrently with PHPUnit suites using the same database.
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
fi

target="all"
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then
    target="$1"
    shift
fi

project_target="${DUSK_PROJECT:-demo13}"

# Check if another Dusk run is already using this project's lock
command -v flock >/dev/null 2>&1 || fail "flock is required to prevent concurrent Dusk runs."
exec 9> "${TMPDIR:-/tmp}/testing13-dusk-$(id -u)-${project_target}.lock" || fail "Cannot open the Dusk lock."
flock -n 9 || { echo "WARNING: Another Dusk run is already using $project_target. Exiting."; exit 1; }

projects_file="$SCRIPT_DIR/02.projects.txt"
[ -f "$projects_file" ] || fail "Project list not found: $projects_file."

project=""
while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    name="$(parse_name "$line")"
    short="$(parse_short "$line")"
    if [ "${name,,}" = "${project_target,,}" ] || [ "${short,,}" = "${project_target,,}" ]; then
        project="$name"
        break
    fi
done < "$projects_file"

[ -n "$project" ] || fail "Project not found: $project_target."
[[ "$project" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || fail "Invalid project name: $project."
project_dir="$SCRIPT_DIR/../projects/$project"

for required in artisan vendor/autoload.php vendor/laravel/dusk/src/Console/DuskCommand.php phpunit.dusk.xml docker-compose.yml; do
    [ -f "$project_dir/$required" ] || fail "$required not found for $project. Prepare the consuming application first."
done

browser_paths=()
has_browser_tests(){
    [ -d "$1" ] && [ -n "$(find "$1" -type f -name '*Test.php' -print -quit)" ]
}

add_package_suite(){
    local package="$1"
    local browser_path="vendor/amaia/$package/tests/Browser"

    if ! has_browser_tests "$project_dir/$browser_path"; then
        if [ "${target,,}" = "all" ]; then
            printf 'Skipping %s: no installed browser suite.\n' "$package"
            return 0
        fi
        if [ "$package" = "projects13" ]; then
            local bridge_path="vendor/amaia/entity-projects13/tests/Browser"
            local domain
            for domain in Projects Epics; do
                has_browser_tests "$project_dir/$bridge_path/$domain" \
                    || fail "Integrated $domain browser suite not found in $project."
                browser_paths+=("$bridge_path/$domain")
            done
            printf 'Using entity-projects13 browser integration for projects13.\n'
            return 0
        fi
        fail "No installed browser suite for $package in $project."
    fi

    browser_paths+=("$browser_path")
}

case "${target,,}" in
    app)
        has_browser_tests "$project_dir/tests/Browser" || fail "No application browser suite for $project."
        browser_paths+=("tests/Browser")
        ;;
    all)
        [ -f "$PACKAGES" ] || fail "Package list not found: $PACKAGES."
        while IFS= read -r line || [ -n "$line" ]; do
            package="$(parse_name "$line")"
            [ -z "$package" ] && continue
            add_package_suite "$package"
        done < "$PACKAGES"
        ;;
    *)
        package="$(resolve_package "$target")" || not_found
        add_package_suite "$package"
        ;;
esac

[ "${#browser_paths[@]}" -gt 0 ] || fail "No installed package browser suites found in $project."
cd "$project_dir" || exit 1

command -v flock >/dev/null 2>&1 || fail "flock is required to prevent concurrent Dusk runs."
exec 9> "${TMPDIR:-/tmp}/testing13-dusk-$(id -u)-$project.lock" || fail "Cannot open the Dusk lock."
flock -n 9 || fail "Another Dusk run is already using $project. Wait for it to finish."

services="$(docker compose config --services)" || fail "Cannot read Compose services for $project."
dusk_service=""
while IFS= read -r service; do
    if [[ "$service" = *-dusk ]]; then
        [ -z "$dusk_service" ] || fail "Multiple Compose services ending in -dusk for $project."
        dusk_service="$service"
    fi
done <<< "$services"
[ -n "$dusk_service" ] || fail "Compose service ending in -dusk not found for $project."

printf '\n>>>>> %s: Dusk (%s) <<<<<<\n' "$project" "$target"
docker compose up -d --wait "$dusk_service" || exit $?
docker compose exec -T "$dusk_service" curl --fail --silent --show-error \
    --retry 10 --retry-delay 1 --retry-all-errors --connect-timeout 5 --max-time 10 \
    --output /dev/null http://localhost/ || fail "The Dusk application is not responding."

docker compose exec -T --user "$(id -u):$(id -g)" -e XDEBUG_MODE=off "$dusk_service" \
    php artisan dusk --no-interaction --without-tty "${browser_paths[@]}" "$@"
exit $?
