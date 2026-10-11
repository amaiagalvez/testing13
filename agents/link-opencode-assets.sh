#!/usr/bin/env bash
#
# Links the Copilot agents and skills to the locations OpenCode discovers.
# Runnable from any directory; accepts an optional repository root.

set -euo pipefail

RED='\033[0;31m'
NC='\033[0m' # No Color

fail(){
    printf "${RED}Error: %s${NC}\n" "$1" >&2
    exit "${2:-1}"
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ $# -gt 0 ]]; then
    root="$1"
else
    root="$script_dir"
    while [[ "$root" != "/" && ( ! -d "$root/.github/agents" || ! -d "$root/.github/skills" ) ]]; do
        root="$(dirname "$root")"
    done
fi
cd "$root"

AGENTS_SRC=".github/agents"
AGENTS_DEST=".opencode/agents"
SKILLS_SRC=".github/skills"
SKILLS_DEST=".opencode/skills"

if [[ ! -d "$AGENTS_SRC" || ! -d "$SKILLS_SRC" ]]; then
    fail "$AGENTS_SRC and/or $SKILLS_SRC not found under $root."
fi

probe_dir="$(mktemp -d)"
if ! ln -s /dev/null "$probe_dir/probe" 2>/dev/null || [[ ! -L "$probe_dir/probe" ]]; then
    rm -f "$probe_dir/probe"
    rmdir "$probe_dir"
    fail "This system does not support creating symlinks."
fi
rm -f "$probe_dir/probe"
rmdir "$probe_dir"

mkdir -p "$AGENTS_DEST"

# Leaves the managed folder clean and keeps any regular file the script does not manage.
while IFS= read -r -d '' link_path; do
    rm -f "$link_path"
done < <(find "$AGENTS_DEST" -mindepth 1 -maxdepth 1 -type l -print0)

printf 'Agents (.github/agents -> .opencode/agents)\n'
for src in "$AGENTS_SRC"/*.agent.md; do
    [[ -e "$src" ]] || continue
    id="$(basename "$src" .agent.md)"
    dest="$AGENTS_DEST/$id.md"

    if [[ -e "$dest" || -L "$dest" ]]; then
        fail "$dest already exists and is not a symlink managed by this script."
    fi

    ln -s "../../$AGENTS_SRC/$id.agent.md" "$dest"
    printf '  + %s\n' "$id"
done

if [[ -e "$SKILLS_DEST" && ! -L "$SKILLS_DEST" ]]; then
    fail "$SKILLS_DEST exists and is not a symlink; it will not be replaced."
fi
if [[ -L "$SKILLS_DEST" ]]; then
    rm -f "$SKILLS_DEST"
fi
ln -s "../$SKILLS_SRC" "$SKILLS_DEST"

printf 'Skills: %s -> %s\n' "$SKILLS_DEST" "$SKILLS_SRC"
printf 'Edit agents and skills only in .github; content changes are visible through the symlinks immediately.\n'

if command -v opencode >/dev/null 2>&1; then
    printf 'Restarting the OpenCode service...\n'
    if ! opencode service restart; then
        fail "Links were created, but OpenCode could not be restarted. Run \`opencode service restart\` manually."
    fi
    printf 'Done. OpenCode service restarted.\n'
else
    printf 'Warning: the OpenCode CLI was not found; run `opencode service restart` when it becomes available.\n' >&2
fi
