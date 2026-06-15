#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

RESTIC_PASSWORD="${RESTIC_PASSWORD:-backup2024}"

run_root mkdir -p /backup-repo
run_root chmod 777 /backup-repo

# Password file for Restic (reusable by scripts)
run_root mkdir -p /etc/restic
echo "${RESTIC_PASSWORD}" | run_root tee /etc/restic/passwd > /dev/null
run_root chmod 600 /etc/restic/passwd

run_root restic init --repo /backup-repo <<< "${RESTIC_PASSWORD}"

run_root tee /usr/local/bin/backup-clientes-local.sh > /dev/null << 'SCRIPT'
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

run_root tee /usr/local/bin/restore-clientes-local.sh > /dev/null << 'SCRIPT'
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

# Copy restored data to original directory
rsync -a --delete "$TARGET/data/clientes/" "$DATA_DIR/"
rm -rf "$TARGET"

RTO=$(( ($(date +%s) - START_TIME) / 60 ))
RTO_S=$(( ($(date +%s) - START_TIME) % 60 ))
COUNT=$(ls "$DATA_DIR/"*.txt 2>/dev/null | wc -l)

syslog "RESTORE_EXECUTADO: RTO ${RTO}min ${RTO_S}s | ${COUNT} arquivos"
echo "RTO: ${RTO}min ${RTO_S}s | ${COUNT} arquivos restaurados em ${DATA_DIR}"
SCRIPT

run_root chmod +x /usr/local/bin/backup-clientes-local.sh
run_root chmod +x /usr/local/bin/restore-clientes-local.sh

# Trigger backup (will prompt for password if needed)
run_root /usr/local/bin/backup-clientes-local.sh
run_root restic snapshots --repo /backup-repo <<< "${RESTIC_PASSWORD}"
echo "Backup OK"
