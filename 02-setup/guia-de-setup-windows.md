# Windows — Guia de Setup (WSL2 + Docker Desktop)

> **Aviso:** O projeto foi originalmente desenvolvido e testado em Linux (Arch Linux e Ubuntu).
> No Windows e possível executar a maior parte do ambiente usando **WSL2** e **Docker Desktop**,
> mas alguns recursos (journal-bridge nativo, systemd do host, FIM direto) tem limitações.

---

## Arquitetura no Windows

```
+-------------------------------------------------------------------+
|                    WINDOWS (Host)                                  |
|  +-------------------------------------------------------------+  |
|  | WSL2 (Ubuntu 22.04)                                         |  |
|  |  - Wazuh Agent (instalado dentro do WSL)                    |  |
|  |  - /data/clientes/ -- dados LGPD                            |  |
|  |  - /backup-repo/ -- backup Restic                           |  |
|  |  - Scripts de backup/restore                                |  |
|  +-------------------------------------------------------------+  |
|                                                                   |
|  CONTAINERS DOCKER (Docker Desktop):                              |
|  +-----------------------+  +----------------------------------+  |
|  | Wazuh Stack           |  | DVWA                            |  |
|  | wazuh-dashboard:443   |  | :8080                           |  |
|  | wazuh-manager:1514    |  |                                  |  |
|  | wazuh-indexer:9200    |  |                                  |  |
|  +-----------------------+  +----------------------------------+  |
|                                                                   |
|  KALI VM (VirtualBox para Windows):                               |
|  +-------------------------------------------------------------+  |
|  | Kali Linux                                                   |  |
|  | 192.168.56.20                                                |  |
|  | Nmap, Hydra, Curl, SSH                                       |  |
|  +-------------------------------------------------------------+  |
+----------------------------------+-------------------------------+
                                   | vboxnet0 (192.168.56.0/24)
                                   v
              +---------------------------------------------+
              | Kali Linux (VM - VirtualBox)                 |
              | 192.168.56.20                               |
              | Nmap, Hydra, Curl, SSH                       |
              +---------------------------------------------+
```

---

## Pré-requisitos

| Recurso      | Mínimo  | Recomendado |
|-------------|---------|-------------|
| RAM         | 16 GB   | 32 GB       |
| CPU         | 4 cores | 8 cores     |
| Disco livre | 60 GB   | 100 GB SSD  |
| Windows     | 10/11   | 11          |

### Software necessário

- **Docker Desktop** para Windows (com integração WSL2)
- **WSL2** com Ubuntu 22.04
- **VirtualBox** 7.x para Windows com Extension Pack
- **Git** para Windows (ou usar git no WSL)
- **Kali Linux ISO**

---

## Parte 1: Instalar Dependências

### 1.1 Instalar WSL2 com Ubuntu

Abra o **PowerShell como Administrador**:

```powershell
wsl --install -d Ubuntu-22.04
wsl --set-default-version 2
```

Após a instalação, inicie o WSL:

```powershell
wsl -d Ubuntu-22.04
```

Dentro do WSL, atualize:

```bash
sudo apt update && sudo apt upgrade -y
```

### 1.2 Instalar Docker Desktop

1. Baixe e instale [Docker Desktop para Windows](https://www.docker.com/products/docker-desktop/)
2. Nas configurações do Docker Desktop, va em **Settings > Resources > WSL Integration**
3. Ative a integração com **Ubuntu-22.04**
4. Clique em **Apply & Restart**

### 1.3 Instalar VirtualBox

1. Baixe e instale [VirtualBox para Windows](https://www.virtualbox.org/)
2. Baixe e instale o **Extension Pack**
3. Configure a rede Host-Only:

```powershell
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" hostonlyif create
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" hostonlyif ipconfig vboxnet0 --ip 192.168.56.1 --netmask 255.255.255.0
```

> **Nota:** No Windows, a interface de rede criada e `vboxnet0` (ou similar como `VirtualBox Host-Only Ethernet Adapter`).

---

## Parte 2: Configurar WSL2

### 2.1 Instalar dependências dentro do WSL

```bash
# Dentro do WSL (Ubuntu)
sudo apt install -y docker.io docker-compose-v2 git restic curl
```

### 2.2 Verificar Docker

Dentro do WSL, confirme que o Docker está acessível:

```bash
docker --version
docker compose version
```

Se o Docker não for encontrado, configure o PATH:

```bash
echo 'export PATH="$PATH:/mnt/c/Program Files/Docker/Docker/resources/bin"' >> ~/.bashrc
source ~/.bashrc
```

### 2.3 Clonar o repositório

```bash
mkdir -p ~/Code
cd ~/Code
git clone https://github.com/wazuh/wazuh-docker.git -b 4.9.0
# O repositório soc-corporativo deve estar em ~/Code/soc-corporativo/
# (copie ou clone conforme necessário)
```

---

## Parte 3: Subir Wazuh Docker

```bash
cd ~/Code/wazuh-docker/single-node

# Ajustar memoria
sed -i 's/ES_JAVA_OPTS=-Xms4g -Xmx4g/ES_JAVA_OPTS=-Xms1g -Xmx1g/g' docker-compose.yml

# Gerar certificados e subir
docker compose -f generate-indexer-certs.yml run --rm generator
docker compose up -d
```

---

## Parte 4: Criar Kali VM (VirtualBox Windows)

### 4.1 Criar VM via PowerShell

```powershell
$vbox = "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
& $vbox createvm --name kali-attacker --register
& $vbox modifyvm kali-attacker --memory 2048 --cpus 2 --nic1 hostonly --hostonlyadapter1 vboxnet0
& $vbox createhd --filename "$env:USERPROFILE\VirtualBox VMs\kali-attacker\kali-disk.vdi" --size 51200
& $vbox storagectl kali-attacker --name "SATA Controller" --add sata --controller IntelAhci
& $vbox storageattach kali-attacker --storagectl "SATA Controller" --port 0 --device 0 --type hdd --medium "$env:USERPROFILE\VirtualBox VMs\kali-attacker\kali-disk.vdi"
```

### 4.2 Anexar ISO e instalar

```powershell
& $vbox storageattach kali-attacker --storagectl "IDE Controller" --port 0 --device 0 --type dvddrive --medium "C:\caminho\kali-linux.iso"
& $vbox startvm kali-attacker
```

Após instalação, configure IP fixo na VM:

```bash
# Dentro do Kali
sudo ip addr add 192.168.56.20/24 dev eth0
sudo ip link set eth0 up
```

---

## Parte 5: Configurar Serviços e Dados

Siga os passos da seção correspondente no [guia Ubuntu](guia-de-setup-ubuntu.md) a partir do **WSL**:

- **Parte 4.1 a 4.5:** Subir DVWA e criar dados LGPD
- **Parte 5:** Instalar agente Wazuh (dentro do WSL)
- **Parte 6:** Copiar regras de compliance
- **Parte 7:** Configurar backup Restic

**Diferenças importantes no WSL:**

1. **Wazuh Agent:** Deve ser instalado dentro do WSL. O endereco do manager e `localhost` (pois o Docker Desktop compartilha a rede com o WSL).
2. **Journal-bridge:** O WSL tem suporte a systemd a partir do Ubuntu 22.04. Habilite com:

   ```bash
   sudo tee /etc/wsl.conf <<< '[boot]' && echo 'systemd=true' | sudo tee -a /etc/wsl.conf
   ```

   Reinicie o WSL com `wsl --shutdown` no PowerShell e inicie novamente.
3. **Diretórios:** Use `/data/clientes/` normalmente dentro do WSL.
4. **VirtualBox:** O VBoxManage do Windows gerencia a VM Kali. Execute os comandos de VBoxManage no **PowerShell**, não no WSL.

---

## Limitações no Windows

| Funcionalidade | Status | Alternativa |
|---|---|---|
| Journal-bridge nativo | Limitado | Systemd no WSL (requer configuração) |
| FIM em tempo real | Ok dentro do WSL | Monitora apenas arquivos dentro do WSL |
| VirtualBox no WSL | Não funciona | Usar VBoxManage do Windows (PowerShell) |
| Script setup-opcao5.sh | Parcial | Rodar no WSL, exceto comandos VBox |
| Backup Restic | Ok | Funciona dentro do WSL |
| Deploy para Kali | Parcial | Copiar chave/script manualmente |

---

## Comandos Úteis (PowerShell)

```powershell
# Iniciar WSL
wsl -d Ubuntu-22.04

# Desligar WSL
wsl --shutdown

# Iniciar Kali VM
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" startvm kali-attacker

# Parar Kali VM
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" controlvm kali-attacker poweroff

# Listar VMs
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" list vms
```

---

## Referências

- [Docker Desktop WSL2 Backend](https://docs.docker.com/desktop/wsl/)
- [WSL Systemd Support](https://devblogs.microsoft.com/commandline/systemd-support-is-now-available-in-wsl/)
- [VirtualBox para Windows](https://www.virtualbox.org/)
