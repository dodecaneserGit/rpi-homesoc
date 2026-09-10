# 🔐 [ HOME SOC ] — Guía de Configuración de Credenciales (`.env`)

Esta guía detalla para qué sirve cada variable y contraseña requerida en el archivo `.env` del **Nodo 1 (Raspberry Pi 4 Master)** y cómo generarlas correctamente.

---

## 📋 Resumen de Servicios que Requieren Contraseña

| Servicio | Variable en `.env` | Función / Dónde se usa |
|---|---|---|
| **AdGuard Home & Sync** | `ADGUARD_USER`, `ADGUARD_PASS` | Credenciales de administración de AdGuard Home y autenticación de la API para `adguard-sync` hacia la RPi 3. |
| **WireGuard (wg-easy)** | `WG_ADMIN_HASH` | Hash bcrypt para proteger el acceso a la Web UI de WireGuard (`:51821`). |
| **CrowdSec LAPI** | `CROWDSEC_AGENT_PASSWORD` | Token/password de autenticación para el agente CrowdSec del Nodo 2 (RPi 3). |
| **CrowdSec LAPI** | `CROWDSEC_ZERO_PASSWORD` | Token/password de autenticación para el agente CrowdSec del Nodo 3 (Honeypot). |

---

## 🛠️ Detalle por Servicio

### 1. 🛡️ AdGuard Home & Replicación (`adguard-sync`)

```env
ADGUARD_USER=admin
ADGUARD_PASS=TuPasswordSeguraAqui!
```

* **¿Para qué sirve?**
  * La primera vez que arranques AdGuard Home (asistente en el puerto `:3000`), te pedirá crear un usuario y contraseña de administrador.
  * El contenedor **`adguard-sync`** usará exactamente este usuario y contraseña para conectarse a la API de la RPi 4 y replicar de forma automatizada todas las listas de bloqueo, reglas personalizadas y configuración hacia el Nodo 2 (RPi 3).
* **Recomendación:** Usa una contraseña robusta con mayúsculas, minúsculas, números y símbolos.

---

### 2. 🔑 WireGuard Web UI (`wg-easy`)

```env
DDNS_DOMAIN=mi-servidor.duckdns.org
WG_ADMIN_HASH=$$2a$$12$$e8Y6e3fGZqW7Q...
WG_MTU=1280
WG_ALLOWED_IPS=0.0.0.0/0, ::/0
```

* **¿Para qué sirve?**
  * `DDNS_DOMAIN`: Es la dirección a la que se conectarán tus dispositivos (móviles, portátiles) cuando estés fuera de casa. **Debe ser un dominio DDNS público** (ej. DuckDNS gratuito) o tu IP pública. **NUNCA uses una IP local (192.168.1.x)** aquí; de lo contrario tus clientes no podrán conectarse desde datos móviles (4G/5G) ni redes externas.
  * **Puerto en el router**: Es obligatorio abrir/redireccionar el puerto **51820 UDP** en tu router apuntando a la IP del Nodo 1 (ej: `192.168.1.40:51820`).
  * `WG_MTU=1280`: Establece el MTU a 1280 bytes para evitar la fragmentación de paquetes y el bloqueo en redes 4G/5G y fibra PPPoE (evita que la VPN vaya lenta o dé errores de timeout).
  * `WG_ALLOWED_IPS`: `0.0.0.0/0, ::/0` para enrutar todo el tráfico por la VPN (protegido por AdGuard Home) o `192.168.1.0/24, 10.8.0.0/24` si solo quieres acceder a equipos locales.
  * `WG_ADMIN_HASH`: Es la contraseña para acceder a la interfaz web de gestión de WireGuard (`http://192.168.1.40:51821`), donde se dan de alta clientes y se descargan los perfiles VPN o códigos QR.
* **¿Cómo generar el hash bcrypt?**
  * `wg-easy` **no** acepta contraseñas en texto plano por seguridad; requiere un hash bcrypt.
  * Ejecuta el siguiente comando en cualquier terminal con Docker (sustituye `'MiPasswordVPN'` por la contraseña que quieras):
    ```bash
    docker run --rm ghcr.io/wg-easy/wg-easy wgpw 'MiPasswordVPN'
    ```
  * El comando imprimirá una cadena parecida a:
    ```
    PASSWORD_HASH='$2a$12$e8Y6e3fGZqW7QvO9L0...'
    ```
  * ⚠️ **Importante (Docker Compose)**: En los archivos `.env` leídos por Docker Compose, el caracter `$` debe escaparse como doble `$$` para que no sea interpretado como una variable vacía:
    ```env
    WG_ADMIN_HASH=$$2a$$12$$e8Y6e3fGZqW7QvO9L0...
    ```

---

### 3. 🧠 CrowdSec LAPI (Cerebro Central e IPS)

```env
CROWDSEC_AGENT_PASSWORD=ClaveSecretaParaRPi3!
CROWDSEC_ZERO_PASSWORD=ClaveSecretaParaHoneypot!
```

* **¿Para qué sirve?**
  * El Nodo 1 aloja el **servidor central de decisiones (LAPI)** en el puerto `:8080`.
  * La RPi 3 (Nodo 2) y el Honeypot OpenCanary (Nodo 3) actúan como **sensores/agentes remotos**.
  * Estas contraseñas son las credenciales con las que los agentes remotos se autentican contra la LAPI para reportar ataques, escaneos y recibir las listas de bloqueo de IPs.
* **Recomendación:** No necesitas recordarlas de memoria; simplemente inventa dos cadenas largas y seguras y asegúrate de que coincidan con los archivos `.env` de sus respectivos nodos (`node2` y `node3`).

---

## ℹ️ Servicios que NO Requieren Contraseña en `.env`

* **🌐 Unbound (`:5335`)**: Es un resolver DNS recursivo interno que solo escucha consultas DNS desde localhost/Docker; no tiene panel web ni requiere autenticación.
* **📊 Uptime Kuma (`:3001`)**: El usuario y contraseña se configuran interactivamente en el navegador en la primera apertura.
* **🖥️ Homepage (`:8082`)**: Cuadro de mando del SOC de solo lectura dentro de la red local.
