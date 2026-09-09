# 🛡️ [ HOME SOC ] — Bastionado (Hardening) y Aislamiento del Honeypot

Este documento responde a las dos principales directivas de seguridad del clúster:
1. **Prevención de Movimiento Lateral desde el Honeypot**.
2. **Bastionado Estricto del Sistema Operativo y SSH en todos los Nodos**.

---

## 🍯 1. Seguridad del Honeypot: ¿Por qué NO pueden saltar a tu red?

Tener miedo a que un atacante "salte" desde un honeypot a tu red local (movimiento lateral) es una **preocupación muy profesional y totalmente legítima**. En ciberseguridad, esa amenaza se neutraliza mediante **Defensa en Profundidad**:

### A. La naturaleza de OpenCanary: Es de "Baja Interacción" (Low-Interaction)
* **No es una máquina virtual real con Linux ni Windows.**
* OpenCanary es un demonio en Python que **únicamente emula los protocolos de red y banners**:
  * Si un atacante intenta conectarse al SSH falso (`:2222`), OpenCanary simula el handshake inicial de SSH, guarda el usuario, contraseña e IP atacante en los logs, y devuelve inmediatamente `Permission denied` o corta la conexión.
  * **No existe una consola bash**, no hay un prompt de comandos, ni se ejecuta ningún binario del atacante.
  * Lo mismo ocurre con el falso SMB (`:445`), falso MySQL (`:3306`) o falso Redis (`:6379`).

### B. Jaula de Contención (Container Hardening)
Incluso en el escenario paranoico de un fallo de seguridad de día cero (0-Day) en el código de Python de OpenCanary:
1. **`security_opt: [no-new-privileges:true]`**: Prohíbe terminantemente elevar privilegios mediante binarios SUID.
2. **`cap_drop: [ALL]`**: Se despoja al contenedor de capacidades de kernel de Linux (no puede interactuar con hardware, ni montar discos, ni manipular tablas de enrutamiento).
3. **`read_only: true`**: El sistema de archivos del contenedor es de solo lectura; un atacante no puede escribir herramientas ni descargar malware.

### C. Aislamiento de Red Unidireccional (Anti-Movimiento Lateral)
Para evitar que el honeypot inicie conexiones hacia tus ordenadores, móviles o NAS en la LAN (`192.168.1.0/24`):
* **El honeypot SOLO recibe tráfico entrante** (es una trampa pasiva).
* Mediante reglas de firewall (`iptables` / `UFW`):
  * **BLOQUEO**: Se descarta (`DROP`) cualquier conexión saliente iniciada desde el honeypot hacia la subred doméstica `192.168.1.0/24`.
  * **ÚNICA EXCEPCIÓN**: Tráfico saliente permitido exclusivamente hacia `192.168.1.2:8080` (la LAPI de CrowdSec para reportar al atacante).
* **Resultado**: Si un atacante intentara hacer un escaneo de red (`nmap`, `ping`, SMB) desde el honeypot hacia tu casa, los paquetes mueren en la tarjeta de red.

---

## 🔒 2. Bastionado de Nodos y SSH (`harden-node.sh`)

Hemos creado un script automatizado en el repositorio:
[`scripts/harden-node.sh`](scripts/harden-node.sh)

Aplica las directivas CIS Benchmark y estándares de seguridad para Raspberry Pi OS:

### A. SSH Blindado al 100%
* ❌ **`PermitRootLogin no`**: Prohibido el login directo como superusuario (`root`).
* ❌ **`PasswordAuthentication no`**: Prohibido el acceso mediante contraseña (inmune a ataques de fuerza bruta o diccionarios).
* ❌ **`KbdInteractiveAuthentication no`**: Desactiva intentos interactivos por teclado.
* ✅ **`PubkeyAuthentication yes`**: Autenticación **exclusiva** mediante claves públicas SSH modernas (Ed25519 o RSA 4096).
* 🛡️ **Cifrado Robusto**: Se fuerzan algoritmos de intercambio de claves modernos (`curve25519-sha256`) y cifrados autenticados (`chacha20-poly1305`, `aes256-gcm`).
* ⏱️ **Límites de Conexión**: `MaxAuthTries 3` y `LoginGraceTime 30`.

> **Mecanismo de Seguridad Anti-Bloqueo**: El script verifica automáticamente que tengas al menos una clave pública copiada en `~/.ssh/authorized_keys`. Si no la tienes, te avisa y no desactiva las contraseñas para que no pierdas el acceso accidentalmente.

### B. Endurecimiento de Kernel (`/etc/sysctl.d/99-soc-hardening.conf`)
* **Anti-Spoofing**: `net.ipv4.conf.all.rp_filter = 1` (descarta paquetes con IPs de origen falsificadas).
* **Anti-SYN Flood**: `net.ipv4.tcp_syncookies = 1` (protección contra saturación TCP).
* **Anti-MITM / ICMP Redirects**: `accept_redirects = 0` y `send_redirects = 0` (prohíbe que alguien desvíe el tráfico engañando al kernel).
* **Detección de Paquetes Marcianos**: `log_martians = 1` (registra intentos de inyección de paquetes imposibles).

### C. Firewall UFW con Perfiles por Rol
* Política por defecto: **Denegar todo el tráfico entrante** (`default deny incoming`).
* SSH con limitación de frecuencia (`ufw limit 22/tcp`).
* Apertura estricta únicamente de los puertos necesarios según el nodo (`master`, `backup` o `decoy`).

### D. Parches de Seguridad Automáticos
* Se instala y configura `unattended-upgrades` para que el sistema descargue e instale parches de seguridad de Debian/Raspberry Pi OS de forma desatendida.

---

## 🚀 3. Modo de Uso

En cada una de las Raspberry Pis (RPi 4 y RPi 3), tras haber copiado tu clave pública desde tu ordenador con `ssh-copy-id`:

```bash
# En el Nodo 1 (RPi 4):
sudo ./scripts/harden-node.sh master

# En el Nodo 2 (RPi 3):
sudo ./scripts/harden-node.sh backup
```
