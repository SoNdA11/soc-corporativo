# Opção 5 — Setup Completo (Wazuh Docker + Kali VM)

## Arquitetura

```
┌──────────────────────────────────────────────────────────────────┐
│                    HOST (Arch Linux)                              │
│                    IP: 192.168.56.1 (vboxnet0)                    │
│                    IP: 192.168.1.244/24 (wlan0 - internet)       │
│                                                                  │
│  CONTAINERS DOCKER:                                              │
│  ┌─────────────────────┐  ┌─────────────────────────────────┐   │
│  │ Wazuh Stack         │  │ Alvos                           │   │
│  │ wazuh-dashboard:443 │  │ dvwa:8080                       │   │
│  │ wazuh-manager:1514  │  │                                  │   │
│  │ wazuh-indexer:9200  │  │                                  │   │
│  └─────────────────────┘  └─────────────────────────────────┘   │
│                                                                  │
│  SERVIÇOS NATIVOS:                                               │
│  ● Wazuh Agent instalado no Arch                                │
│  ● Logs via journald bridge → /var/log/soc-corporativo/         │
│  ● /data/clientes/ — dados LGPD (FIM monitorado)                │
│  ● /backup-repo/ — backup local (Restic)                        │
│  ● Scripts em /usr/local/bin/                                    │
│  ● Regras Wazuh em /var/ossec/etc/rules/local_rules.xml          │
└──────────────────────────┬───────────────────────────────────────┘
                           │ vboxnet0 (192.168.56.0/24)
                           ▼
              ┌────────────────────────┐
              │ Kali Linux (VM)        │
              │ 192.168.56.20          │
              │ 1.5 GB RAM             │
              │ Nmap, Hydra, Sqlmap    │
              └────────────────────────┘
```

---

## Pré-requisitos

### Hardware mínimo

| Recurso      | Mínimo  | Recomendado |
|-------------|---------|-------------|
| RAM         | 12 GB   | 16 GB       |
| CPU         | 4 cores | 8 cores     |
| Disco livre | 30 GB   | 60 GB       |
| Internet    | Sim     | Sim         |

> O Wazuh Docker usa ~2 GB RAM (indexer com heap 1g). Kali VM com 1.5 GB. Host Arch com agente + containers leves.

### Software necessário

- **VirtualBox** 7.x com Extension Pack
- **Docker** + Docker Compose plugin
- **Git**
- **Kali Linux ISO** (para criar a VM, se não existir)

Verificar instalações:

```bash
vboxmanage --version
docker --version && docker compose version
git --version
```

---

## Parte 1: Rede Host-Only

### 1.1 Verificar se vboxnet0 existe

```bash
vboxmanage list hostonlyifs
```

### 1.2 Criar se necessário

```bash
vboxmanage hostonlyif create
vboxmanage hostonlyif ipconfig vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0
```

### 1.3 Configurar DHCP (desligado, IP fixo)

```bash
vboxmanage dhcpserver remove --netname HostInterfaceNetworking-vboxnet0 2>/dev/null
vboxmanage dhcpserver add --netname HostInterfaceNetworking-vboxnet0 \
  --ip 192.168.56.100 --netmask 255.255.255.0 \
  --lowerip 192.168.56.10 --upperip 192.168.56.99 --enable
```

### 1.4 Subir interface no host

```bash
sudo ip link set vboxnet0 up
```

---

## Parte 2: Wazuh Docker

### 2.1 Clonar repositório

```bash
cd ~/Code/new-project
git clone https://github.com/wazuh/wazuh-docker.git -b 4.9.0
cd wazuh-docker/single-node
```

### 2.2 Ajustar memória do indexer

Edite `docker-compose.yml` e altere as variáveis `ES_JAVA_OPTS` de `-Xms4g -Xmx4g` para `-Xms1g -Xmx1g` nas seções `opensearch` e `wazuh-indexer-0`:

```yaml
opensearch:
  environment:
    - ES_JAVA_OPTS=-Xms1g -Xmx1g
```

```yaml
wazuh-indexer-0:
  environment:
    - ES_JAVA_OPTS=-Xms1g -Xmx1g
```

### 2.3 Ajustar versão das imagens (opcional)

Se desejar usar imagens 4.14.5 em vez das 4.9.0 padrão, edite o arquivo `.env` ou o `docker-compose.yml` alterando os tags das imagens.

### 2.4 Gerar certificados e iniciar

```bash
# Gerar certificados SSL (apenas na primeira vez)
docker compose -f generate-indexer-certs.yml run --rm generator

# Subir serviços
docker compose up -d

# Aguardar ~2-3 minutos e verificar
docker compose ps
```

### 2.5 Acessar dashboard

```bash
curl -k https://localhost:443
```

**URL:** `https://localhost:443`
**Usuário:** `admin`
**Senha:** `SecretPassword`

> Se a senha não funcionar, extraia dos logs:
> ```bash
> docker compose logs wazuh-dashboard | grep -i password
> ```

---

## Parte 3: Kali VM

### 3.1 Criar a VM (se não existir)

```bash
vboxmanage createvm --name kali-attacker --basefolder ~/VirtualBox\ VMs/ --register
vboxmanage modifyvm kali-attacker --memory 1536 --cpus 2 --nic1 hostonly --hostonlyadapter1 vboxnet0
vboxmanage createhd --filename ~/VirtualBox\ VMs/kali-attacker/kali-disk.vdi --size 51200
vboxmanage storagectl kali-attacker --name "SATA Controller" --add sata --controller IntelAhci
vboxmanage storageattach kali-attacker --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium ~/VirtualBox\ VMs/kali-attacker/kali-disk.vdi
vboxmanage storagectl kali-attacker --name "IDE Controller" --add ide
```

Para anexar a ISO e instalar manualmente:

```bash
vboxmanage storageattach kali-attacker --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium /caminho/kali-linux-2024.1-installer-amd64.iso
vboxmanage startvm kali-attacker
```

### 3.2 Configurar IP fixo no Kali

Após a instalação, dentro da VM:

```bash
sudo ip addr add 192.168.56.20/24 dev eth0
sudo ip link set eth0 up
sudo ip route add default via 192.168.56.1
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
```

Para persistência, edite `/etc/network/interfaces`:

```
auto eth0
iface eth0 inet static
    address 192.168.56.20
    netmask 255.255.255.0
    gateway 192.168.56.1
```

### 3.3 Verificar VM existente

```bash
vboxmanage showvminfo kali-attacker | grep -E "Memory|CPU|NIC"
```

### 3.4 Ligar a VM

```bash
vboxmanage startvm kali-attacker
```

---

## Parte 4: Serviços Alvo

### 4.1 Criar rede Docker isolada

```bash
docker network create --subnet=172.20.0.0/16 target-net
```

### 4.2 Subir DVWA (porta 8080)

```bash
docker run -d \
  --name dvwa \
  --network target-net \
  -p 8080:80 \
  --restart unless-stopped \
  vulnerables/web-dvwa

# Verificar
docker logs dvwa --tail 5
curl -s http://localhost:8080 | head -5
```

### 4.3 Configurar DVWA

Acesse `http://192.168.56.1:8080` (do Kali) ou `http://localhost:8080` (do host):

1. Clique em **"Create/Reset Database"**
2. Login: `admin` / `password`
3. **DVWA Security** → altere para **low**

### 4.4 Criar diretório de dados LGPD

```bash
sudo mkdir -p /data/clientes
sudo chmod 777 /data/clientes

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

echo "Criados $(ls /data/clientes/*.txt | wc -l) arquivos"
```

### 4.5 Inserir dados LGPD no MySQL do DVWA

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
  ('João Silva', '123.456.789-00', 'joao.silva@email.com', '(11) 99999-8888', 'Rua das Flores, 123, São Paulo - SP', '1990-05-15'),
  ('Maria Santos', '987.654.321-00', 'maria.santos@email.com', '(21) 98888-7777', 'Av. Atlântica, 456, Rio de Janeiro - RJ', '1985-10-20'),
  ('Carlos Pereira', '456.789.123-00', 'carlos.pereira@email.com', '(31) 97777-6666', 'Rua Minas Gerais, 789, Belo Horizonte - MG', '1978-03-08'),
  ('Ana Oliveira', '111.222.333-44', 'ana.oliveira@email.com', '(41) 96666-5555', 'Rua XV de Novembro, 321, Curitiba - PR', '1995-07-12'),
  ('Roberto Costa', '555.666.777-88', 'roberto.costa@email.com', '(51) 95555-4444', 'Rua dos Andradas, 654, Porto Alegre - RS', '1982-11-25');
EOF

# Verificar
docker exec -i dvwa mysql -u root -pp@ssw0rd -e "SELECT * FROM clientes.pessoas;"
```

---

## Parte 5: Agente Wazuh no Host

Nesta configuração, o agente Wazuh é instalado diretamente no Arch Linux (**não** em container) e os logs do sistema são enviados via **journald bridge**.

### 5.1 Instalar agente Wazuh

```bash
curl -sO https://packages.wazuh.com/4.x/wazuh-agent/linux/wazuh-agent-4.9.0-1-x86_64.pkg.tar.zst
sudo pacman -U wazuh-agent-4.9.0-1-x86_64.pkg.tar.zst
```

### 5.2 Configurar agente para apontar para o manager

Edite `/var/ossec/etc/ossec.conf` e altere o endereço do manager:

```xml
<client>
  <server>
    <address>172.17.0.1</address>
    <port>1514</port>
    <protocol>tcp</protocol>
  </server>
</client>
```

> O IP `172.17.0.1` é o gateway da bridge docker padrão, que redireciona para o host e, consequentemente, para o container do wazuh-manager mapeado na porta 1514.

### 5.3 Configurar monitoramento FIM

No mesmo `ossec.conf`, dentro de `<ossec_config>`, adicione:

```xml
<syscheck>
  <directories check_all="yes" realtime="yes">/etc/passwd</directories>
  <directories check_all="yes" realtime="yes">/etc/shadow</directories>
  <directories check_all="yes" realtime="yes">/etc/sudoers</directories>
  <directories check_all="yes" realtime="yes">/etc/crontab</directories>
  <directories check_all="yes" realtime="yes">/data/clientes</directories>
  <directories check_all="yes" realtime="yes">/home</directories>
</syscheck>
```

### 5.4 Configurar entrada de logs via journald bridge

O agente Wazuh lê arquivos de log. Para enviar logs do systemd (journald), use o **journald bridge** que grava logs em um arquivo monitorado pelo agente.

Crie o diretório de logs:

```bash
sudo mkdir -p /var/log/soc-corporativo
```

Crie o serviço systemd para o bridge:

```bash
sudo tee /etc/systemd/system/soc-journal-bridge.service << 'EOF'
[Unit]
Description=SOC Journald Bridge - encaminha logs do systemd para arquivo monitorado pelo Wazuh
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

sudo systemctl daemon-reload
sudo systemctl enable --now soc-journal-bridge
```

Adicione o arquivo de log no `ossec.conf` dentro de `<ossec_config>`:

```xml
<localfile>
  <log_format>syslog</log_format>
  <location>/var/log/soc-corporativo/soc-journal.log</location>
</localfile>
```

### 5.5 Iniciar agente

```bash
sudo systemctl enable --now wazuh-agent
sudo systemctl status wazuh-agent
```

### 5.6 Configurar log rotation (opcional)

Para evitar que o arquivo `/var/log/soc-corporativo/soc-journal.log` cresça infinitamente:

```bash
sudo cp ~/Code/new-project/soc-corporativo/03-configuração/logrotate-soc.conf /etc/logrotate.d/soc-corporativo
```

Isso irá rotacionar os logs diariamente, mantendo 7 dias de histórico com compressão.

### 5.7 Aceitar agente no Wazuh Manager

```bash
docker exec -it wazuh-manager /var/ossec/bin/agent_control -l
# Pegar o ID do agente listado e aceitar:
docker exec -it wazuh-manager /var/ossec/bin/agent_control -a -i <ID>
```

---

## Parte 6: Regras de Compliance

### 6.1 Copiar regras customizadas para o container

```bash
docker cp ~/Code/new-project/soc-corporativo/03-configuração/local_rules.xml \
  wazuh-manager:/var/ossec/etc/rules/local_rules.xml

docker exec wazuh-manager chown ossec:ossec /var/ossec/etc/rules/local_rules.xml
docker exec wazuh-manager chmod 640 /var/ossec/etc/rules/local_rules.xml
```

### 6.2 Reiniciar manager para carregar regras

```bash
docker exec wazuh-manager /var/ossec/bin/ossec-control restart
```

As regras incluem classificações NIST CSF, ISO 27001 e LGPD para eventos como:
- Alterações em `/data/clientes/` (FIM)
- Acesso SSH
- Logs de serviço
- Eventos de segurança do sistema

---

## Parte 7: Backup Local (Restic)

> Os scripts de backup e restore são **gerados pelo `setup-opcao5.sh`** e instalados em `/usr/local/bin/`. Esta seção documenta o que fazer manualmente, caso necessário.

### 7.1 Instalar Restic

```bash
sudo pacman -S restic
```

### 7.2 Inicializar repositório local

```bash
sudo mkdir -p /backup-repo
sudo chmod 777 /backup-repo
restic init --repo /backup-repo <<< "backup2024"
```

### 7.3 Scripts gerados pelo setup

O script `setup-opcao5.sh` instala automaticamente:

| Script | Caminho | Função |
|--------|---------|--------|
| `backup-clientes-local.sh` | `/usr/local/bin/backup-clientes-local.sh` | Backup de `/data/clientes` para `/backup-repo` |
| `restore-clientes-local.sh` | `/usr/local/bin/restore-clientes-local.sh` | Restaura último snapshot |

Se precisar instalá-los manualmente, gere os scripts com o conteúdo abaixo:

**`/usr/local/bin/backup-clientes-local.sh`:**
```bash
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
```

**`/usr/local/bin/restore-clientes-local.sh`:**
```bash
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
```

```bash
sudo chmod +x /usr/local/bin/backup-clientes-local.sh /usr/local/bin/restore-clientes-local.sh
```

### 7.4 Agendar backup automático (cron)

```bash
(crontab -l 2>/dev/null; echo "0 * * * * /usr/local/bin/backup-clientes-local.sh") | crontab -
crontab -l
```

### 7.5 Testar backup manual

```bash
sudo /usr/local/bin/backup-clientes-local.sh
tail -5 /var/log/backup.log
```

---

## Parte 8: Testes

### 8.1 Testar conectividade do Kali ao host

```bash
# No Kali:
ping -c 3 192.168.56.1
curl -s http://192.168.56.1:8080 | head -5
nmap -sS -p 22,80,443,8080,3306 192.168.56.1
```

### 8.2 Testar acesso ao Wazuh Dashboard

```bash
# No Kali:
curl -k https://192.168.56.1:443 | head -5
```

### 8.3 Testar agente Wazuh conectado

```bash
# No host:
docker exec wazuh-manager /var/ossec/bin/agent_control -l
```

Deverá mostrar o agente do Arch com status `Active`.

### 8.4 Verificar saúde do ambiente

```bash
bash ~/Code/new-project/soc-corporativo/04-operação/healthcheck.sh
```

### 8.5 Executar script de ataques (opcional)

```bash
# No Kali:
bash /home/paulo/Code/new-project/soc-corporativo/04-operação/ataques-opcao5.sh
```

---

## Checklist Final

- [ ] Wazuh Docker rodando (`docker compose ps` — todos "Up")
- [ ] Dashboard acessível em `https://localhost:443`
- [ ] Kali VM ligada com IP `192.168.56.20`
- [ ] DVWA acessível em `http://localhost:8080` e `http://192.168.56.1:8080`
- [ ] Dados LGPD em `/data/clientes/` (100 arquivos)
- [ ] Dados LGPD no MySQL do DVWA (5 registros)
- [ ] Wazuh Agent conectado ao manager (status `Active`)
- [ ] Journald bridge rodando (`soc-journal-bridge.service`)
- [ ] Regras de compliance carregadas
- [ ] Backup funcionando (`/usr/local/bin/backup-clientes-local.sh`)
- [ ] Restore funcionando (`/usr/local/bin/restore-clientes-local.sh`)
- [ ] Kali consegue pingar `192.168.56.1`
- [ ] Cron de backup a cada hora configurado
- [ ] Healthcheck passou (`bash 04-operação/healthcheck.sh`)
- [ ] Log rotation configurado (opcional: `logrotate-soc.conf`)
