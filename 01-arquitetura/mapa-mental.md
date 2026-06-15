# Mapa Mental — SOC Corporativo (Mermaid)

```mermaid
mindmap
  root((SOC Corporativo))
    Kali_Atacante
      192.168.56.20
      Nmap
      Hydra
      Curl
      SSH
    Host_Arch_Alvo
      192.168.56.1
      Wazuh_Docker
        wazuh-manager
        wazuh-indexer
        wazuh-dashboard
      Wazuh_Agent
        Coleta_logs
        FIM_arquivos
      DVWA
        MySQL_LGPD
      Backup_Restic
        /backup-repo
        /data/clientes
    Cadeia_de_Ataque
      F1_Recon_Nmap
      F2_Brute_Force_Hydra
      F3_SQLi_LGPD
      F4_Ransomware_SSH
      F5_Disaster_Recovery
    Frameworks
      NIST_CSF
      ISO_27001
      LGPD
```

---

## Arquitetura do Ambiente

```mermaid
graph TB
    subgraph KALI["Kali Linux (Atacante) — 192.168.56.20"]
        N[Nmap]
        H[Hydra]
        C[Curl]
        S[SSH]
    end

    subgraph HOST["Host Arch Linux (Alvo) — 192.168.56.1"]
        subgraph DOCKER["Docker Wazuh Stack"]
            M[wazuh-manager<br/>:1514 TCP]
            I[wazuh-indexer<br/>:9200]
            D[wazuh-dashboard<br/>:443]
        end

        subgraph AGENT["Wazuh Agent Nativo"]
            LOG[Coleta de logs<br/>journal-bridge]
            FIM[FIM syscheck<br/>tempo real]
        end

        subgraph TARGET["Serviços Alvo"]
            DVWA[<b>DVWA</b> :8080<br/>MySQL clientes.pessoas]
            DATA[<b>/data/clientes/</b><br/>100 arquivos .txt]
            BACKUP[<b>/backup-repo/</b><br/>Restic snapshots]
        end

        LOG_APPS[Logs backup.log<br/>restore.log<br/>soc-journal.log]
    end

    subgraph REDE["Rede VirtualBox Host-Only"]
        NET[vboxnet0<br/>192.168.56.0/24]
    end

    KALI --- NET --- HOST

    M -.->|armazena índices| I
    D -.->|consulta índices| I
    LOG --->|syslog :1514| M
    FIM --->|alertas FIM| M
    DVWA --->|logs HTTP| LOG
    DATA --->|FIM monitora| FIM
    BACKUP --->|logs backup| LOG_APPS
    LOG_APPS --->|agente lê| LOG
```

---

## Pipeline de Detecção (Fluxo de Dados)

```mermaid
flowchart LR
    subgraph MUNDO["Mundo Real"]
        EV1[("F1: Nmap<br/>Varredura portas")]
        EV2[("F2: Hydra<br/>Brute force SSH")]
        EV3[("F3: Curl<br/>SQL Injection")]
        EV4[("F4: SSH mv<br/>Ransomware")]
        EV5[("F5: SSH restore<br/>Disaster Recovery")]
    end

    subgraph FONTES["Fontes de Log no Host"]
        JB[journal-bridge<br/>journalctl -f]
        AL[/var/log/auth.log]
        SYS[syscheck FIM]
        BL[/var/log/backup.log]
        RL[/var/log/restore.log]
    end

    subgraph PIPELINE["Pipeline Wazuh"]
        AG[<b>Wazuh Agent</b><br/>Coleta e envia]
        DEC[Decoder<br/>Extrai campos]
        RULES[local_rules.xml<br/>~40 regras]
        ALERT[Alerta gerado]
    end

    subgraph DESTINO["Destino"]
        IDX[wazuh-indexer<br/>OpenSearch]
        DSH[wazuh-dashboard<br/>Visualização]
    end

    EV1 --> JB
    EV2 --> AL
    EV3 --> JB
    EV4 --> SYS
    EV5 --> BL & RL

    JB & AL & BL & RL -->|TCP :1514| AG
    SYS --> AG
    AG --> DEC --> RULES --> ALERT
    ALERT --> IDX --> DSH
```

---

## Cadeia de Ataque — 5 Fases

```mermaid
sequenceDiagram
    participant K as Kali (192.168.56.20)
    participant H as Host Arch (192.168.56.1)
    participant DVWA as DVWA Docker (:8080)
    participant W as Wazuh Manager
    participant D as Dashboard

    Note over K,D: FASE 1 — RECONHECIMENTO (NIST DE.CM)
    K->>H: nmap -sS -sV -p 22,80,3306,443,1514
    H->>W: log: conexões detectadas
    W->>D: Alerta SID 200006 (severidade 8)

    Note over K,D: FASE 2 — BRUTE FORCE SSH (NIST PR.AC)
    K->>H: hydra -l paulo -P rockyou.txt ssh://192.168.56.1
    H->>W: log: "Failed password" repetido
    W->>D: Alerta SID 200003 (severidade 8)
    Note over W: >30 falhas em 5 min
    W->>D: Alerta CORRELAÇÃO SID 200040 (severidade 15)

    Note over K,D: FASE 3 — SQL INJECTION LGPD (LGPD Art.46)
    K->>DVWA: POST /login.php (login admin)
    K->>DVWA: GET /sqli/?id=' UNION SELECT...FROM clientes.pessoas
    DVWA-->>K: Nome, CPF, Email, Telefone (dados vazados)
    DVWA->>W: log: SQL injection detectado
    W->>D: Alerta SID 200031 (severidade 12 — CRÍTICO)

    Note over K,D: FASE 4 — RANSOMWARE SIMULADO (NIST PR.DS)
    K->>H: ssh paulo@host "mv *.txt *.txt.encrypted"
    H->>W: FIM: 100 arquivos alterados
    W->>D: Alerta SID 200004 x100 (severidade 9)

    Note over K,D: FASE 5 — DISASTER RECOVERY (NIST RC.RP)
    K->>H: ssh paulo@host "sudo restore-clientes-local.sh"
    H->>H: Restic restaura snapshot → /data/clientes/
    H->>W: log: "RESTORE_EXECUTADO"
    W->>D: Alerta SID 200033 (severidade 5)
```

---

## Regras × Ataques

```mermaid
flowchart TB
    subgraph FASES["5 Fases do Ataque"]
        F1[<b>F1: Recon</b><br/>Nmap]
        F2[<b>F2: Brute Force</b><br/>Hydra]
        F3[<b>F3: SQLi LGPD</b><br/>Curl]
        F4[<b>F4: Ransomware</b><br/>SSH + mv]
        F5[<b>F5: DR</b><br/>SSH + restore]
    end

    subgraph REGRAS["Regras de Compliance (local_rules.xml)"]
        R006[SID 200006<br/>DE.CM - SSH scan]
        R003[SID 200003<br/>PR.AC - Auth failures]
        R040[SID 200040<br/>Correlação >30 falhas]
        R030[SID 200031<br/>MITRE T1190 - SQLi]
        R004[SID 200004<br/>PR.DS - File change]
        R011[SID 200033<br/>RC.RP - Restore OK]
    end

    subgraph SEVERIDADE["Severidade"]
        S8["8 (ALTA)"]
        S15["15 (CRÍTICO)"]
        S12["12 (CRÍTICO)"]
        S9["9 (ALTA)"]
        S5["5 (INFO)"]
    end

    subgraph FRAMEWORK["Framework"]
        NIST1["NIST CSF DE.CM<br/>ISO A.16.1.5"]
        NIST2["NIST CSF PR.AC<br/>ISO A.9.4.2"]
        NIST3["NIST CSF PR.DS<br/>ISO A.12.3.1"]
        LGPD["LGPD Art.46/48/49"]
        REC["NIST CSF RC.RP<br/>ISO A.12.3.1"]
    end

    F1 --> R006 --> S8 --> NIST1
    F2 --> R003 --> S8 --> NIST2
    R003 -.->|agg 5min| R040 --> S15 --> NIST2
    F3 --> R030 --> S12 --> LGPD
    F4 --> R004 --> S9 --> NIST3
    F5 --> R011 --> S5 --> REC
```

---

## Navegação no Wazuh Dashboard

```mermaid
flowchart LR
    subgraph DASH["Wazuh Dashboard — https://localhost:443"]
        SE["Security Events<br/>(Módulo Principal)"]
    end

    subgraph FILTROS["Filtros por Fase"]
        F1F["rule.id: 200006<br/>→ Fase 1 (Nmap)"]
        F2F["rule.id: 200003<br/>→ Fase 2 (Hydra)"]
        F3F["rule.id: 200031<br/>→ Fase 3 (SQLi)"]
        F4F["rule.id: 200004<br/>→ Fase 4 (Ransomware)"]
        F5F["rule.id: 200033<br/>→ Fase 5 (DR)"]
        ALL["group: compliance<br/>→ Todas as fases"]
    end

    subgraph VISUAIS["Visualizações"]
        TIMELINE["Timeline<br/>(linha do tempo)"]
        TABLE["Tabela de alertas<br/>(detalhes/JSON)"]
        METRICS["Métricas<br/>(contagem/severidade)"]
    end

    DASH --> SE
    SE --> FILTROS
    SE --> VISUAIS
```

---

## Sumário Visual do Ambiente

```mermaid
pie title Componentes do SOC Corporativo
    "Wazuh Docker (manager + indexer + dashboard)" : 3
    "DVWA (alvo web vulnerável)" : 1
    "Wazuh Agent (coleta + FIM)" : 1
    "Kali Linux VM (atacante)" : 1
    "Restic Backup" : 1
```

```mermaid
pie title Alertas por Severidade
    "15 - Correlação Brute Force" : 1
    "12 - SQLi LGPD" : 1
    "9 - Ransomware FIM" : 1
    "8 - Reconhecimento" : 1
    "8 - Auth failures" : 1
    "5 - Backup executado" : 1
```
