#!/bin/bash
# ============================================================
# DEPLOY TO KALI — Copia script de ataque e chave SSH para Kali
# ============================================================
# Uso: bash deploy-to-kali.sh [usuario_kali] [ip_kali]
# Default: kali@192.168.56.20
# ============================================================

KALI_USER="${1:-kali}"
KALI_IP="${2:-}"
SSH_KEY_SRC="${KALI_SSH_KEY_DIR:-/tmp/soc-ssh-key}"
SCRIPT_SRC="$(cd "$(dirname "$0")" && pwd)/../04-operacao/ataques-opcao5.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[DEPLOY]${NC} $1"; }
warn() { echo -e "${YELLOW}[AVISO]${NC} $1"; }
err()  { echo -e "${RED}[ERRO]${NC} $1"; exit 1; }

# Auto-detectar IP do Kali se nao foi fornecido
if [ -z "$KALI_IP" ]; then
  log "Auto-detectando IP do Kali na rede 192.168.56.0/24..."
  KALI_IP=$(nmap -sn 192.168.56.0/24 -oG - 2>/dev/null | grep "Up$" | grep -v "192.168.56.1" | head -1 | awk '{print $2}' || true)
  if [ -z "$KALI_IP" ]; then
    warn "Auto-deteccao falhou. Tentando IP padrao 192.168.56.20..."
    KALI_IP="192.168.56.20"
  else
    log "Kali detectado em ${KALI_IP}"
  fi
fi

KALI_SSH="${KALI_USER}@${KALI_IP}"

# Verificar se a chave SSH existe
if [ ! -f "${SSH_KEY_SRC}" ]; then
  err "Chave SSH nao encontrada em ${SSH_KEY_SRC}. Execute setup-opcao5.sh primeiro."
fi

# Verificar se o script de ataque existe
if [ ! -f "${SCRIPT_SRC}" ]; then
  err "Script de ataque nao encontrado em ${SCRIPT_SRC}"
fi

log "Verificando conectividade com ${KALI_SSH}..."
if ! ping -c 1 -W 2 "${KALI_IP}" >/dev/null 2>&1; then
  err "Kali VM (${KALI_IP}) nao responde. Verifique se a VM esta ligada."
fi

log "Copiando chave SSH para ${KALI_SSH}:/tmp/id_ed25519..."
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "${SSH_KEY_SRC}" "${KALI_SSH}:/tmp/id_ed25519" || {
  err "Falha ao copiar chave SSH. Verifique se o SSH esta rodando no Kali e as credenciais."
}

log "Copiando script de ataque para ${KALI_SSH}:/home/kali/ataques.sh..."
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "${SCRIPT_SRC}" "${KALI_SSH}:/home/kali/ataques.sh" || {
  err "Falha ao copiar script de ataque."
}

log "Ajustando permissoes no Kali..."
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  "${KALI_SSH}" "chmod 600 /tmp/id_ed25519 && chmod +x /home/kali/ataques.sh" || {
  err "Falha ao ajustar permissoes no Kali."
}

echo ""
log "============================================"
log "  DEPLOY CONCLUIDO"
log "============================================"
echo ""
echo "  No Kali, execute:"
echo "    bash /home/kali/ataques.sh"
echo ""
echo "  Para conectar via SSH:"
echo "    ssh ${KALI_SSH}"
echo ""
