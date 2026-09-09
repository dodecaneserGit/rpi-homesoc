#!/usr/bin/env bash
set -e

echo "=== [ HOME SOC ] Instalador Automatizado de Docker & Compose ==="

# 1. Actualizar repositorios
sudo apt update && sudo apt upgrade -y

# 2. Instalar Docker oficial
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
rm get-docker.sh

# 3. Añadir usuario actual al grupo docker
sudo usermod -aG docker "$USER"

# 4. Habilitar servicio
sudo systemctl enable docker
sudo systemctl start docker

echo "=== Docker y Docker Compose instalados con éxito. Cierra sesión y vuelve a entrar para aplicar permisos. ==="
