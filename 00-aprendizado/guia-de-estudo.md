# Guia de Estudo — SOC Corporativo com Wazuh

> Documento preparatório para apresentação acadêmica.
> Leia este guia para entender profundamente o Wazuh, o projeto, e saber responder qualquer pergunta do professor.

---

## Sumário

1. [O que é o Wazuh?](#1-o-que-é-o-wazuh)
2. [Arquitetura do Wazuh](#2-arquitetura-do-wazuh)
3. [O Projeto SOC Corporativo](#3-o-projeto-soc-corporativo)
4. [Arquitetura do Projeto](#4-arquitetura-do-projeto)
5. [Cadeia de Ataque — As 5 Fases](#5-cadeia-de-ataque--as-5-fases)
6. [Regras de Compliance](#6-regras-de-compliance)
7. [Fluxo de Detecção](#7-fluxo-de-detecção)
8. [Backup e Recovery](#8-backup-e-recovery)
9. [Principais Conceitos para a Prova Oral](#9-principais-conceitos-para-a-prova-oral)
10. [Possíveis Perguntas do Professor](#10-possíveis-perguntas-do-professor)

---

## 1. O que é o Wazuh?

### Definição

Wazuh é uma **plataforma open source de segurança unificada** que combina quatro capacidades principais em um único sistema:

| Capacidade | Sigla | Função |
|------------|-------|--------|
| **SIEM** | Security Information and Event Management | Correlação e análise de eventos de segurança em tempo real |
| **HIDS** | Host-based Intrusion Detection System | Detecção de intrusões no nível do sistema operacional |
| **FIM** | File Integrity Monitoring | Monitoramento de integridade de arquivos |
| **SCA** | Security Configuration Assessment | Avaliação de conformidade e configuração segura |

### História

- Originalmente baseado no **OSSEC** (criado por Daniel Cid em 2004)
- O Wazuh surgiu como um fork do OSSEC em 2015, adicionando:
  - Dashboard web moderno (Kibana/OpenSearch Dashboards)
  - API REST completa
  - Escalabilidade via cluster
  - Regras e decoders mais robustos
- Atualmente na versão **4.x** (usamos a 4.9.0 no projeto)
- Licenciado sob **GPL 2.0**

### Componentes Principais

```
┌──────────────┐     ┌──────────────┐     ┌───────────────┐
│   Wazuh      │     │   Wazuh      │     │   Wazuh       │
│   Agent      │────▶│   Manager    │────▶│   Indexer     │────▶Dashboard
│  (coleta)    │     │  (análise)   │     │(armazenamento)│
└──────────────┘     └──────────────┘     └───────────────┘
```

1. **Wazuh Agent**: Instalado nos hosts monitorados. Coleta logs, monitora arquivos, detecta rootkits. Envia dados para o Manager via porta 1514 (TCP/UDP), criptografado com AES.

2. **Wazuh Manager**: Servidor central que recebe dados dos agents, aplica regras de correlação (decoders + rules), gera alertas e os encaminha para o Indexer.

3. **Wazuh Indexer**: Baseado no OpenSearch (fork do Elasticsearch). Armazena todos os alertas e eventos em índices diários. Permite buscas avançadas.

4. **Wazuh Dashboard**: Interface web baseada em OpenSearch Dashboards (fork do Kibana). Exibe alertas em tempo real, dashboards, relatórios.

### Formatos de Arquivo Importantes

- **`ossec.conf`**: Configuração do agente/manager (XML)
- **`local_rules.xml`**: Regras customizadas de correlação
- **`decoders.xml`**: Decoders para extrair campos de logs
- **`/var/ossec/logs/alerts/alerts.json`**: Alertas em formato JSON

---

## 2. Arquitetura do Wazuh

### Fluxo de Dados

```
1. Evento ocorre no host (ex: login SSH falhou)
2. Wazuh Agent captura o log
3. Agent envia para o Manager (porta 1514)
4. Manager aplica decoders (extrai campos)
5. Manager aplica rules (correlaciona)
6. Se uma rule match → alerta gerado
7. Alerta enviado para o Indexer (OpenSearch)
8. Dashboard exibe o alerta em tempo real
```

### Decoders vs Rules

- **Decoder**: Extrai campos estruturados de um log bruto (ex: extrair IP, usuário, comando de uma linha de log SSH)
- **Rule**: Define condições para gerar alertas baseado nos campos extraídos

Exemplo:

```
Log bruto: "Jun 8 10:30:45 arch sshd[1234]: Failed password for root from 192.168.56.20"

Decoder extrai:
  - application: sshd
  - srcip: 192.168.56.20
  - user: root
  - result: Failed

Rule 200003 detecta:
  - if_group authentication_failed
  → Alerta: NIST PR.AC - Access Control - SSH authentication failure
```

### Grupos de Regras Padrão

| Grupo | Descrição |
|-------|-----------|
| `authentication_failures` | Falhas de autenticação |
| `authentication_success` | Logins bem sucedidos |
| `syscheck` | Alterações em arquivos (FIM) |
| `web_attack` | Ataques web (SQLi, XSS) |
| `nmap` | Escaneamento de portas |
| `rootcheck` | Rootkits e malware |
| `cron` | Modificações no cron |

---

## 3. O Projeto SOC Corporativo

### Objetivo Acadêmico

Demonstrar na prática como um **Centro de Operações de Segurança (SOC)** funciona, utilizando o Wazuh como SIEM open source, simulando:

- **Ataques reais** em ambiente controlado
- **Detecção em tempo real** pelo Wazuh
- **Classificação por frameworks** de compliance (NIST CSF, ISO 27001, LGPD)
- **Recuperação** após incidente (backup e restore)

### Ambiente

| Componente | Especificação |
|------------|--------------|
| **Host** | Arch Linux, 16 GB RAM, 4+ cores |
| **Wazuh** | Docker (manager + indexer + dashboard), versão 4.9.0 |
| **DVWA** | Damn Vulnerable Web Application, container Docker, porta 8080 |
| **Dados LGPD** | 100 arquivos em /data/clientes/ + 5 registros no MySQL |
| **Kali Linux** | VM VirtualBox, 2 GB RAM, 192.168.56.20 |
| **Backup** | Restic, repositório local em /backup-repo |

### Estrutura de Diretórios

```
soc-corporativo/               ← Raiz do projeto
├── README.md                  ← Visão geral (comece aqui)
├── Makefile                   ← Geração de PDFs
├── 00-aprendizado/            → Entender a ferramenta e conceitos
├── 01-arquitetura/            → Entender o projeto
├── 02-setup/                  → Montar o ambiente
├── 03-configuracao/           → Arquivos de configuração
├── 04-operação/               → Executar e verificar
├── 05-resultados/             → Entregas e evidências
└── 06-apresentacao/           → Apresentar o projeto
```

---

## 4. Arquitetura do Projeto

### Diagrama de Rede

```
┌──────────────────────────────────────────────────────────────┐
│                     HOST (Arch Linux)                          │
│                     192.168.56.1 (vboxnet0)                   │
│                                                               │
│  ┌─────────────────┐  ┌──────────┐  ┌──────────────────┐    │
│  │  WAZUH DOCKER   │  │  DVWA    │  │  SERVIÇOS NATIVOS │    │
│  │  - manager:1514 │  │  :8080   │  │  - Wazuh Agent   │    │
│  │  - indexer:9200 │  │  MySQL   │  │  - /data/clientes │    │
│  │  - dashboard:443│  │  LGPD    │  │  - /backup-repo   │    │
│  └─────────────────┘  └──────────┘  └──────────────────┘    │
└──────────────────────────────┬───────────────────────────────┘
                               │ vboxnet0
                               ▼
                    ┌─────────────────────┐
                    │   KALI LINUX (VM)    │
                    │   192.168.56.20      │
                    │   Nmap, Hydra, SSH   │
                    └─────────────────────┘
```

### Componentes em Detalhe

#### Wazuh Docker (3 containers)

- **wazuh-manager**: Recebe conexões dos agents (porta 1514), syslog (porta 514), aplica regras
- **wazuh-indexer**: OpenSearch, armazena alertas, índices diários, API REST (porta 9200)
- **wazuh-dashboard**: Interface web (porta 443), dashboards pré-configurados

#### DVWA (1 container)

- Aplicação web intencionalmente vulnerável
- Contém MySQL com dados LGPD (5 registros de pessoas físicas)
- Porta 8080 mapeada para o host

#### Agente Wazuh (nativo no Arch)

- Monitora logs do sistema via **journald bridge**
- Monitora integridade de arquivos (FIM) em /data/clientes/
- Envia logs para o manager

### Por que Docker em vez de VM?

Na **Opção 4** (abordagem anterior), o Wazuh rodava em uma VM separada. Na **Opção 5** (atual), optamos por Docker porque:

| Aspecto | VM | Docker |
|---------|-----|--------|
| Recursos | ~4 GB RAM dedicados | ~2 GB compartilhados |
| Tempo de setup | Horas | Minutos |
| Portabilidade | Médio | Alto |
| Atualização | Complexa | `docker compose pull` |
| Ideal para | Produção | Laboratório/Demonstração |

---

## 5. Cadeia de Ataque — As 5 Fases

### Visão Geral

A demonstração simula um ataque real seguindo o ciclo de vida de um incidente de segurança, desde o reconhecimento até a recuperação.

### Fase 1 — Reconhecimento

**O que acontece:** O atacante usa nmap para escanear portas abertas no alvo.

**Comando:**

```bash
nmap -sS -sV -p 22,80,3306,443,1514 192.168.56.1
```

**O que testa:** Capacidade de detecção de varredura de rede.

**Alerta Wazuh:** SID 200006 — NIST DE.CM: Security Monitoring - SSH scan detected (severidade 8)

**Framework:** NIST Detect (DE.CM), ISO 27001 A.16.1.5 (na verdade A.12.6.1 ou A.16.1.5 dependendo da regra)

**Por que é importante:** Escaneamento é quase sempre o primeiro passo de um ataque. Detectá-lo permite bloquear o atacante antes que ele encontre uma vulnerabilidade.

### Fase 2 — Brute Force SSH

**O que acontece:** O atacante tenta descobrir a senha SSH usando hydra com a wordlist rockyou.txt.

**Comando:**

```bash
hydra -l paulo -P /usr/share/wordlists/rockyou.txt ssh://192.168.56.1 -t 4
```

**O que testa:** Detecção de múltiplas falhas de autenticação em sequência.

**Alerta Wazuh:** SID 200003 — NIST PR.AC: Access Control - SSH authentication failure (severidade 8)

**Regra de correlação:** SID 200040 — Se >30 falhas em 5 minutos, severidade sobe para 15 (BRUTE FORCE: 30+ failed logins in 5 minutes)

**Framework:** NIST Protect (PR.AC), ISO 27001 A.9.4.2 (na verdade A.9.4.2 e MITRE T1110)

**Por que é importante:** Força bruta é o método mais comum de acesso não autorizado. O Wazuh correlaciona tentativas para identificar padrões.

### Fase 3 — SQL Injection com Vazamento LGPD

**O que acontece:** O atacante explora uma vulnerabilidade SQL Injection no DVWA para extrair dados pessoais do banco MySQL.

**Comando:**

```bash
curl -s "http://192.168.56.1:8080/DVWA/vulnerabilities/sqli/
  ?id=%27+UNION+SELECT+id%2Cconcat(nome%2C%27+%7C+%27%2Ccpf)%2Cemail%2Ctelefone%2Cendereco+FROM+clientes.pessoas--+-
  &Submit=Submit"
```

**Dados extraídos:** Nome, CPF, email, telefone, endereço (5 registros)

**Alerta Wazuh:** SID 200031 — MITRE ATTACK T1190: Exploit Public-Facing App (severidade 10 — CRÍTICA)

**Frameworks:**

- LGPD Art. 46 (segurança), Art. 48 (notificação ANPD), Art. 49 (sigilo)
- NIST Detect (DE.CM)
- ISO 27001 A.14.2.1 (desenvolvimento seguro)

**Esta é a fase mais importante da demonstração** porque:

1. Envolve **dados pessoais reais** (LGPD)
2. A severidade é a **mais alta** (12)
3. Demonstra a **notificação ANPD** (Art. 48 — 5 dias úteis)
4. Cruza **3 frameworks** simultaneamente

### Fase 4 — Ransomware Simulado

**O que aconteta:** O atacante acessa o host via SSH e "criptografa" os arquivos de clientes (renomeia .txt → .encrypted).

**Comando:**

```bash
ssh paulo@192.168.56.1 \
  "cd /data/clientes && for f in *.txt; do mv \$f \$f.encrypted; done"
```

**O que testa:** Monitoramento de integridade de arquivos (FIM) em tempo real.

**Alerta Wazuh:** SID 200004 — NIST PR.DS: Data Security - File integrity change detected (severidade 9)

**Framework:** NIST Protect (PR.DS), ISO 27001 A.12.3.1

**Por que é importante:** Ransomware é a ameaça #1 atualmente. O FIM do Wazuh detecta alterações em segundos, permitindo resposta imediata.

### Fase 5 — Disaster Recovery

**O que acontece:** O administrador executa o restore do backup para recuperar os dados.

**Comando:**

```bash
sudo /usr/local/bin/restore-clientes-local.sh
```

**O que testa:** Plano de recuperação com métricas RPO/RTO.

**Alerta Wazuh:** SID 200033 — NIST RC.RP: Disaster Recovery - Restore executed successfully (severidade 5)

**Framework:** NIST Recover (RC.RP), ISO 27001 A.12.3.1

**Métricas:**

- **RPO (Recovery Point Objective):** 1 hora (backup a cada hora)
- **RTO (Recovery Time Objective):** ~12 minutos (para restaurar 100 arquivos)

---

## 6. Regras de Compliance

### O que são regras de compliance no Wazuh?

São regras customizadas em XML que **enriquecem** os alertas com metadados de frameworks regulatórios. Quando um evento é detectado, a regra adiciona campos como:

```xml
<field name="compliance.nist">Protect</field>
<field name="compliance.nist_funcao">PR.AC</field>
<field name="compliance.iso">A.9.4.2</field>
<field name="compliance.lgpd">Art.46</field>
```

Isso permite **filtrar alertas por framework** no Dashboard, criar relatórios de compliance, e demonstrar conformidade com normas.

### Estrutura de uma Regra

```xml
<rule id="200031" level="10">
  <if_sid>31151,31152,31153</if_sid>
  <description>MITRE ATTACK T1190: Exploit Public-Facing App</description>
</rule>
```

### Frameworks Implementados

#### NIST Cybersecurity Framework

O NIST CSF é organizado em 5 funções:

| Função | Sigla | O que cobre | Nossas Regras |
|--------|-------|-------------|---------------|
| **Identify** | ID.AM | Gerenciamento de ativos | 200001, 200002 |
| **Protect** | PR.AC, PR.DS | Controle de acesso, segurança de dados | 200003, 200004, 200005, 200008, 200010 |
| **Detect** | DE.CM | Monitoramento contínuo | 200006, 200007, 200009 |
| **Recover** | RC.RP | Planejamento de recuperação | 200032, 200033 |

Total: **12 regras** NIST CSF

#### ISO 27001:2013 (Anexo A)

| Controle | Descrição | Regra |
|----------|-----------|-------|
| A.12.4.1 | Registro de eventos | 200011 |
| A.16.1.5 | Gestão de incidentes de segurança da informação | 200012 |
| A.14.2.1 | Engenharia de sistemas segura | 200013 |
| A.9.4.2 | Controle de acesso a sistemas e aplicações | 200014 |
| A.12.6.1 | Gerenciamento de vulnerabilidades técnicas | 200015 |

Total: **5 regras** ISO 27001

#### LGPD (Lei 13.709/2018)

| Artigo | Obrigação | Regra |
|--------|-----------|-------|
| Art. 46 | Medidas de segurança técnicas e administrativas | 200016, 200017, 200020 |
| Art. 49 | Sigilo e confidencialidade dos dados pessoais | 200018, 200019 |

Total: **5 regras** LGPD

### Regras de Correlação (Importante!)

Regras especiais que detectam **padrões** ao invés de eventos isolados:

- **SID 200040 (severidade 15):** Se >30 falhas de autenticação em 5 minutos → ataque de força bruta confirmado

Regras de correlação usam os atributos:

- `frequency`: número de ocorrências
- `timeframe`: janela de tempo (segundos)
- `ignore`: intervalo entre alertas

---

## 7. Fluxo de Detecção

### Pipeline Completo

```
┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐
│ EVENTO  │──▶│ COLETA  │──▶│ ENVIO   │──▶│ ANÁLISE │──▶│ STORAGE │──▶│  VISUAL │
│ Ocorre  │   │ Agent   │   │ 1514TCP │   │ Manager │   │ Indexer │   │ização   │
└─────────┘   └─────────┘   └─────────┘   └─────────┘   └─────────┘   └─────────┘
                                                                             │
                                                                             ▼
                                                                      ┌──────────┐
                                                                      │ Dashboard│
                                                                      │ Web UI   │
                                                                      └──────────┘
```

### Passo a Passo Detalhado

1. **Evento**: Algo acontece no host — login SSH, alteração de arquivo, scan de rede, requisição HTTP

2. **Coleta**: O Wazuh Agent (ou journald bridge) captura o evento:
   - Logs do sistema: via `journalctl` → arquivo → agente lê o arquivo
   - Alterações de arquivo: via `syscheck` (FIM) → monitora diretórios em tempo real
   - Logs de aplicação: via leitura de arquivos de log

3. **Envio**: O agent envia para o manager via TCP porta 1514, criptografado com AES

4. **Análise**: O manager processa:
   - **Decoder**: extrai campos estruturados do log bruto
   - **Rule**: compara contra as regras (primeiro as padrão, depois as customizadas)
   - **Match**: se uma regra corresponde → gera alerta com metadados

5. **Storage**: O alerta é enviado para o Wazuh Indexer (OpenSearch), armazenado em índices diários

6. **Visualização**: O Dashboard exibe o alerta em tempo real, com:
   - Severidade (cores: verde, laranja, vermelho)
   - Descrição do alerta
   - Framework de compliance associado
   - Dados brutos do evento

### Exemplo Real

**Entrada (log do sistema):**

```
Jun 8 10:30:45 arch sshd[1234]: Failed password for root from 192.168.56.20 port 45678 ssh2
```

**Processamento:**

1. Decoder `sshd` extrai: `srcip=192.168.56.20, user=root, result=failed`
2. Rule `authentication_failed` match
3. Rule customizada 200003 extends: adiciona metadados NIST PR.AC
4. Se >30 ocorrências em 5 minutos: regra de correlação 200040 (severidade 15)

**Saída (alerta JSON):**

```json
{
  "rule": { "id": 200003, "severity": 8 },
  "description": "NIST CSF PR.AC: Multiple authentication failures detected",
  "compliance": {
    "nist": "Protect",
    "nist_funcao": "PR.AC",
    "iso": "A.9.4.2"
  },
  "data": {
    "srcip": "192.168.56.20",
    "user": "root"
  }
}
```

---

## 8. Backup e Recovery

### Restic

Ferramenta de backup open source com:

- **Criptografia**: AES-256-GCM
- **Deduplicação**: blocos duplicados são armazenados uma única vez
- **Compressão**: zstd (reduz tamanho dos backups)
- **Snapshots**: cada backup é um snapshot imutável

### Esquema de Backup

```
/data/clientes/ (100 arquivos .txt)
       │
       ▼
restic backup → /backup-repo/ (repositório local)
       │
       ▼
    Logger "BACKUP_EXECUTADO" → journald → Wazuh detecta (SID 200032)

Cron: 0 * * * * (a cada hora → RPO = 1h)
```

### Métricas

| Métrica | Valor | Significado |
|---------|-------|-------------|
| **RPO** (Recovery Point Objective) | 1 hora | Máximo de dados que pode ser perdido |
| **RTO** (Recovery Time Objective) | ~12 minutos | Tempo para recuperar totalmente |
| **Snapshots** | 24 (rolling) | Backup das últimas 24 horas |
| **Integridade** | 100% | Todos os arquivos restaurados corretamente |

### Fluxo de Recuperação

```
Ransomware → Wazuh FIM detecta → Restore via Restic → Verificação
   ↓               ↓                    ↓                  ↓
100 arquivos   Alerta PR.DS       12 minutos       100% ok
criptografados severidade 9      restore latest
```

---

## 9. Principais Conceitos

### Conceitos Gerais de SIEM

| Conceito | Definição |
|----------|-----------|
| **SIEM** | Sistema que coleta, normaliza, correlaciona e analisa logs de segurança em tempo real |
| **Log** | Registro de um evento ocorrido em um sistema |
| **Alerta** | Notificação gerada quando uma regra de correlação é satisfeita |
| **Correlação** | Análise de múltiplos eventos para identificar padrões de ataque |
| **Falso positivo** | Alerta gerado para um evento legítimo (não é um ataque real) |
| **Falso negativo** | Ataque real que não gerou alerta (pior cenário) |

### Conceitos Específicos do Wazuh

| Conceito | Definição |
|----------|-----------|
| **Agent** | Software instalado no host monitorado |
| **Manager** | Servidor central que recebe e analisa dados |
| **Indexer** | OpenSearch para armazenamento e busca |
| **Dashboard** | Interface web para visualização |
| **Decoder** | Extrai campos estruturados de logs brutos |
| **Rule** | Define condições para gerar alertas |
| **FIM (syscheck)** | Monitoramento de integridade de arquivos |
| **Rootcheck** | Detecção de rootkits e malware |
| **SCA** | Avaliação de configuração de segurança |

### Frameworks de Compliance

| Framework | O que é | Nosso uso |
|-----------|---------|-----------|
| **NIST CSF** | Framework de cibersegurança do governo americano (5 funções) | Classificar alertas por função (Identify, Protect, Detect, Respond, Recover) |
| **ISO 27001** | Norma internacional de gestão de segurança da informação | Mapear controles do Anexo A (A.9, A.12, A.14, A.16) |
| **LGPD** | Lei brasileira de proteção de dados pessoais (Lei 13.709/2018) | Simular incidente com dados pessoais e notificação ANPD |

### Docker vs VM

| Aspecto | VM | Container |
|---------|-----|-----------|
| Virtualização | Completa (hardware virtualizado) | Nível de SO (kernel compartilhado) |
| Peso | GBs (OS completo) | MBs (apenas binários) |
| Inicialização | Minutos | Segundos |
| Isolamento | Máximo | Bom (namespaces) |
| SO | Qualquer | Mesmo kernel do host |

---

## 10. Possíveis Perguntas

### Perguntas sobre o Wazuh

**P: O que é o Wazuh e para que serve?**
R: Wazuh é uma plataforma open source de segurança que combina SIEM, HIDS e monitoramento de conformidade. Serve para detectar ameaças, monitorar integridade de arquivos, analisar logs e avaliar conformidade com frameworks como NIST e ISO 27001.

**P: Qual a diferença entre Wazuh e OSSEC?**
R: Wazuh é um fork do OSSEC que adicionou dashboard web, API REST, escalabilidade em cluster, e integração com Elasticsearch/OpenSearch. O OSSEC tem interface apenas CLI.

**P: Quais os componentes do Wazuh?**
R: Agent (coleta), Manager (análise), Indexer (armazenamento), Dashboard (visualização). Também pode incluir Filebeat para transporte de dados.

**P: Como o Wazuh se comunica com os agents?**
R: Via TCP/UDP porta 1514, com criptografia AES. O agent inicia a conexão com o manager.

**P: O que é FIM e como funciona?**
R: File Integrity Monitoring. O Wazuh monitora diretórios configurados e detecta alterações em tempo real (criação, modificação, exclusão, renomeação de arquivos). Usa checksums para comparar estado anterior vs atual.

### Perguntas sobre o Projeto

**P: Qual o objetivo do projeto?**
R: Demonstrar na prática o funcionamento de um SOC (Security Operations Center) utilizando Wazuh como SIEM, simulando ataques em ambiente controlado e classificando-os por frameworks de compliance.

**P: Por que vocês escolheram Docker em vez de VM?**
R: A abordagem inicial usava VMs separadas, mas migramos para Docker por questões de recursos de hardware (16 GB RAM insuficiente para múltiplas VMs). Docker permite rodar o Wazuh com ~2 GB RAM.

**P: Quantas VMs e containers são usados?**
R: 1 VM (Kali Linux) e 4 containers Docker (wazuh-manager, wazuh-indexer, wazuh-dashboard, DVWA).

**P: Quais as 5 fases da demonstração?**
R: Reconhecimento (nmap), Brute Force SSH (hydra), SQL Injection com vazamento LGPD, Ransomware simulado, e Disaster Recovery (restore Restic).

**P: Qual fase é a mais crítica e por quê?**
R: A Fase 3 (SQL Injection + LGPD) porque envolve dados pessoais, tem severidade máxima (12), e aciona obrigações legais reais como notificação ANPD em até 5 dias úteis.

**P: Como o Wazuh detecta o ransomware?**
R: Via FIM (File Integrity Monitoring). O diretório /data/clientes/ é monitorado em tempo real. Quando 100 arquivos são alterados simultaneamente, o Wazuh gera alerta de severidade 9.

### Perguntas sobre Compliance

**P: Quais frameworks de compliance foram implementados?**
R: NIST CSF (5 funções, 13 regras), ISO 27001:2013 (6 controles, 8 regras), e LGPD (3 artigos, 4 regras). Total de ~40 regras customizadas.

**P: Como as regras de compliance são implementadas no Wazuh?**
R: No arquivo local_rules.xml. Cada regra customizada adiciona metadados ao alerta através de campos `<field>`, como `compliance.nist`, `compliance.iso`, `compliance.lgpd`.

**P: O que é RPO e RTO?**
R: RPO (Recovery Point Objective) é o máximo de dados aceitável perder — no projeto é 1 hora. RTO (Recovery Time Objective) é o tempo máximo para recuperar — ~12 minutos no projeto.

### Perguntas Técnicas Avançadas

**P: Como funciona a correlação de eventos no Wazuh?**
R: Usando regras com atributos `frequency` (número de ocorrências) e `timeframe` (janela em segundos). Exemplo: a regra 200040 detecta >30 falhas de autenticação em 5 minutos e eleva a severidade para 15.

**P: O que são decoders e rules?**
R: Decoders extraem campos estruturados de logs brutos (ex: extrair IP, usuário de um log SSH). Rules definem condições para gerar alertas baseado nos campos extraídos.

**P: Como o agente Wazuh lida com journald no Arch Linux?**
R: Arch Linux usa systemd-journald em vez de arquivos de log tradicionais (/var/log/auth.log, /var/log/syslog). Implementamos um "journal bridge" — um serviço systemd que usa `journalctl -f` para escrever os logs em /var/log/soc-corporativo/soc-journal.log, que o Wazuh Agent monitora.

---

## Glossário Rápido

| Sigla | Significado |
|-------|-------------|
| **SIEM** | Security Information and Event Management |
| **HIDS** | Host-based Intrusion Detection System |
| **FIM** | File Integrity Monitoring |
| **SCA** | Security Configuration Assessment |
| **SOC** | Security Operations Center |
| **NIST CSF** | National Institute of Standards and Technology Cybersecurity Framework |
| **ISO** | International Organization for Standardization |
| **LGPD** | Lei Geral de Proteção de Dados Pessoais |
| **ANPD** | Autoridade Nacional de Proteção de Dados |
| **RPO** | Recovery Point Objective |
| **RTO** | Recovery Time Objective |
| **DVWA** | Damn Vulnerable Web Application |
| **SID** | Signature ID (identificador único da regra) |
| **MITRE ATT&CK** | Matriz de táticas e técnicas de ataques cibernéticos |

---
