# 03 — Kali Attacker

Configuração da máquina que executará os ataques controlados durante a demonstração.

---

## 3.1 Criar a VM

```bash
VBOX_DIR="$HOME/VirtualBox VMs/soc-corporativo"

vboxmanage createvm \
  --name kali-attacker \
  --ostype Debian_64 \
  --register \
  --basefolder "$VBOX_DIR"

vboxmanage modifyvm kali-attacker \
  --memory 2048 \
  --cpus 2 \
  --ioapic on \
  --boot1 dvd \
  --boot2 disk \
  --audio none \
  --usb off \
  --nic1 nat \
  --nic2 hostonly \
  --hostonlyadapter2 vboxnet0

vboxmanage createmedium disk \
  --filename "$VBOX_DIR/kali-attacker/kali-attacker.vdi" \
  --size 30720 \
  --format VDI

vboxmanage storagectl kali-attacker \
  --name "SATA Controller" \
  --add sata \
  --controller IntelAhci

vboxmanage storageattach kali-attacker \
  --storagectl "SATA Controller" \
  --port 0 \
  --device 0 \
  --type hdd \
  --medium "$VBOX_DIR/kali-attacker/kali-attacker.vdi"

vboxmanage storagectl kali-attacker \
  --name "IDE Controller" \
  --add ide

vboxmanage storageattach kali-attacker \
  --storagectl "IDE Controller" \
  --port 0 \
  --device 0 \
  --type dvddrive \
  --medium ~/isos/kali-linux-2024.4-installer-amd64.iso
```

---

## 3.2 Instalar Kali Linux

1. Inicie a VM e siga:

| Passo | Configuração |
|-------|-------------|
| Idioma | English |
| Location | United States |
| Keyboard | US |
| Hostname | `kali-attacker` |
| Domain | (deixe em branco) |
| Root password | `KaliAttacker2024!` |
| Partitioning | Guided - use entire disk (30 GB) |
| Desktop | ✅ Xfce (leve) ou ✅ GNOME |
| Software | ✅ **Standard system utilities**, deixe demais marcado |

2. Após reiniciar, faça login como root com a senha definida.

---

## 3.3 Configurar Rede

Edite a configuração de rede:

```bash
nano /etc/network/interfaces
```

Adicione:

```bash
# Host-Only (Segunda Placa)
auto enp0s8
iface enp0s8 inet static
    address 192.168.56.20
    netmask 255.255.255.0
```

Reinicie a rede:

```bash
sudo systemctl restart NetworkManager
```

**Verificar:**

```bash
ip a
# eth0 deve mostrar 192.168.56.20

ping 192.168.56.10  # Wazuh Server
ping 8.8.8.8        # Internet (via NAT)
```

---

## 3.4 Atualizar Kali e Ferramentas

```bash
apt update && apt full-upgrade -y
```

**Verificar ferramentas necessárias** (já vêm instaladas, mas confirme):

```bash
which nmap hydra gobuster sqlmap msfconsole nc python3 curl
nmap --version | head -1
hydra -h | head -1
```

Se alguma faltar:

```bash
apt install nmap hydra gobuster sqlmap metasploit-framework netcat-openbsd -y
```

---

## 3.5 (Opcional) Instalar Wazuh Agent no Kali

O Kali pode ser monitorado como agente do Wazuh. Durante a apresentação, isso demonstra que **até o atacante pode ser detectado** se houver agente instalado (embora não seja o foco principal).

```bash
# Adicionar repositório Wazuh
# Baixar a chave para o chaveiro seguro do sistema
curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --dearmor | sudo tee /usr/share/keyrings/wazuh.gpg > /dev/null
# Adicionar o repositório apontando diretamente para a chave específica
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" | sudo tee /etc/apt/sources.list.d/wazuh.list
apt update
apt install wazuh-agent -y

# Configurar agente
nano /var/ossec/etc/ossec.conf
# Substituir <address>MANAGER_IP</address> por <address>192.168.56.10</address>

systemctl enable --now wazuh-agent
```

---

## 3.6 Expandir Wordlists (se precisar de mais palavras)

O Kali já vem com wordlists no `/usr/share/wordlists/`. O `rockyou.txt` precisa ser extraído:

```bash
# Se existir o arquivo comprimido
if [ -f /usr/share/wordlists/rockyou.txt.gz ]; then
    gunzip /usr/share/wordlists/rockyou.txt.gz
fi

# Para brute force mais rápido em demonstração, criar uma wordlist pequena:
cat > /root/mini-wordlist.txt << 'EOF'
admin
root
123456
password
admin123
Administrator
test
guest
user
manager
EOF
```

---

## 3.7 Instalar SSH Client e Testar Acesso aos Alvos

```bash
# Gerar chave SSH para acesso sem senha aos alvos
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""

# Copiar chave para o web-target (será criado na etapa 04)
# (Execute depois do web-target estar pronto)
# ssh-copy-id admin@192.168.56.30
```

---

## 3.8 Teste de Comunicação com Wazuh Server

```bash
# Verificar se a porta 1514 do Wazuh está acessível
nc -zv 192.168.56.10 1514

# Verificar se o dashboard está acessível
curl -k https://192.168.56.10:443
```

---

## 3.9 Checklist de Verificação

- [ ] Kali instalado com interface gráfica
- [ ] IP fixo 192.168.56.20 configurado
- [ ] Comunicação com Wazuh Server (ping 192.168.56.10)
- [ ] Comunicação com Internet (ping 8.8.8.8)
- [ ] Ferramentas instaladas: nmap, hydra, gobuster, sqlmap, metasploit, netcat
- [ ] Wordlist rockyou.txt extraída
- [ ] (Opcional) Wazuh Agent instalado

---

**Próximo:** [04 — Web Target + DVWA](04-web-target.md)
