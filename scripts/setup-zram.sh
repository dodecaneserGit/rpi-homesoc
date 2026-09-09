#!/usr/bin/env bash
set -e

echo "=== [ HOME SOC ] Instalación y Configuración de ZRAM (Swap comprimido en RAM) ==="

sudo apt update
sudo apt install -y zram-tools

# Configurar 50% de RAM como zram comprimido con algoritmo zstd
sudo bash -c 'cat > /etc/default/zramswap <<EOF
ALGO=zstd
PERCENT=50
PRIORITY=100
EOF'

sudo systemctl restart zramswap
sudo systemctl enable zramswap

echo "=== ZRAM configurado y activo con éxito (zramctl para comprobar). ==="
