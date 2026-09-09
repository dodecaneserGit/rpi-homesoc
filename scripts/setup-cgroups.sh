#!/usr/bin/env bash
set -e

echo "=== [ HOME SOC ] Habilitación de Cgroups Memory para Docker ==="

CMDLINE_FILE=""
if [ -f /boot/firmware/cmdline.txt ]; then
    CMDLINE_FILE="/boot/firmware/cmdline.txt"
elif [ -f /boot/cmdline.txt ]; then
    CMDLINE_FILE="/boot/cmdline.txt"
else
    echo "Error: No se encontró cmdline.txt"
    exit 1
fi

if grep -q "cgroup_memory=1" "$CMDLINE_FILE"; then
    echo "Cgroups memory ya está habilitado en $CMDLINE_FILE"
else
    echo "Añadiendo parámetros cgroup a $CMDLINE_FILE..."
    sudo sed -i '$s/$/ cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1/' "$CMDLINE_FILE"
    echo "¡Listo! Es necesario reiniciar la Raspberry Pi (sudo reboot) para aplicar los cambios."
fi
