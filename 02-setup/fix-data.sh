#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

run_root chmod 777 /data/clientes
for i in $(seq 6 100); do
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
echo "Total: $(ls /data/clientes/*.txt | wc -l) arquivos"
