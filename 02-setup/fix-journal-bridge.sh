#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

mkdir -p /var/log/soc-corporativo

run_root tee /etc/systemd/system/soc-journal-bridge.service > /dev/null << 'EOF'
[Unit]
Description=SOC Journald Bridge - encaminha logs do systemd para arquivo monitorado pelo Wazuh
After=systemd-journald.service

[Service]
Type=simple
ExecStart=/bin/sh -c 'journalctl -f -n 0 -o short >> /var/log/soc-corporativo/soc-journal.log'
Restart=always
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

run_root systemctl daemon-reload
run_root systemctl enable --now soc-journal-bridge
run_root systemctl status soc-journal-bridge --no-pager
