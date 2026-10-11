#!/usr/bin/env bash
#
# Enlaza los agentes y skills de Copilot en las ubicaciones que Claude Code descubre.
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
AGENTS_DEST=".claude/agents"
SKILLS_SRC=".github/skills"
SKILLS_DEST=".claude/skills"
GENERATED_MARKER="Generated from .github/agents by testing13/agents/link-claude-assets.sh."

if [[ ! -d "$AGENTS_SRC" || ! -d "$SKILLS_SRC" ]]; then
    printf 'Error: %s and/or %s not found under %s.\n' "$AGENTS_SRC" "$SKILLS_SRC" "$root" >&2
    exit 1
fi

mkdir -p "$AGENTS_DEST"

# Retira los enlaces previos y las copias generadas por versiones anteriores.
while IFS= read -r -d '' link_path; do
    rm -f "$link_path"
done < <(find "$AGENTS_DEST" -mindepth 1 -maxdepth 1 -type l -print0)

while IFS= read -r -d '' generated_file; do
    if grep -qF "$GENERATED_MARKER" "$generated_file"; then
        rm -f "$generated_file"
    fi
done < <(find "$AGENTS_DEST" -mindepth 1 -maxdepth 1 -type f -name '*.md' -print0)

if [[ -e "$SKILLS_DEST" && ! -L "$SKILLS_DEST" ]]; then
    printf 'Error: %s exists and is not a symlink; it will not be replaced.\n' "$SKILLS_DEST" >&2
    exit 1
fi
if [[ -L "$SKILLS_DEST" ]]; then
    rm -f "$SKILLS_DEST"
fi
ln -s "../$SKILLS_SRC" "$SKILLS_DEST"

printf 'Agents (.github/agents -> .claude/agents)\n'
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

printf '\nSkills: %s -> %s\n' "$SKILLS_DEST" "$SKILLS_SRC"
printf 'Done. Edit agents and skills only in .github; content changes are visible through the symlinks immediately.\n'
