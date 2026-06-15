#!/bin/bash
# ============================================================
# SETUP AUTOMATIZADO — SOC Corporativo (Ubuntu/Debian)
# ============================================================
# Executar no HOST (Ubuntu 22.04+ ou Debian 12+) como usuário
# com permissão sudo.
#
# Uso: bash setup-ubuntu.sh
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/lib/common.sh"

log()  { echo -e "${GREEN}[SETUP]${NC} $1"; }

# ============================================================
# VARIAVEIS DE CONFIGURACAO (sobrescreva com export)
# ============================================================
RESTIC_PASSWORD="${RESTIC_PASSWORD:-backup2024}"
WAZUH_PASSWORD="${WAZUH_PASSWORD:-SecretPassword}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-p@ssw0rd}"
KALI_SSH_KEY_DIR="${KALI_SSH_KEY_DIR:-/tmp/soc-ssh-key}"

# ============================================================
# VERIFICAR PRÉ-REQUISITOS
# ============================================================
log "Verificando pré-requisitos..."

# Verificar se é Ubuntu/Debian
if ! grep -qiE "ubuntu|debian" /etc/os-release 2>/dev/null; then
  warn "Este script foi feito para Ubuntu/Debian. Detectado: $(grep ^ID= /etc/os-release 2>/dev/null | cut -d= -f2)"
  echo -n "Deseja continuar mesmo assim? (s/N): "; read -r confirm
  [ "$confirm" != "s" ] && [ "$confirm" != "S" ] && exit 1
fi

command -v docker &>/dev/null || err "Docker não encontrado. Instale com: sudo apt install docker.io docker-compose-v2"
docker compose version &>/dev/null || warn "Docker Compose plugin não encontrado. Instale com: sudo apt install docker-compose-v2"
command -v vboxmanage &>/dev/null || warn "VirtualBox não encontrado. Instale com: sudo apt install virtualbox"
command -v restic &>/dev/null && log "Restic OK" || warn "Restic não encontrado. sudo apt install restic"
command -v git &>/dev/null || err "Git não encontrado. sudo apt install git"

# Verificar se vboxnet0 existe
vboxmanage list hostonlyifs 2>/dev/null | grep -q "vboxnet0" || {
  warn "Rede vboxnet0 não existe. Criando..."
  vboxmanage hostonlyif create
  vboxmanage hostonlyif ipconfig vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0
}

# ============================================================
# PARTE 1: INSTALAR WAZUH DOCKER
# ============================================================
log "Instalando Wazuh via Docker..."

WAZUH_DIR="$(dirname "$PROJECT_DIR")/wazuh-docker"
if [ ! -d "$WAZUH_DIR" ]; then
  log "Clonando wazuh-docker (branch 4.9.0)..."
  git clone https://github.com/wazuh/wazuh-docker.git -b 4.9.0 "$WAZUH_DIR"
fi

cd "$WAZUH_DIR/single-node"

log "Ajustando memória do OpenSearch para 1g..."
if grep -q "ES_JAVA_OPTS=-Xms1g" docker-compose.yml 2>/dev/null; then
  log "Memória já ajustada"
else
  sed -i 's/ES_JAVA_OPTS=-Xms4g -Xmx4g/ES_JAVA_OPTS=-Xms1g -Xmx1g/g' docker-compose.yml 2>/dev/null || true
  log "Memória ajustada para 1g"
fi

if [ ! -f config/wazuh_indexer_ssl_certs/admin.pem ]; then
  log "Gerando certificados SSL..."
  docker compose -f generate-indexer-certs.yml run --rm generator
fi

log "Subindo Wazuh (pode levar 2-3 minutos)..."
docker compose up -d

log "Aguardando Wazuh ficar pronto..."
sleep 15
docker compose ps

log "Wazuh Dashboard em: https://localhost:443 (admin/${WAZUH_PASSWORD})"

# ============================================================
# PARTE 3: KALI VM
# ============================================================
log "Verificando Kali VM..."
if vboxmanage list vms 2>/dev/null | grep -q "kali-attacker"; then
  log "Kali VM encontrada"
  vboxmanage modifyvm kali-attacker --nic1 hostonly --hostonlyadapter1 vboxnet0 2>/dev/null || true
  log "Rede do Kali ajustada para Host-Only"
else
  warn "Kali VM não encontrada. Crie manualmente seguindo kali-attacker.md"
fi

# ============================================================
# PARTE 4: SERVICOS ALVO NO HOST
# ============================================================
log "Configurando serviços alvo no host..."

docker network inspect target-net &>/dev/null || {
  docker network create --subnet=172.20.0.0/16 target-net
  log "Rede target-net criada"
}

if docker inspect dvwa &>/dev/null; then
  warn "Container dvwa já existe. Removendo..."
  docker rm -f dvwa
fi

log "Subindo DVWA na porta 8080..."
docker run -d \
  --name dvwa \
  --network target-net \
  -p 8080:80 \
  --restart unless-stopped \
  vulnerables/web-dvwa

sleep 3
if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 2>/dev/null | grep -q "200\|302"; then
  log "DVWA OK em http://localhost:8080"
else
  warn "DVWA pode ainda estar iniciando. Verifique: docker logs dvwa"
fi

# ============================================================
# PARTE 5: DADOS LGPD
# ============================================================
log "Criando dados LGPD..."

run_root mkdir -p /data/clientes
run_root chmod 777 /data/clientes

if [ -z "$(ls -A /data/clientes/ 2>/dev/null)" ]; then
  for i in $(seq 1 100); do
    cat > /data/clientes/cliente_$i.txt << EOF
Cliente $i
Nome: Cliente Ficticio $i
CPF: 000.000.$(printf '%03d' $i)-$(printf '%02d' $((i % 99)))
Email: cliente${i}@empresa.com.br
Telefone: ($(printf '%02d' $((i % 21 + 11)))) 9$(printf '%04d' $i)-$(printf '%04d' $((i * 5 % 9999)))
Data de Cadastro: 2024-$(printf '%02d' $((i % 12 + 1)))-$(printf '%02d' $((i % 28 + 1)))
Status: ATIVO
EOF
  done
  log "100 arquivos de clientes criados em /data/clientes/"
else
  log "Dados já existem em /data/clientes/"
fi

log "Inserindo dados LGPD no MySQL..."
docker exec -i dvwa mysql -u root -p"${MYSQL_PASSWORD}" << 'EOF' 2>/dev/null || true
CREATE DATABASE IF NOT EXISTS clientes;
USE clientes;
CREATE TABLE IF NOT EXISTS pessoas (
  id INT AUTO_INCREMENT PRIMARY KEY,
  nome VARCHAR(100),
  cpf VARCHAR(14),
  email VARCHAR(100),
  telefone VARCHAR(20),
  endereco TEXT,
  data_nascimento DATE
);
INSERT INTO pessoas (nome, cpf, email, telefone, endereco, data_nascimento) VALUES
  ('João Silva', '123.456.789-00', 'joao.silva@email.com', '(11) 99999-8888', 'Rua das Flores, 123, SP', '1990-05-15'),
  ('Maria Santos', '987.654.321-00', 'maria.santos@email.com', '(21) 98888-7777', 'Av. Atlântica, 456, RJ', '1985-10-20'),
  ('Carlos Pereira', '456.789.123-00', 'carlos.pereira@email.com', '(31) 97777-6666', 'Rua MG, 789, BH', '1978-03-08'),
  ('Ana Oliveira', '111.222.333-44', 'ana.oliveira@email.com', '(41) 96666-5555', 'Rua XV, 321, CTBA', '1995-07-12'),
  ('Roberto Costa', '555.666.777-88', 'roberto.costa@email.com', '(51) 95555-4444', 'Rua Andradas, 654, POA', '1982-11-25');
EOF
log "5 registros LGPD inseridos no MySQL"

# ============================================================
# PARTE 6: REGRAS DE COMPLIANCE
# ============================================================
log "Copiando regras de compliance para o Wazuh..."

if [ -f "$PROJECT_DIR/03-configuracao/local_rules.xml" ]; then
  docker cp "$PROJECT_DIR/03-configuracao/local_rules.xml" \
    wazuh-manager:/var/ossec/etc/rules/local_rules.xml 2>/dev/null || true
  docker exec wazuh-manager chown ossec:ossec /var/ossec/etc/rules/local_rules.xml 2>/dev/null || true
  docker exec wazuh-manager chmod 640 /var/ossec/etc/rules/local_rules.xml 2>/dev/null || true
  log "Regras copiadas. Reinicie o manager: docker exec wazuh-manager /var/ossec/bin/ossec-control restart"
else
  warn "local_rules.xml não encontrado em $PROJECT_DIR/03-configuracao/"
fi

# ============================================================
# PARTE 7: BACKUP LOCAL
# ============================================================
log "Configurando backup local..."

# Restic
run_root apt-get install -y restic 2>/dev/null || warn "Instale restic manualmente: sudo apt install restic"

run_root mkdir -p /backup-repo
run_root chmod 777 /backup-repo

if [ -z "$(ls -A /backup-repo/ 2>/dev/null)" ]; then
  restic init --repo /backup-repo <<< "${RESTIC_PASSWORD}"
  log "Repositório Restic inicializado"
else
  log "Repositório Restic já existe"
fi

run_root mkdir -p /etc/restic
echo "${RESTIC_PASSWORD}" | run_root tee /etc/restic/passwd > /dev/null
run_root chmod 600 /etc/restic/passwd

# Scripts de backup/restore
cat > /tmp/backup-local.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail
DATA_DIR="/data/clientes"
REPO="/backup-repo"
PASSFILE="/etc/restic/passwd"
LOG_FILE="/var/log/backup.log"

syslog() {
  local msg="$1"
  local now; now=$(date '+%b %e %H:%M:%S')
  echo "${now} $(hostname) backup[$$]: ${msg}" >> "$LOG_FILE"
  logger "${msg}"
}

syslog "INICIANDO BACKUP"
RESTIC_PASSWORD=$(cat "$PASSFILE") restic backup \
  --repo "$REPO" --verbose --tag clientes \
  --tag "$(date +%Y%m%d_%H%M)" "$DATA_DIR" >> "$LOG_FILE" 2>&1

if [ $? -eq 0 ]; then
  syslog "BACKUP_EXECUTADO: RPO checkpoint"
else
  syslog "BACKUP_FALHOU"
fi
SCRIPT

run_root mv /tmp/backup-local.sh /usr/local/bin/backup-clientes-local.sh
run_root chmod +x /usr/local/bin/backup-clientes-local.sh

cat > /tmp/restore-local.sh << 'SCRIPT'
#!/bin/bash
set -euo pipefail
REPO="/backup-repo"
PASSFILE="/etc/restic/passwd"
DATA_DIR="/data/clientes"
TARGET="/tmp/restore-clientes"
LOG_FILE="/var/log/restore.log"
START_TIME=$(date +%s)

syslog() {
  local msg="$1"
  local now; now=$(date '+%b %e %H:%M:%S')
  echo "${now} $(hostname) restore[$$]: ${msg}" >> "$LOG_FILE"
  logger "${msg}"
}

syslog "INICIANDO RESTORE"
RESTIC_PASSWORD=$(cat "$PASSFILE") restic restore latest \
  --repo "$REPO" --target "$TARGET" >> "$LOG_FILE" 2>&1

rsync -a --delete "$TARGET/data/clientes/" "$DATA_DIR/"
rm -rf "$TARGET"

RTO=$(( ($(date +%s) - START_TIME) / 60 ))
RTO_S=$(( ($(date +%s) - START_TIME) % 60 ))
COUNT=$(ls "$DATA_DIR/"*.txt 2>/dev/null | wc -l)

syslog "RESTORE_EXECUTADO: RTO ${RTO}min ${RTO_S}s | ${COUNT} arquivos"
echo "RTO: ${RTO}min ${RTO_S}s | ${COUNT} arquivos restaurados em ${DATA_DIR}"
SCRIPT

run_root mv /tmp/restore-local.sh /usr/local/bin/restore-clientes-local.sh
run_root chmod +x /usr/local/bin/restore-clientes-local.sh

# Cron (a cada hora)
(crontab -l 2>/dev/null | grep -v backup-clientes; echo "0 * * * * /usr/local/bin/backup-clientes-local.sh") | crontab -
log "Cron configurado: backup a cada hora"

# Log rotation (opcional)
LOGROTATE_SRC="$PROJECT_DIR/03-configuracao/logrotate-soc.conf"
if [ -f "$LOGROTATE_SRC" ] && [ -d /etc/logrotate.d ]; then
  run_root cp "$LOGROTATE_SRC" /etc/logrotate.d/soc-corporativo 2>/dev/null || true
  log "Log rotation configurado em /etc/logrotate.d/soc-corporativo"
fi

# ============================================================
# PARTE 8: CHAVE SSH PARA KALI
# ============================================================
log "Configurando chave SSH para acesso Kali -> Host..."
SSH_KEY_DIR="${KALI_SSH_KEY_DIR}"

if [ ! -f "${SSH_KEY_DIR}" ]; then
  mkdir -p "$(dirname "${SSH_KEY_DIR}")"
  ssh-keygen -t ed25519 -f "${SSH_KEY_DIR}" -N "" -q
  log "Chave SSH gerada em ${SSH_KEY_DIR}"
else
  log "Chave SSH ja existe em ${SSH_KEY_DIR}"
fi

AUTH_KEYS="${HOME}/.ssh/authorized_keys"
mkdir -p "${HOME}/.ssh"
cat "${SSH_KEY_DIR}.pub" >> "${AUTH_KEYS}"
chmod 600 "${AUTH_KEYS}" 2>/dev/null || true
log "Chave publica adicionada a ${AUTH_KEYS}"

log "Para copiar a chave para o Kali, execute quando a VM estiver ligada:"
log "  scp -P 22 ${SSH_KEY_DIR} kali@192.168.56.20:/tmp/id_ed25519"
log "  scp ${PROJECT_DIR}/04-operacao/ataques-opcao5.sh kali@192.168.56.20:/home/kali/ataques.sh"
log "  ssh kali@192.168.56.20 'chmod 600 /tmp/id_ed25519 && chmod +x /home/kali/ataques.sh'"
echo ""

# ============================================================
# RESUMO FINAL
# ============================================================
echo ""
log "============================================"
log "  SETUP CONCLUIDO"
log "============================================"
echo ""
echo "  Wazuh Dashboard:  https://localhost:443"
echo "  Usuario/Senha:    admin / ${WAZUH_PASSWORD}"
echo ""
echo "  DVWA:             http://localhost:8080/DVWA"
echo "  Login:            admin / password"
echo ""
echo "  Kali VM:          192.168.56.20"
echo "  Host (alvo):      192.168.56.1"
echo ""
echo "  Backup:           /usr/local/bin/backup-clientes-local.sh"
echo "  Restore:          /usr/local/bin/restore-clientes-local.sh"
echo "  Dados:            /data/clientes/"
echo "  Repositorio:      /backup-repo/"
echo "  Senha Restic:     ${RESTIC_PASSWORD} (/etc/restic/passwd)"
echo ""
echo "  PROXIMOS PASSOS:"
echo "  1. Acessar DVWA em http://localhost:8080/DVWA"
echo "     - Clique em 'Create/Reset Database'"
echo "     - Login: admin / password"
echo "     - DVWA Security > low"
echo "  2. Iniciar Kali: vboxmanage startvm kali-attacker"
echo "  3. Regras de compliance ja copiadas"
echo "  4. Reiniciar manager: docker exec wazuh-manager /var/ossec/bin/ossec-control restart"
echo "  5. Verificar saude: bash 04-operacao/healthcheck.sh"
echo "  6. Copiar chave SSH e script para o Kali:"
echo "     bash 02-setup/deploy-to-kali.sh"
echo "  7. No Kali, executar: bash /home/kali/ataques.sh"
echo "============================================"
