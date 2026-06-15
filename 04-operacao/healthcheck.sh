#!/bin/bash
# ============================================================
# HEALTHCHECK - Verifica se todos os componentes estao OK
# ============================================================
# Uso: bash healthcheck.sh
# Retorna: 0 se tudo ok, 1 se algo falhou
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
FAIL=0

check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✔${NC} $desc"
    else
        echo -e "  ${RED}✘${NC} $desc"
        FAIL=1
    fi
}

warn() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✔${NC} $desc"
    else
        echo -e "  ${YELLOW}⚠${NC} $desc (nao critico)"
    fi
}

echo "============================================"
echo "  HEALTHCHECK - SOC Corporativo"
echo "============================================"
echo ""

echo "--- Docker ---"
check "Docker daemon rodando" docker info
check "Wazuh manager no ar" docker exec wazuh-manager test -f /var/ossec/bin/wazuh-control
check "Wazuh indexer respondendo" curl -sk https://localhost:9200
check "Wazuh dashboard respondendo" curl -sk https://localhost:443
check "DVWA respondendo" curl -sf http://localhost:8080 -o /dev/null

echo ""
echo "--- Rede ---"
check "Rede target-net existe" docker network inspect target-net
check "DVWA na target-net" docker inspect dvwa --format '{{json .NetworkSettings.Networks}}' | grep -q target-net

echo ""
echo "--- Dados LGPD ---"
check "Diretorio /data/clientes existe" test -d /data/clientes
check "Arquivos de clientes existem" sh -c "ls /data/clientes/*.txt 2>/dev/null | wc -l | grep -q 100"
check "Dados no MySQL do DVWA" docker exec dvwa mysql -u root -pp@ssw0rd -e "SELECT COUNT(*) FROM clientes.pessoas;" 2>/dev/null | grep -q 5

echo ""
echo "--- Agente Wazuh ---"
warn "Agente Wazuh instalado" test -f /var/ossec/bin/wazuh-agent
check "Agente conectado ao manager" docker exec wazuh-manager /var/ossec/bin/agent_control -l 2>/dev/null | grep -q Active

echo ""
echo "--- Regras de Compliance ---"
check "Regras copiadas para o manager" docker exec wazuh-manager test -f /var/ossec/etc/rules/local_rules.xml

echo ""
echo "--- Backup ---"
check "Repositorio Restic existe" test -d /backup-repo
check "Script de backup existe" test -f /usr/local/bin/backup-clientes-local.sh
check "Script de restore existe" test -f /usr/local/bin/restore-clientes-local.sh

echo ""
echo "--- Journal Bridge ---"
warn "Servico soc-journal-bridge ativo" systemctl is-active --quiet soc-journal-bridge 2>/dev/null

echo ""
echo "--- Kali VM ---"
warn "VM kali-attacker existe" vboxmanage list vms 2>/dev/null | grep -q kali-attacker
warn "VM kali-attacker ligada" vboxmanage showvminfo kali-attacker 2>/dev/null | grep -q "running"

echo ""
echo "============================================"
if [ "$FAIL" -eq 0 ]; then
    echo -e "  ${GREEN}RESULTADO: Tudo OK${NC}"
else
    echo -e "  ${RED}RESULTADO: ${FAIL} componente(s) com falha${NC}"
    echo "  Corrija os itens marcados com ✘ e execute novamente."
fi
echo "============================================"
exit "$FAIL"
