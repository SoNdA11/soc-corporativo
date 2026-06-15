#!/bin/bash
# ============================================================
# COMMON HELPERS — Funcoes compartilhadas entre scripts do SOC
# ============================================================
# Uso: source "$(dirname "$0")/lib/common.sh"
# ============================================================

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[SOC]${NC} $1"; }
warn() { echo -e "${YELLOW}[AVISO]${NC} $1"; }
err()  { echo -e "${RED}[ERRO]${NC} $1"; exit 1; }

# ------------------------------------------------------------------
# run_root COMANDO [ARG...]
#   Executa comando com privilegios de root.
#   Tenta, nesta ordem:
#     1. sudo -n (sem senha, se configurado NOPASSWD)
#     2. sudo  (com senha interativa)
#     3. su -c (com senha de root)
# ------------------------------------------------------------------
run_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
    return $?
  fi

  # 1) Tenta passwordless sudo
  if command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
    sudo "$@"
    return $?
  fi

  # 2) Tenta sudo com senha
  if command -v sudo &>/dev/null; then
    echo -e "${YELLOW}Digite a senha do USUARIO para sudo:${NC}" >&2
    sudo "$@"
    local rc=$?
    [ $rc -eq 0 ] && return 0
    # Se sudo falhou (senha errada 3x), tenta su
    echo -e "${YELLOW}sudo falhou. Tentando su -c (senha de ROOT)...${NC}" >&2
  fi

  # 3) Fallback: su -c
  if command -v su &>/dev/null; then
    local cmd_str
    printf -v cmd_str '%q ' "$@"
    echo -e "${YELLOW}Digite a senha de ROOT:${NC}" >&2
    su -c "$cmd_str"
    return $?
  fi

  err "Nao foi possivel obter privilegios de root (sudo e su indisponiveis)"
}
