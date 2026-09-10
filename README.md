# 🛡️ [ HOME SOC ] — Centro de Operaciones de Seguridad Doméstico

Arquitectura distribuida en **3 Nodos (Cluster de Raspberry Pis)** para ciberdefensa perimetral, bloqueo de telemetría y anuncios, resolución DNSSEC recursiva con alta disponibilidad, VPN WireGuard de alto rendimiento, monitorización inteligente de memoria con alertas a Telegram y honeypots trampa en red local.

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
 │ 🔑 WireGuard (wg-easy :51820)│       │ 🔄 AdGuard-Sync (Auto-replica│       │    • Windows SMB falso (:445)│
 │ 🧠 CrowdSec Central (LAPI)   │ <───  │ 📡 CrowdSec Agent + Bouncer  │ <───  │    • Panel Web falso (:80)   │
 │ 📊 Uptime Kuma (Alertas)     │  logs │ 🤖 RAM Guardian (Telegram)   │  logs │ 📡 CrowdSec Agent (Sensor)   │
 │ 🖥️ Homepage (Dashboard SOC)  │       │                              │       │                              │
 │ 🤖 RAM Guardian (Telegram)   │       │                              │       │                              │
 ├──────────────────────────────┤       ├──────────────────────────────┤       ├──────────────────────────────┤
 │ RAM: ~860 MB / 1.84 GB (46%) │       │ RAM: ~326 MB / 905 MB (36%)  │       │ RAM: ~110 MB / 512 MB (21%)  │
 └──────────────────────────────┘       └──────────────────────────────┘       └──────────────────────────────┘
```

---

## 📦 2. Estructura del Proyecto

```
rpi-homesoc/
├── node1-rpi4-master/             # Configuración del Nodo 1 (RPi 4 Master Gateway)
│   ├── docker-compose.yml         # Orquestación de AdGuard, Unbound, WireGuard, CrowdSec, Uptime Kuma, Homepage
│   ├── .env.example               # Plantilla de credenciales y variables de entorno
│   ├── unbound/unbound.conf       # Configuración recursiva raíz y DNSSEC
│   └── homepage/config/           # Cuadro de mando unificado del SOC
├── node2-rpi3-backup/             # Configuración del Nodo 2 (RPi 3 HA Backup)
│   ├── docker-compose.yml         # Orquestación de AdGuard secundario, Unbound y CrowdSec Agent
│   ├── .env.example               # Variables y claves del nodo secundario
│   └── unbound/unbound.conf       # Resolver secundario DNSSEC
├── node3-rpizero-decoy/           # Configuración del Nodo 3 (RPi Zero 2 W Honeypot)
│   ├── docker-compose.yml         # Orquestación de OpenCanary
│   ├── .env.example               # Configuración de red y CrowdSec
│   └── opencanary/                # Configuración y formateador de alertas Telegram
└── scripts/                       # Herramientas de automatización y bastionado
    ├── install-docker.sh          # Instalación oficial de Docker y Compose
    ├── setup-cgroups.sh           # Habilitar cgroups de memoria en kernel
    ├── setup-zram.sh              # Swap comprimido en RAM (zram)
    ├── harden-node.sh             # Bastionado estricto SSH, firewall UFW y sysctl
    ├── ram-guardian.sh            # Guardián inteligente de memoria y auto-remediación
    └── soc-bot.py                 # Bot interactivo de Telegram con teclado táctil y telemetría
```

---

## 🚀 3. Guía de Instalación y Despliegue

### Paso 0: Preparación de las MicroSD (Raspberry Pi OS Lite 64-bit)
1. Graba **Raspberry Pi OS Lite (64-bit)** en las tarjetas MicroSD mediante *Raspberry Pi Imager*.
2. Configura nombre de host (`NODO1`, `NODO2`, `NODO3`), usuario, contraseña y activa la autenticación SSH por clave pública.

### Paso 1: Optimización de Kernel y Bastionado
En cada Raspberry Pi, ejecuta los scripts de preparación:
```bash
# 1. Habilitar cgroups de memoria para Docker
curl -sSL https://raw.githubusercontent.com/.../scripts/setup-cgroups.sh | bash
sudo reboot

# 2. Instalar Docker oficial
./scripts/install-docker.sh

# 3. Activar ZRAM (Swap ultrarrápida comprimida en memoria)
./scripts/setup-zram.sh

# 4. Aplicar bastionado de seguridad (UFW, SSH y sysctl)
# En Nodo 1:
sudo ./scripts/harden-node.sh master
# En Nodo 2:
sudo ./scripts/harden-node.sh backup
```

---

### Paso 2: Despliegue del Nodo 1 (Raspberry Pi 4 - Master Gateway)
```bash
cd node1-rpi4-master
cp .env.example .env
# Edita .env con tus contraseñas, dominio DDNS y token de Telegram
nano .env
docker compose up -d
```
- **Panel Homepage**: `http://192.168.1.40:8082`
- **AdGuard Home (Master)**: `http://192.168.1.40:8085` (Upstream a `127.0.0.1:5335`)
- **WireGuard Web UI**: `http://192.168.1.40:51821`
- **Uptime Kuma**: `http://192.168.1.40:3001`
- **CrowdSec LAPI**: `http://192.168.1.40:8080`

---

### Paso 3: Despliegue del Nodo 2 (Raspberry Pi 3 - Backup DNS)
```bash
cd node2-rpi3-backup
cp .env.example .env
nano .env
docker compose up -d
```
- **AdGuard Home Secundario**: `http://192.168.1.39:8085`
- `adguard-sync` en el Nodo 1 replicará automáticamente en tiempo real todas las listas de bloqueo, reglas personalizadas y clientes hacia el Nodo 2.

---

### Paso 4: Despliegue del Nodo 3 (Raspberry Pi Zero 2 W - Honeypot Señuelo)
```bash
cd node3-rpizero-decoy
cp .env.example .env
docker compose up -d
```
- El honeypot **OpenCanary** abrirá puertos trampa silenciosos (80, 2222, 445, 21, 6379, 3306).
- Cualquier escaneo en la red local enviará una alerta instantánea y legible a Telegram y reportará al LAPI central de CrowdSec para bloquear la IP agresora.

---

### Paso 5: Configuración del Router Doméstico
En el panel de administración de tu router (habitualmente `http://192.168.1.1`):

1. **DNS en DHCP**:
   * **Servidor DNS Primario**: `192.168.1.40` (Nodo 1 - RPi 4)
   * **Servidor DNS Secundario**: `192.168.1.39` (Nodo 2 - RPi 3)
   > [!TIP]
   > Si el Nodo 1 se reinicia o se apaga, toda la red continuará navegando y bloqueando anuncios a través del Nodo 2 de forma transparente e instantánea.

2. **Reenvío de Puertos (Port Forwarding)**:
   * **Puerto Externo / Interno**: `51820` (Protocolo **UDP**)
   * **IP de Destino**: `192.168.1.40` (Nodo 1)

---

## 🔑 4. WireGuard VPN (`wg-easy`): Configuración y Optimización

El Nodo 1 gestiona el acceso VPN seguro mediante `wg-easy`, permitiendo conectarte a tu casa desde redes móviles (4G/5G) o redes WiFi externas con cifrado robusto y filtrado AdGuard en todo el dispositivo.

### Claves de Configuración para Máxima Estabilidad

| Parámetro | Valor Óptimo | Motivo Técnico |
| :--- | :--- | :--- |
| **`WG_HOST` (`DDNS_DOMAIN`)** | `tu-dominio.duckdns.org` o IP Pública | **Obligatorio para conexión exterior.** Si se usa una IP local (`192.168.1.x`), los móviles fuera de casa no pueden resolver la ruta y la conexión falla por completo. |
| **`WG_MTU`** | `1280` | **Previene el "PMTUD Black Hole"**. En redes 4G/5G y fibra PPPoE, el MTU por defecto (1420) supera el tamaño máximo del paquete con las cabeceras WireGuard, provocando que la navegación se congele o dé errores de timeout. `1280` es el estándar mínimo IPv6 garantizado libre de fragmentación. |
| **`WG_PERSISTENT_KEEPALIVE`**| `25` | Mantiene abierta la tabla de estados NAT en operadores móviles y CG-NAT, evitando que la VPN "se duerma" por inactividad. |
| **`WG_ALLOWED_IPS`** | `0.0.0.0/0, ::/0` | **Full Tunnel**: Enruta todo el tráfico del cliente por la VPN para beneficiarse del bloqueo de anuncios, telemetría y malware de AdGuard Home fuera de casa. *(Usa `192.168.1.0/24, 10.8.0.0/24` si solo deseas acceder a la LAN doméstica)*. |
| **`WG_DEFAULT_DNS`** | `192.168.1.40` | Fuerza al cliente a resolver nombres a través de AdGuard Home en el puerto 53 del Nodo 1. |

> [!WARNING]
> **Pruebas en red local vs 4G/5G:**
> Si tu router no soporta *NAT Loopback* (muy habitual en routers Movistar/O2), intentar conectarse al Endpoint público (`2.139.x.x` o DuckDNS) **estando conectado al mismo Wi-Fi de casa fallará**. Para verificar la VPN, **desactiva el Wi-Fi en el móvil y prueba siempre con datos móviles (4G/5G)**.

### Soporte y Uso en macOS
En macOS, la app oficial de WireGuard opera como un accesorio de sistema (`LSUIElement`):
* **No aparece en el Dock** ni abre una ventana central al hacer clic en el ejecutable.
* Su interfaz vive en la **barra superior de menús** (arriba a la derecha, junto al reloj y Wi-Fi). Haz clic en el icono y selecciona **"Manage Tunnels"** para importar archivos `.conf`.
* Para cerrarla o desbloquear una desinstalación atascada: `killall WireGuard`.

---

## 🤖 5. Monitorización Inteligente de Memoria (`ram-guardian.sh`)

Para garantizar la estabilidad 24/7 en dispositivos con recursos acotados (RPi 4 de 2 GB y RPi 3 de 1 GB), se ha diseñado un servicio guardián en bash sin dependencias pesadas: [`scripts/ram-guardian.sh`](scripts/ram-guardian.sh).

```
   ┌───────────────────────────────────────────────────────────────┐
   │               CRON JOB (Cada 5 minutos)                       │
   └──────────────────────────────┬────────────────────────────────┘
                                  │
                                  ▼
   ┌───────────────────────────────────────────────────────────────┐
   │            Lectura directa de /proc/meminfo y Docker          │
   └──────────────┬───────────────────────────────┬────────────────┘
                  │                               │
       RAM < 82% y Contenedores < 90%   RAM >= 82% o Contenedor >= 90%
                  │                               │
                  ▼                               ▼
          [ MODO SILENCIOSO ]         ┌────────────────────────────┐
             (Cero consumo)           │  Alerta Warning a Telegram │
                                      │  (Cooldown anti-spam 1h)   │
                                      └─────────────┬──────────────┘
                                                    │
                                         Contenedor >= 96% (Fuga)
                                                    │
                                                    ▼
                                      ┌────────────────────────────┐
                                      │    AUTO-REMEDIACIÓN:       │
                                      │  Reinicio automático del   │
                                      │  contenedor + Alerta crítica│
                                      └────────────────────────────┘
```

### Características Principales
1. **Doble Nivel de Vigilancia**:
   * **Nivel Global**: Monitorea el uso de RAM física y swap ZRAM calculando la memoria verdaderamente disponible (`MemAvailable`).
   * **Nivel Contenedor**: Detecta si una aplicación específica está agotando su límite de memoria asignado.
2. **Dimensionamiento Seguro de Contenedores (Docker Limits)**:
   * Los servicios basados en Node.js (`uptime-kuma` a **192M** y `homepage` a **128M**) cuentan con margen suficiente para su recolector de basura V8, evitando caídas imprevistas por *OOM Killer*.
   * La suma total de límites de todos los contenedores se mantiene en ~1 GB, asegurando que el sistema operativo disponga siempre de ~800 MB libres.
3. **Auto-Remediación Inteligente**:
   * Si un contenedor sufre una fuga de memoria y supera el **96%** de su límite asignado, el script ejecuta un reinicio preventivo (`docker restart <container>`) antes de que el kernel congele el sistema, notificando la intervención por Telegram.
4. **Protección Anti-Spam y Recuperación**:
   * Incluye un enfriamiento (*cooldown*) de 1 hora para avisos persistentes.
   * Cuando los niveles vuelven a la normalidad, envía automáticamente una notificación de recuperación confirmada (✅).
5. **Multi-Nodo Automático**:
   * Detecta dinámicamente el host (`NODO1`, `NODO2`), identificando en cada mensaje a qué nodo corresponde el evento.

### Comandos Útiles del Guardián
```bash
# Solicitar un informe de memoria en tiempo real enviado a Telegram:
~/rpi-homesoc/scripts/ram-guardian.sh --report

# Comprobar la programación en crontab:
crontab -l
---

## 📱 6. Bot Interactivo de Telegram (`soc-bot.py`)

El clúster cuenta con un demonio interactivo bidireccional desarrollado en Python nativo (`scripts/soc-bot.py`) que se ejecuta como servicio `systemd` 24/7 en el Nodo 1.

Permite consultar el estado de toda la infraestructura doméstica en tiempo real directamente desde tu móvil, tablet o smartwatch, utilizando un menú táctil de botones (*Inline Keyboards*).

```
┌──────────────────────────────────────────────┐
│  🛡️ [ HOME SOC ] Panel de Control y Estado   │
│                                              │
│  Selecciona una opción:                      │
├──────────────────────┬───────────────────────┤
│  📊 Resumen Clúster  │  🌐 Estadísticas DNS  │
├──────────────────────┼───────────────────────┤
│  🧠 Memoria Nodo 1   │  🧠 Memoria Nodo 2    │
├──────────────────────┼───────────────────────┤
│  🔑 Clientes VPN     │  🛡️ Ciberdefensa & IPS│
├──────────────────────┴───────────────────────┤
│             🔄 Actualizar Menú               │
└──────────────────────────────────────────────┘
```

### Características y Comandos Disponibles

| Botón / Comando | Información Reportada en Tiempo Real |
| :--- | :--- |
| **📊 `Resumen Clúster`** (`/status`) | Estado en vivo de los 3 nodos (RPi 4 Master, RPi 3 Backup, RPi Zero Decoy), latencia ping y número de contenedores activos. |
| **🌐 `Estadísticas DNS`** (`/dns`) | Métricas en vivo de AdGuard Home: consultas totales, anuncios/rastreadores bloqueados (%), latencia media DNSSEC y top dominios bloqueados. |
| **🧠 `Memoria Nodo 1`** (`/nodo1`) | Diagnóstico exacto de RAM física, disponibilidad libre, swap ZRAM y consumo desglosado de cada contenedor en el Nodo 1. |
| **🧠 `Memoria Nodo 2`** (`/nodo2`) | Telemetría remota por SSH del Nodo 2 (RPi 3 Backup DNS) sin exponer puertos adicionales. |
| **🔑 `Clientes VPN`** (`/vpn`) | Lista de peers de WireGuard, detección de conexiones activas en tiempo real, endpoints externos y megabytes transferidos (RX/TX). |
| **🛡️ `Ciberdefensa`** (`/alertas`) | Lista de IPs atacantes baneadas por CrowdSec LAPI y estado de las trampas del Honeypot OpenCanary en la red local. |

### Seguridad y Arquitectura
* **Cero Puertos Expuestos**: Funciona en modo *Long Polling* por HTTPS saliente. No requiere abrir ningún puerto en el router de casa ni disponer de IP pública fija.
* **Control de Acceso Estricto**: Valida el `chat_id` autorizado. Cualquier usuario externo o desconocido que intente interactuar con el bot es rechazado automáticamente.
* **Consumo Mínimo**: Desarrollado con la librería estándar de Python (`urllib.request`), con un consumo inferior a **25 MB de RAM** y 0% de CPU.
* **Servicio Systemd Persistente**:
  ```bash
  # Ver estado del bot en el Nodo 1:
  systemctl --user status home-soc-bot.service

  # Reiniciar el servicio si se desea:
  systemctl --user restart home-soc-bot.service
  ```

---

## 🔒 7. Licencia
Proyecto libre distribuido bajo la licencia **MIT License**. Consulta el archivo [LICENSE](LICENSE) para más detalles.

