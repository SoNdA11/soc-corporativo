#!/bin/bash
# ============================================================
# APPLY FIXES — Aplica todas as correcoes no host Arch Linux
# ============================================================
# Uso: bash 02-setup/apply-fixes.sh
#
# Este script aplica TODAS as correcoes mais recentes:
#   1. Journal-bridge com -o short (syslog header preservado)
#   2. Regras de compliance atualizadas (200034 adicionada)
#   3. Scripts de backup/restore com syslog() e set -e
#   4. Healthcheck atualizado (Kali IP auto-detect)
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/common.sh"

# Override log prefix
log() { echo -e "${GREEN}[FIX]${NC} $1"; }

echo ""
log "============================================"
log "  APLICANDO CORRECOES NO HOST"
log "============================================"
echo ""

# ---- 1. Recrear journal-bridge com -o short ----
log "[1/5] Reconfigurando journal-bridge (--output=short)..."
if systemctl is-active --quiet soc-journal-bridge 2>/dev/null; then
  run_root systemctl stop soc-journal-bridge 2>/dev/null || true
fi
bash "$SCRIPT_DIR/fix-journal-bridge.sh"
log "[1/5] OK - journal-bridge reiniciado com -o short"
echo ""

# ---- 2. Recopiar regras de compliance ----
log "[2/5] Copiando regras de compliance para o Wazuh..."
RULES_FILE="$PROJECT_DIR/03-configuracao/local_rules.xml"
if [ -f "$RULES_FILE" ] && docker inspect wazuh-manager >/dev/null 2>&1; then
  docker cp "$RULES_FILE" wazuh-manager:/var/ossec/etc/rules/local_rules.xml 2>/dev/null || true
  docker exec wazuh-manager chown ossec:ossec /var/ossec/etc/rules/local_rules.xml 2>/dev/null || true
  docker exec wazuh-manager chmod 640 /var/ossec/etc/rules/local_rules.xml 2>/dev/null || true
  log "[2/5] OK - Regras copiadas (inclui nova 200034)"
else
  warn "[2/5] Pulei - wazuh-manager nao encontrado ou local_rules.xml ausente"
fi
echo ""

# ---- 3. Reiniciar wazuh-manager ----
log "[3/5] Reiniciando wazuh-manager para carregar regras..."
if docker inspect wazuh-manager >/dev/null 2>&1; then
  docker exec wazuh-manager /var/ossec/bin/ossec-control restart 2>/dev/null || true
  log "[3/5] OK - wazuh-manager reiniciado"
else
  warn "[3/5] Pulei - wazuh-manager nao encontrado"
fi
echo ""

# ---- 4. Atualizar scripts de backup/restore no host ----
log "[4/5] Atualizando scripts de backup/restore..."
if [ -f "$SCRIPT_DIR/fix-backup.sh" ]; then
  bash "$SCRIPT_DIR/fix-backup.sh"
  log "[4/5] OK - Scripts backup/restore atualizados (syslog, set -e)"
else
  warn "[4/5] Pulei - fix-backup.sh nao encontrado"
fi
echo ""

# ---- 5. Verificar saude do ambiente ----
log "[5/5] Verificando saude do ambiente..."
if [ -f "$PROJECT_DIR/04-operacao/healthcheck.sh" ]; then
  bash "$PROJECT_DIR/04-operacao/healthcheck.sh" || true
fi

echo ""
log "============================================"
log "  CORRECOES APLICADAS"
log "============================================"
echo ""
log "Agora execute no Kali:"
log "  bash /home/kali/ataques.sh"
echo ""
log "Os alertas 200033 (RESTORE_EXECUTADO) e"
log "200034 (RANSOMWARE_SIMULATED) devem aparecer"
log "no Wazuh Dashboard."
echo ""
