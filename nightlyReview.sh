#!/bin/bash

# Revisión completa desatendida (skill full-review). Se programa desde el timer
# de usuario opencode-nightly.timer. El agente nightly-review solo puede escribir
# en .github/reviews/, así que el repositorio queda intacto.

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE="projects/demo13/docker-compose.yml"
# El modelo por defecto de la sesión está deprecado; se fija uno para que la
# revisión no dependa de lo que haya configurado en ese momento.
MODEL="${NIGHTLY_REVIEW_MODEL:-opencode/space-bunny-free}"
DATE="$(date +%F)"
LOG_DIR="$HOME/.local/state/opencode"
LOG="$LOG_DIR/full-review-$DATE.log"

mkdir -p "$LOG_DIR" || exit 1

cd "$REPO" || exit 1

# El agente valida con DX (docker compose exec laravel13) y el MCP laravel-boost
# levanta sus propios contenedores; sin el stack arriba casi todo sale NOT RUN.
docker compose -f "$COMPOSE" up -d laravel13 >>"$LOG" 2>&1

# --auto aprueba lo que no esté denegado explícitamente; los deny del agente se
# siguen aplicando. Sin questions, porque a esta hora no hay nadie delante.
opencode run --auto --agent nightly-review --model "$MODEL" --title "full-review $DATE" \
    "Ejecuta la skill full-review completa sobre el estado actual del repositorio. \
No hagas preguntas ni pidas confirmaciones: si tienes dudas dejalo por escrito y deja el \
informe escrito en .github/reviews/$DATE/CODE-REVIEW.md. Al terminar, resume en una \
frase el número de hallazgos por severidad." >>"$LOG" 2>&1
status=$?

{
    echo "----------------------------------------------------------"
    echo "Exit code: $status"
    echo "Report:    $REPO/.github/reviews/$DATE/CODE-REVIEW.md"
    echo "Full log:  $LOG"
    tail -n 20 "$LOG"
} >>"$LOG" 2>&1

printf 'full-review %s: exit %s (see %s)\n' "$DATE" "$status" "$LOG"

exit $status