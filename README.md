# 🛡️ [ HOME SOC ] — Centro de Operaciones de Seguridad Doméstico

Arquitectura distribuida en **3 Nodos (Cluster de Raspberry Pis)** para ciberdefensa perimetral, bloqueo de telemetría/anuncios, resolución DNSSEC recursiva con alta disponibilidad, VPN WireGuard y honeypots trampa en red local.

---

## 🗺️ 1. Topología del Cluster (3 Nodos)

```
                                      [ ROUTER / INTERNET ]
                                                │
         ┌──────────────────────────────────────┼──────────────────────────────────────┐
         ▼ (Cable Ethernet)                     ▼ (Cable Ethernet)                     ▼ (WiFi / Inalámbrico)
 ┌──────────────────────────────┐       ┌──────────────────────────────┐       ┌──────────────────────────────┐
 │   NODO 1: RASPBERRY PI 4     │       │   NODO 2: RASPBERRY PI 3     │       │   NODO 3: RPI ZERO 2 W       │
 │   (2 GB RAM - MASTER GATEWAY)│       │   (1 GB RAM - HA BACKUP & SL)│       │   (512 MB - STEALTH DECOY)   │
 ├──────────────────────────────┤       ├──────────────────────────────┤       ├──────────────────────────────┤
 │ 🛡️ AdGuard Home (Master :53) │ ───>  │ 🛡️ AdGuard Home (Backup :53) │       │ 🍯 OpenCanary (LAN Honeypot) │
 │ 🌐 Unbound (Root DNSSEC)     │       │ 🌐 Unbound (Root DNSSEC)     │       │    • SSH falso (:2222)       │
 │ 🔑 WireGuard (wg-easy VPN)   │       │ 🔄 AdGuard-Sync (Auto-replica│       │    • Windows SMB falso (:445)│
 │ 🧠 CrowdSec Central (LAPI)   │ <───  │ 📡 CrowdSec Agent + Bouncer  │ <───  │    • Panel Web falso (:80)   │
 │ 📊 Uptime Kuma (Alertas)     │  logs │                              │  logs │ 📡 CrowdSec Agent (Sensor)   │
 │ 🖥️ Homepage (Dashboard SOC)  │       │                              │       │                              │
 ├──────────────────────────────┤       ├──────────────────────────────┤       ├──────────────────────────────┤
 │ RAM: ~380 MB / 2.0 GB (19%)  │       │ RAM: ~260 MB / 1.0 GB (26%)  │       │ RAM: ~110 MB / 512 MB (21%)  │
 └──────────────────────────────┘       └──────────────────────────────┘       └──────────────────────────────┘
```

---

## 📦 2. Estructura del Proyecto

```
rpi-homesoc/
├── node1-rpi4-master/             # Configuración del Nodo 1 (RPi 4 Master)
│   ├── docker-compose.yml
│   ├── .env.example
│   ├── unbound/unbound.conf
│   └── homepage/config/           # Dashboard central unificado
├── node2-rpi3-backup/             # Configuración del Nodo 2 (RPi 3 Backup)
│   ├── docker-compose.yml
│   ├── .env.example
│   └── unbound/unbound.conf
├── node3-rpizero-decoy/           # Configuración del Nodo 3 (RPi Zero 2 W Honeypot)
│   ├── docker-compose.yml
│   ├── .env.example
│   └── opencanary/opencanary.conf
└── scripts/                       # Scripts de puesta a punto
    ├── install-docker.sh          # Instalación de Docker y Docker Compose
    ├── setup-cgroups.sh           # Habilitar cgroups de memoria
    └── setup-zram.sh              # Swap comprimido en RAM
```

---

## 🚀 3. Guía de Instalación Rápida

### Paso 0: Preparación de las MicroSD (Raspberry Pi OS Lite 64-bit)
1. Graba **Raspberry Pi OS Lite (64-bit)** en las 3 tarjetas MicroSD mediante *Raspberry Pi Imager*.
2. Configura nombre de host, usuario, contraseña y activa SSH.

### Paso 1: Optimización de Kernel en los 3 Nodos
En cada Raspberry Pi, ejecuta los scripts de preparación:
```bash
# 1. Habilitar cgroups de memoria para Docker
curl -sSL https://raw.githubusercontent.com/.../scripts/setup-cgroups.sh | bash
sudo reboot

# 2. Instalar Docker oficial
./scripts/install-docker.sh

# 3. (Recomendado en RPi 3 y RPi Zero) Activar ZRAM
./scripts/setup-zram.sh
```

---

### Paso 2: Despliegue del Nodo 1 (Raspberry Pi 4 - Master)
```bash
cd node1-rpi4-master
cp .env.example .env
# Edita .env con tus contraseñas y dominio DDNS
docker compose up -d
```
- **Panel Homepage**: `http://192.168.1.2:8082`
- **AdGuard Home**: `http://192.168.1.2:8085` (Configurar upstream a `127.0.0.1:5335`)
- **WireGuard Web**: `http://192.168.1.2:51821`
- **Uptime Kuma**: `http://192.168.1.2:3001`

---

### Paso 3: Despliegue del Nodo 2 (Raspberry Pi 3 - Backup)
```bash
cd node2-rpi3-backup
cp .env.example .env
docker compose up -d
```
- **AdGuard Home Secundario**: `http://192.168.1.3:8085`
- `adguard-sync` en el Nodo 1 replicará automáticamente todas las listas, clientes y reglas hacia el Nodo 2.

---

### Paso 4: Despliegue del Nodo 3 (Raspberry Pi Zero 2 W - Honeypot)
```bash
cd node3-rpizero-decoy
cp .env.example .env
docker compose up -d
```
- El honeypot **OpenCanary** abrirá trampas silenciosas en los puertos 80, 2222, 445, 21, 6379 y 3306.
- Cualquier intento de escaneo en la red local será registrado y enviado al LAPI del Nodo 1 para banear al atacante.

---

### Paso 5: Configuración del Router Doméstico
En la configuración DHCP de tu router de casa:
- **Servidor DNS Primario**: `192.168.1.2` (RPi 4)
- **Servidor DNS Secundario**: `192.168.1.3` (RPi 3)

Si el Nodo 1 se reinicia o se apaga, toda la casa continuará navegando y filtrando amenazas a través del Nodo 2 de forma instantánea y transparente.

---

## 🔒 4. Licencia
Proyecto libre bajo licencia **MIT License**. Consulta el archivo [LICENSE](LICENSE) para más detalles.
