#!/usr/bin/env bash
###############################################################################
# [ HOME SOC ] — Script de Bastionado y Hardening de Nodos Raspberry Pi
# Uso: sudo ./scripts/harden-node.sh [--role master|backup|decoy]
###############################################################################
set -euo pipefail

ROLE="${1:-}"

# Validar permisos de root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Este script debe ejecutarse con privilegios de root (sudo)."
  exit 1
fi

echo "======================================================================"
echo "🛡️  [ HOME SOC ] Iniciando Proceso de Bastionado del Sistema"
echo "======================================================================"

TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "pi")}"
TARGET_HOME=$(eval echo "~$TARGET_USER")

# ─────────────────────────────────────────────────────────────────────────────
# 1. VERIFICACIÓN Y HARDENING ESTRICTO DE SSH
# ─────────────────────────────────────────────────────────────────────────────
echo "[+] 1. Comprobando configuración de acceso SSH seguro..."

# Medida de seguridad: Comprobar que existe al menos una clave pública autorizada
AUTH_KEYS="$TARGET_HOME/.ssh/authorized_keys"
if [ ! -f "$AUTH_KEYS" ] || [ ! -s "$AUTH_KEYS" ]; then
  echo "⚠️  ADVERTENCIA CRÍTICA: No se ha detectado ninguna clave pública en $AUTH_KEYS."
  echo "    Deshabilitar contraseñas ahora te dejaría FUERA de la Raspberry Pi."
  echo "    Por favor, copia tu clave SSH desde tu máquina con:"
  echo "      ssh-copy-id $TARGET_USER@<IP_RASPBERRY>"
  echo "    ¿Deseas continuar bloqueando contraseñas de todos modos? (s/N)"
  read -r resp
  if [[ ! "$resp" =~ ^[sS]$ ]]; then
    echo "[-] Abortando bastionado de SSH para evitar bloqueo accidental."
    exit 1
  fi
fi

echo "[+] Aplicando directivas de SSH Hardening en /etc/ssh/sshd_config.d/99-soc-hardening.conf..."
mkdir -p /etc/ssh/sshd_config.d/
cat > /etc/ssh/sshd_config.d/99-soc-hardening.conf << 'SSHCONF'
# === [ HOME SOC ] Hardening Estricto de OpenSSH ===
# 1. Prohibir login directo como superusuario (root)
PermitRootLogin no

# 2. Deshabilitar completamente la autenticación por contraseña
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no

# 3. Forzar autenticación exclusiva por clave pública moderna
PubkeyAuthentication yes

# 4. Restricciones de intentos y tiempos de sesión
MaxAuthTries 3
LoginGraceTime 30
MaxSessions 4

# 5. Seguridad de sesión
X11Forwarding no
PermitEmptyPasswords no
ClientAliveInterval 300
ClientAliveCountMax 2

# 6. Algoritmos de cifrado y MACs robustos
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
SSHCONF

# Permisos correctos para authorized_keys y ssh
chmod 700 "$TARGET_HOME/.ssh" 2>/dev/null || true
chmod 600 "$AUTH_KEYS" 2>/dev/null || true
chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.ssh" 2>/dev/null || true

# Testear configuración de sshd antes de reiniciar
if sshd -t; then
  systemctl restart ssh || systemctl restart sshd
  echo "✅ SSH bastionada correctamente (Root bloqueado, contraseña desactivada)."
else
  echo "[-] Error en sintaxis de sshd. Revisa la configuración."
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. HARDENING DE KERNEL (SYSCTL)
# ─────────────────────────────────────────────────────────────────────────────
echo "[+] 2. Aplicando endurecimiento de parámetros de red y kernel..."

cat > /etc/sysctl.d/99-soc-hardening.conf << 'SYSCTLCONF'
# Habilitar reenvío de paquetes IP para WireGuard y redes Docker
net.ipv4.ip_forward = 1

# Protección anti-spoofing (Reverse Path Filtering en modo loose=2 para compatibilidad con WireGuard y Docker)
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2

# Protección contra ataques SYN Flood
net.ipv4.tcp_syncookies = 1

# Ignorar paquetes ICMP broadcast y ecos inválidos
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Prohibir redirecciones ICMP (evitar ataques Man-in-the-Middle)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Prohibir enrutamiento en origen (Source Routing)
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Registrar paquetes con direcciones sospechosas o imposibles (Martian packets)
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Proteger volcados y punteros de memoria
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
SYSCTLCONF

sysctl --system > /dev/null
echo "✅ Parámetros de kernel protegidos."

# ─────────────────────────────────────────────────────────────────────────────
# 3. ACTUALIZACIONES DE SEGURIDAD AUTOMÁTICAS
# ─────────────────────────────────────────────────────────────────────────────
echo "[+] 3. Configurando actualizaciones de seguridad desatendidas (unattended-upgrades)..."
apt-get update -qq
apt-get install -y -qq unattended-upgrades ufw fail2ban > /dev/null

cat > /etc/apt/apt.conf.d/20auto-upgrades << 'APTCONF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APTCONF
echo "✅ Actualizaciones de seguridad automáticas activadas."

# ─────────────────────────────────────────────────────────────────────────────
# 4. FIREWALL UFW (Por Rol)
# ─────────────────────────────────────────────────────────────────────────────
echo "[+] 4. Configurando Firewall UFW..."

ufw --force reset > /dev/null
ufw default deny incoming
ufw default allow outgoing

# Limitar intentos de conexión a SSH (anti fuerza bruta)
ufw limit 22/tcp comment "SSH con rate-limiting"

# Reglas específicas según el rol
case "$ROLE" in
  master)
    echo "    -> Aplicando perfil NODO 1 (Master Gateway)..."
    ufw allow 53 comment "AdGuard DNS"
    ufw allow 51820/udp comment "WireGuard VPN"
    ufw allow 8080/tcp comment "CrowdSec LAPI"
    ufw allow 8085/tcp comment "AdGuard Web GUI"
    ufw allow 51821/tcp comment "WireGuard Web GUI"
    ufw allow 3001/tcp comment "Uptime Kuma"
    ufw allow 8082/tcp comment "Homepage Dashboard"
    ;;
  backup)
    echo "    -> Aplicando perfil NODO 2 (Backup DNS)..."
    ufw allow 53 comment "AdGuard Backup DNS"
    ufw allow 5335 comment "Unbound DNS Resolver"
    ufw allow 8085/tcp comment "AdGuard Web GUI"
    ;;
  decoy)
    echo "    -> Aplicando perfil NODO 3 (Honeypot Decoy)..."
    ufw allow 80/tcp comment "Decoy Web"
    ufw allow 2222/tcp comment "Decoy Fake SSH"
    ufw allow 445/tcp comment "Decoy Fake SMB"
    ufw allow 21/tcp comment "Decoy Fake FTP"
    ufw allow 3306/tcp comment "Decoy Fake MySQL"
    ufw allow 6379/tcp comment "Decoy Fake Redis"
    ;;
  *)
    echo "    -> Rol no especificado. Solo SSH queda abierto en UFW."
    ;;
esac

ufw --force enable > /dev/null
echo "✅ Firewall UFW configurado y habilitado."

echo "======================================================================"
echo "🎉 [ BASTIONADO COMPLETADO ] El nodo está seguro y protegido."
echo "======================================================================"
