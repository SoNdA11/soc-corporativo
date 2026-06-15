# Topologia do Ambiente

## Diagrama de Rede

```mermaid
graph TB
    KALI["Kali Linux (VM VirtualBox)<br/>RAM: 2 GB | CPU: 2 cores<br/>IP: 192.168.56.20/24<br/>Nmap / Hydra / Curl / SSH"]

    HOST["Host Físico (ArchLinux)<br/>RAM: 16 GB | CPU: 4+ cores | Disco: 80 GB"]
    MANAGER["wazuh-manager<br/>:1514 Agent / :514 Syslog"]
    INDEXER["wazuh-indexer<br/>:9200 API OpenSearch"]
    DASHBOARD["wazuh-dashboard<br/>:443 HTTPS / :5601"]
    DVWA["DVWA :8080<br/>Rede target-net 172.20.0.0/16<br/>MySQL interno — dados LGPD"]
    AGENT["Wazuh Agent<br/>Monitora o host"]
    CLIENTS["/data/clientes/<br/>100 arquivos dados LGPD"]
    BACKUP_REPO["/backup-repo/<br/>Restic snapshots"]
    SCRIPTS["Scripts de Backup<br/>backup-clientes-local.sh<br/>restore-clientes-local.sh<br/>Cron: RPO = 1h"]
    WAN["enp0s* / wlan0<br/>Internet (DHCP, ex: 192.168.1.x)"]
    LAN["vboxnet0<br/>192.168.56.1/24 (Host-Only)"]

    HOST --- MANAGER
    HOST --- INDEXER
    HOST --- DASHBOARD
    HOST --- DVWA
    HOST --- AGENT
    HOST --- CLIENTS
    HOST --- BACKUP_REPO
    HOST --- SCRIPTS
    HOST --- WAN
    HOST --- LAN

    KALI -->|vboxnet0 192.168.56.0/24| LAN
    MANAGER --> INDEXER --> DASHBOARD
    AGENT -->|TCP :1514| MANAGER
    DVWA -->|logs HTTP| AGENT
    CLIENTS -->|FIM syscheck| AGENT
    BACKUP_REPO -->|logs backup/restore| AGENT
```

## Portas Expostas

| Serviço | Porta | Destino | Descrição |
|---------|-------|---------|-----------|
| Wazuh Dashboard | 443 | Host → Internet | Interface web do Wazuh |
| Wazuh Manager | 1514 | Host → Docker | Comunicação com agentes |
| Wazuh Manager | 514 | Host → Docker | Syslog remoto |
| Wazuh Indexer | 9200 | Host → Docker | API REST do OpenSearch |
| DVWA | 8080 | Host → Docker | Web app vulnerável |
| Kali SSH | 22 | Kali → Host | Acesso remoto para ataques |

## Mapeamento de Dependências

### Wazuh Docker (clonado do upstream)
```
wazuh-docker/
└── single-node/
    ├── docker-compose.yml         ← Modificado (memoria 1g, imagens 4.9.0)
    ├── config/
    │   ├── wazuh_cluster/
    │   │   └── wazuh_manager.conf ← Modificado (syslog remote + custom rules)
    │   └── wazuh_indexer/
    │       └── wazuh.indexer.yml  ← Modificado (caminho dos certificados)
    └── generate-indexer-certs.yml ← Original
```

### Soc Corporativo (neste repositório)
```
soc-corporativo/
├── 00-aprendizado/              → Entender a ferramenta e conceitos
├── 01-arquitetura/              → Diagramas e topologia
├── 02-setup/                    → Scripts e guias de instalação
├── 03-configuração/             → Regras Wazuh e configs do agente
├── 04-operação/                 → Scripts de ataque e healthcheck
├── 05-resultados/               → Relatorios, dashboards e prints
└── 06-apresentacao/             → Slides e roteiro
```

## Fluxo de Dados

### Coleta de Logs
```mermaid
graph LR
    A[Kali: Atacante] -->|ataques SSH/HTTP| B[Host: Logs do sistema]
    B -->|Wazuh Agent| C[Wazuh Manager: Análise]
    C -->|Correlação + Regras| D[Wazuh Indexer: Armazenamento]
    D -->|Consulta| E[Wazuh Dashboard: Visualização]
```

### Pipeline de Detecção
```mermaid
graph LR
    subgraph PIPELINE["Pipeline de Detecção"]
        A[1. Evento no host<br/>login SSH / alteração FIM / scan rede]
        B[2. Wazuh Agent captura<br/>e envia TCP :1514]
        C[3. Wazuh Manager correlaciona<br/>local_rules.xml]
        D[4. Alerta gerado →<br/>Wazuh Indexer OpenSearch]
        E[5. Wazuh Dashboard<br/>exibe em tempo real]
        A --> B --> C --> D --> E
    end
```

### Fluxo de Ataque e Recuperacao
```mermaid
graph TB
    subgraph FASES["Fluxo de Ataque e Recuperação"]
        F1["Fase 1: Recon (nmap)"] -->|Alerta DE.CM| N1["NIST CSF DE.CM (Detect)"]
        F2["Fase 2: Brute Force (hydra)"] -->|Alerta PR.AC| N2["NIST CSF PR.AC (Protect)"]
        F3["Fase 3: SQL Injection"] -->|Alerta LGPD| L1["LGPD Art.46"]
        F4["Fase 4: Ransomware (SSH)"] -->|Alerta FIM| N3["NIST CSF PR.DS"]
        F5["Fase 5: Restore (Restic)"] -->|Alerta RC.RP| N4["NIST CSF RC.RP (Recovery)"]
    end
```

## Requisitos de Hardware

| Componente | Mínimo | Recomendado |
|------------|--------|-------------|
| RAM | 12 GB | 16 GB |
| CPU | 4 cores | 8 cores |
| Disco | 60 GB | 120 GB (SSD) |
| SO | Arch Linux | Arch Linux |

## Referências

- [Wazuh Docker](https://github.com/wazuh/wazuh-docker) - Repositório oficial
- [Wazuh Documentation](https://documentation.wazuh.com/) - Documentação oficial
- [DVWA](https://github.com/digininja/DVWA) - Damn Vulnerable Web Application
- [Restic](https://restic.net/) - Ferramenta de backup
