#!/usr/bin/env bash
#
# Enlaza los agentes y skills de Copilot en las ubicaciones que OpenCode descubre.
# Ejecutable desde cualquier directorio; acepta una raíz de repositorio opcional.

set -euo pipefail

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
    printf 'Error: %s and/or %s not found under %s.\n' "$AGENTS_SRC" "$SKILLS_SRC" "$root" >&2
    exit 1
fi

probe_dir="$(mktemp -d)"
if ! ln -s /dev/null "$probe_dir/probe" 2>/dev/null || [[ ! -L "$probe_dir/probe" ]]; then
    rm -f "$probe_dir/probe"
    rmdir "$probe_dir"
    printf 'Error: this system does not support creating symlinks.\n' >&2
    exit 1
fi
rm -f "$probe_dir/probe"
rmdir "$probe_dir"

mkdir -p "$AGENTS_DEST"

# Deja limpia la carpeta administrada y conserva cualquier archivo normal ajeno al script.
while IFS= read -r -d '' link_path; do
    rm -f "$link_path"
done < <(find "$AGENTS_DEST" -mindepth 1 -maxdepth 1 -type l -print0)

printf 'Agents (.github/agents -> .opencode/agents)\n'
for src in "$AGENTS_SRC"/*.agent.md; do
    [[ -e "$src" ]] || continue
    id="$(basename "$src" .agent.md)"
    dest="$AGENTS_DEST/$id.md"

    if [[ -e "$dest" || -L "$dest" ]]; then
        printf 'Error: %s already exists and is not a symlink managed by this script.\n' "$dest" >&2
        exit 1
    fi

    ln -s "../../$AGENTS_SRC/$id.agent.md" "$dest"
    printf '  + %s\n' "$id"
done

if [[ -e "$SKILLS_DEST" && ! -L "$SKILLS_DEST" ]]; then
    printf 'Error: %s exists and is not a symlink; it will not be replaced.\n' "$SKILLS_DEST" >&2
    exit 1
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
        printf 'Error: links were created, but OpenCode could not be restarted. Run `opencode service restart` manually.\n' >&2
        exit 1
    fi
    printf 'Done. OpenCode service restarted.\n'
else
    printf 'Warning: the OpenCode CLI was not found; run `opencode service restart` when it becomes available.\n' >&2
fi
