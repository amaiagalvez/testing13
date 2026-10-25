#!/bin/bash

# Multi-browser, multi-screen Dusk test runner
# Uses `docker compose run -d` for persistent web server + `docker exec` for tests
# Sequential mode: single server, multiple exec (fast, reliable)
# Parallel mode: not implemented (use Selenium Grid for true parallel)
#  bash dusktest_multi.sh ENT -b chrome,firefox -s desktop,mobile --sequential
# Screenshots - projects/demo13/storage/app/dusk-screenshots/
#Logs de consola - en projects/demo13/tests/Browser/console/

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

usage(){
    cat <<'USAGE'
Usage: bash testing13/dusktest_multi.sh [package|short-name|all|app] [OPTIONS] [Dusk options...]

Runs Dusk browser tests across multiple browsers and screen sizes.

TARGETS (same as dusktest.sh):
  all          Run browser suites of all installed packages (default)
  app          Run only the consuming application's browser tests
  BAS|basics13     Run basics13 browser tests
  ENT|entities13   Run entities13 browser tests
  PRO|projects13   Run projects13 browser tests (via entity-projects13 bridge)
  ENTPRO|entity-projects13  Run entity-projects13 browser tests

MATRIX OPTIONS:
  -b, --browsers LIST      Comma-separated browsers: chrome,firefox,edge (default: chrome)
  -s, --sizes LIST         Comma-separated screen sizes: 
                           desktop,tablet,mobile,desktop-small,desktop-xl,
                           tablet-landscape,mobile-large,mobile-xl,mobile-fold (default: desktop)
  -H, --headed             Run headed (non-headless) mode
  -f, --filter PATTERN     PHPUnit filter (passed to php artisan dusk)
      --continue-on-fail   Continue matrix even if some combinations fail

EXAMPLES:
  # All packages, Chrome desktop (default)
  bash testing13/dusktest_multi.sh

  # entities13 in Chrome + Firefox at desktop + mobile
  bash testing13/dusktest_multi.sh ENT -b chrome,firefox -s desktop,mobile

  # All packages, all browsers, all sizes (full matrix)
  bash testing13/dusktest_multi.sh all -b chrome,firefox,edge -s desktop,tablet,mobile

  # Headed mode for debugging
  bash testing13/dusktest_multi.sh ENT -b chrome -s desktop -H

  # With PHPUnit filter
  bash testing13/dusktest_multi.sh ENT --filter=EntityCrudTest -b chrome,firefox

  # Continue on fail
  bash testing13/dusktest_multi.sh ENT -b chrome,firefox -s desktop,mobile --continue-on-fail

ENVIRONMENT:
  DUSK_PROJECT     Select project (default: demo13)

NOTE: Runs sequentially (one combination at a time) using a persistent web server.
      For true parallel execution, use Selenium Grid (not implemented in this script).

USAGE
}

# Parse arguments
target="all"
browsers="chrome"
sizes="desktop"
headed="false"
continue_on_fail="false"
filter_args=()

# First pass: extract target (first non-option arg)
remaining_args=()
for arg in "$@"; do
    if [[ "$arg" != -* ]] && [[ -z "${target_set:-}" ]]; then
        target="$arg"
        target_set=1
    else
        remaining_args+=("$arg")
    fi
done

# Second pass: parse options
set -- "${remaining_args[@]}"
while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--browsers)
            browsers="$2"
            shift 2
            ;;
        -s|--sizes)
            sizes="$2"
            shift 2
            ;;
        -H|--headed)
            headed="true"
            shift
            ;;
        -f|--filter)
            filter_args+=("--filter=$2")
            shift 2
            ;;
        --continue-on-fail)
            continue_on_fail="true"
            shift
            ;;
        --sequential)
            # Already sequential by default, just acknowledge
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        -p|--parallel|-j|--jobs)
            printf '⚠️  Parallel mode (-p/-j) not implemented in this version.\n'
            printf '    Use Selenium Grid for true parallel execution.\n'
            printf '    Running sequentially instead.\n'
            shift $([ "$1" = "-j" ] && echo 2 || echo 1)
            ;;
        *)
            # Pass through to dusk
            filter_args+=("$1")
            shift
            ;;
    esac
done

# Split comma-separated lists into arrays
IFS=',' read -ra BROWSER_ARRAY <<< "$browsers"
IFS=',' read -ra SIZE_ARRAY <<< "$sizes"

# Validate browsers
valid_browsers=("chrome" "firefox" "edge")
for b in "${BROWSER_ARRAY[@]}"; do
    if [[ ! " ${valid_browsers[*]} " =~ " ${b} " ]]; then
        fail "Invalid browser: $b. Valid: ${valid_browsers[*]}"
    fi
done

# Validate sizes
valid_sizes=("desktop" "desktop-small" "desktop-xl" "tablet" "tablet-landscape" "mobile" "mobile-large" "mobile-xl" "mobile-fold")
for s in "${SIZE_ARRAY[@]}"; do
    if [[ ! " ${valid_sizes[*]} " =~ " ${s} " ]]; then
        fail "Invalid screen size: $s. Valid: ${valid_sizes[*]}"
    fi
done

# Resolve project (same logic as dusktest.sh)
project_target="${DUSK_PROJECT:-demo13}"

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

# Check required files
for required in artisan vendor/autoload.php vendor/laravel/dusk/src/Console/DuskCommand.php phpunit.dusk.xml docker-compose.yml; do
    [ -f "$project_dir/$required" ] || fail "$required not found for $project. Prepare the consuming application first."
done

# Determine browser test paths (same logic as dusktest.sh)
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

# Lock to prevent concurrent runs
command -v flock >/dev/null 2>&1 || fail "flock is required to prevent concurrent Dusk runs."
exec 9> "${TMPDIR:-/tmp}/testing13-dusk-multi-$(id -u)-${project}.lock" || fail "Cannot open the Dusk lock."
flock -n 9 || { echo "WARNING: Another Dusk run is already using $project. Exiting."; exit 1; }

cd "$project_dir" || exit 1

# Get the dusk service name
services="$(docker compose --profile '*' config --services)" || fail "Cannot read Compose services for $project."
dusk_service=""
while IFS= read -r service; do
    if [[ "$service" = *-dusk ]]; then
        [ -z "$dusk_service" ] || fail "Multiple Compose services ending in -dusk for $project."
        dusk_service="$service"
    fi
done <<< "$services"
[ -n "$dusk_service" ] || fail "Compose service ending in -dusk not found for $project."

# Global variable for server container ID
SERVER_CONTAINER_ID=""

# Function to start the dusk web server using `run -d`
start_dusk_server() {
    printf '\n🌐 Starting Dusk web server (%s) via run -d...\n' "$dusk_service"
    
    # Start server container in background with tty (stays alive)
    SERVER_CONTAINER_ID=$(docker compose run -d "$dusk_service") || fail "Failed to start $dusk_service"
    
    # Wait for web server to be ready (tight loop, max 10 seconds)
    local retries=20
    while [ $retries -gt 0 ]; do
        if docker exec "$SERVER_CONTAINER_ID" curl --fail --silent --show-error \
            --retry 2 --retry-delay 0 --retry-all-errors --connect-timeout 2 --max-time 3 \
            --output /dev/null http://localhost/ 2>/dev/null; then
            printf '✅ Web server ready (container: %s)\n' "${SERVER_CONTAINER_ID:0:12}"
            return 0
        fi
        sleep 0.5
        retries=$((retries - 1))
    done
    fail "Web server did not become ready in time"
}

# Function to stop the dusk web server
stop_dusk_server() {
    if [ -n "$SERVER_CONTAINER_ID" ]; then
        printf '\n🧹 Stopping Dusk web server (%s)...\n' "${SERVER_CONTAINER_ID:0:12}"
        docker stop "$SERVER_CONTAINER_ID" >/dev/null 2>&1 || true
        docker rm "$SERVER_CONTAINER_ID" >/dev/null 2>&1 || true
        SERVER_CONTAINER_ID=""
    fi
}

# Function to run migrations
run_migrations() {
    printf '\n📦 Running migrations for Dusk database...\n'
    docker exec -u "$(id -u):$(id -g)" -e XDEBUG_MODE=off -e APP_ENV=dusk "$SERVER_CONTAINER_ID" \
        php artisan migrate:fresh --seed --seeder="Database\\Seeders\\AccessSeeder" --force --env=dusk || fail "Migrations failed"
}

# Function to run tests for a single browser/size combination
run_combination() {
    local browser="$1"
    local size="$2"
    local combo_id="$3"
    local total_combos="$4"

    local env_vars=(
        "DUSK_BROWSER=$browser"
        "DUSK_SCREEN_SIZE=$size"
        "DUSK_HEADLESS=$headed"
        "APP_URL=http://localhost"
    )

    printf '\n[%d/%d] %s: browser=%s size=%s headed=%s\n' "$combo_id" "$total_combos" "$target" "$browser" "$size" "$headed"

    # Build the docker exec command with environment variables
    local exec_cmd="docker exec -u \"$(id -u):$(id -g)\" -e XDEBUG_MODE=off"
    for ev in "${env_vars[@]}"; do
        exec_cmd="$exec_cmd -e $ev"
    done
    exec_cmd="$exec_cmd \"$SERVER_CONTAINER_ID\" php artisan dusk --no-interaction --without-tty ${filter_args[*]} ${browser_paths[*]}"

    if eval "$exec_cmd"; then
        printf '✅ [%d/%d] PASSED: browser=%s size=%s\n' "$combo_id" "$total_combos" "$browser" "$size"
        return 0
    else
        local exit_code=$?
        printf '❌ [%d/%d] FAILED: browser=%s size=%s (exit code %d)\n' "$combo_id" "$total_combos" "$browser" "$size" "$exit_code"
        return $exit_code
    fi
}

# Trap to cleanup server on exit
trap 'stop_dusk_server; docker compose stop db >/dev/null 2>&1 || true' EXIT

# Start infrastructure
printf '\n>>>>> %s: Dusk Multi (%s) <<<<<<\n' "$project" "$target"
printf '📦 Starting database...\n'
docker compose up -d --wait db || fail "Failed to start database"

start_dusk_server
run_migrations

# Generate all combinations
combinations=()
for browser in "${BROWSER_ARRAY[@]}"; do
    for size in "${SIZE_ARRAY[@]}"; do
        combinations+=("$browser $size")
    done
done

total_combos=${#combinations[@]}
printf '\n📊 Matrix: %d browser(s) × %d size(s) = %d combination(s)\n' "${#BROWSER_ARRAY[@]}" "${#SIZE_ARRAY[@]}" "$total_combos"
printf 'Browsers: %s\n' "${BROWSER_ARRAY[*]}"
printf 'Sizes:    %s\n' "${SIZE_ARRAY[*]}"
printf 'Headed:   %s\n' "$headed"
printf 'Mode:     Sequential (single persistent server)\n\n'

# Run combinations sequentially
failed_combos=()
passed_combos=()
combo_id=0

for combo in "${combinations[@]}"; do
    combo_id=$((combo_id + 1))
    read -r browser size <<< "$combo"

    if run_combination "$browser" "$size" "$combo_id" "$total_combos"; then
        passed_combos+=("$browser:$size")
    else
        failed_combos+=("$browser:$size:$?")
        if [ "$continue_on_fail" = "false" ]; then
            break
        fi
    fi
done

# Summary (cleanup happens via trap)
printf '\n========================================\n'
printf '📊 DUSK MULTI TEST SUMMARY\n'
printf '========================================\n'
printf 'Target:      %s\n' "$target"
printf 'Project:     %s\n' "$project"
printf 'Total:       %d\n' "$total_combos"
printf 'Passed:      %d\n' "${#passed_combos[@]}"
printf 'Failed:      %d\n' "${#failed_combos[@]}"

if [ "${#passed_combos[@]}" -gt 0 ]; then
    printf '\n✅ PASSED:\n'
    for combo in "${passed_combos[@]}"; do
        printf '   %s\n' "$combo"
    done
fi

if [ "${#failed_combos[@]}" -gt 0 ]; then
    printf '\n❌ FAILED:\n'
    for combo in "${failed_combos[@]}"; do
        printf '   %s\n' "$combo"
    done
fi

if [ "${#failed_combos[@]}" -gt 0 ]; then
    exit 1
fi

exit 0