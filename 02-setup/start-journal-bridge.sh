#!/bin/bash
# ============================================================
# JOURNAL BRIDGE - Forward journald logs to Wazuh Agent
# ============================================================
# Cria um arquivo de log contínuo a partir do journald
# para que o Wazuh Agent possa monitorar os logs do sistema.
#
# Uso:
#   ./start-journal-bridge.sh           # Iniciar em foreground
#   ./start-journal-bridge.sh --daemon  # Iniciar como daemon (nohup)
# ============================================================

OUTPUT_FILE="/var/log/soc-corporativo/soc-journal.log"
CURSOR_FILE="/var/run/soc-journal-cursor"
SLEEP_INTERVAL=5

mkdir -p "$(dirname "$OUTPUT_FILE")"
mkdir -p "$(dirname "$CURSOR_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

if [ "$1" = "--daemon" ]; then
    log "Iniciando em background (PID: $$)..."
    nohup "$0" > "$(dirname "$OUTPUT_FILE")/bridge.log" 2>&1 &
    disown
    exit 0
fi

log "Journal Bridge iniciado. Output: $OUTPUT_FILE"
log "Monitorando journald a cada ${SLEEP_INTERVAL}s..."
log "Pressione Ctrl+C para parar."

# Usar array para evitar problemas de quoting com argumentos compostos
CURSOR_ARGS=()
if [ -f "$CURSOR_FILE" ]; then
    CURSOR_ARGS=(--cursor "$(cat "$CURSOR_FILE")")
fi

while true; do
    journalctl -n 50 --no-pager --output=short \
        "${CURSOR_ARGS[@]}" \
        --since "1 hour ago" >> "$OUTPUT_FILE" 2>/dev/null

    # Salvar cursor atual para proxima iteracao
    journalctl -n 1 --no-pager --output=export 2>/dev/null | \
        grep -oP '__CURSOR=\K.*' | head -1 > "$CURSOR_FILE"

    # Apenas eventos recentes (ultimos 10 min) nas proximas iteracoes
    CURSOR_ARGS=(--since "10 minutes ago")

    sleep "$SLEEP_INTERVAL"
done
