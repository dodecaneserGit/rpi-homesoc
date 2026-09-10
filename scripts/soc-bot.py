#!/usr/bin/env python3
"""
🛡️ [ HOME SOC ] Telegram Interactive Bot Daemon
───────────────────────────────────────────────────────────────────────────────
Bot interactivo bidireccional para consultar el estado del clúster Home SOC:
- Menú táctil con botones interactivos (Inline Keyboards).
- Resumen global del clúster (Nodo 1, Nodo 2 y Nodo 3).
- Memoria RAM detallada y contenedores en tiempo real.
- Estado de clientes WireGuard VPN conectados.
- Estadísticas en vivo de DNS (AdGuard Home + Unbound).
- Alertas de ciberdefensa (CrowdSec IPS y Honeypot OpenCanary).
───────────────────────────────────────────────────────────────────────────────
"""

import os
import sys
import time
import json
import ssl
import subprocess
import urllib.request
import urllib.error

# ─────────────────────────────────────────────────────────────────────────────
# CONFIGURACIÓN Y CREDENCIALES
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ENV_FILE = os.path.join(SCRIPT_DIR, "..", "node1-rpi4-master", ".env")

def load_env(env_path):
    config = {}
    if os.path.exists(env_path):
        with open(env_path, "r") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    config[k.strip()] = v.strip().strip("'\"")
    return config

ENV_VARS = load_env(ENV_FILE)
BOT_TOKEN = ENV_VARS.get("TELEGRAM_BOT_TOKEN") or os.environ.get("TELEGRAM_BOT_TOKEN", "")
chat_id_raw = ENV_VARS.get("TELEGRAM_CHAT_ID") or os.environ.get("TELEGRAM_CHAT_ID", "")
AUTHORIZED_ID = int(chat_id_raw) if chat_id_raw and str(chat_id_raw).isdigit() else None

NODE1_IP = ENV_VARS.get("NODE1_IP", "192.168.1.40")
NODE2_IP = ENV_VARS.get("NODE2_IP", "192.168.1.39")
NODE3_IP = ENV_VARS.get("NODE3_IP", "192.168.1.50")
ADGUARD_USER = ENV_VARS.get("ADGUARD_USER", "admin")
ADGUARD_PASS = ENV_VARS.get("ADGUARD_PASS", "")

SSL_CTX = ssl.create_default_context()

# ─────────────────────────────────────────────────────────────────────────────
# COMUNICACIÓN CON TELEGRAM BOT API
# ─────────────────────────────────────────────────────────────────────────────
def tg_api(endpoint, data=None):
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/{endpoint}"
    req = urllib.request.Request(url)
    req.add_header("Content-Type", "application/json")
    json_data = json.dumps(data).encode("utf-8") if data else None
    try:
        with urllib.request.urlopen(req, data=json_data, timeout=35, context=SSL_CTX) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="ignore")
        if "message is not modified" in err_body:
            return {"ok": True, "result": True}
        print(f"[-] HTTP Error en Telegram ({endpoint}): {err_body}", file=sys.stderr)
        return None
    except Exception as e:
        print(f"[-] Error en llamada a Telegram ({endpoint}): {e}", file=sys.stderr)
        return None

def send_msg(chat_id, text, reply_markup=None):
    payload = {
        "chat_id": chat_id,
        "text": text,
        "parse_mode": "Markdown",
        "disable_web_page_preview": True
    }
    if reply_markup:
        payload["reply_markup"] = reply_markup
    res = tg_api("sendMessage", payload)
    if not res:
        payload.pop("parse_mode", None)
        return tg_api("sendMessage", payload)
    return res

def edit_msg(chat_id, msg_id, text, reply_markup=None):
    payload = {
        "chat_id": chat_id,
        "message_id": msg_id,
        "text": text,
        "parse_mode": "Markdown",
        "disable_web_page_preview": True
    }
    if reply_markup:
        payload["reply_markup"] = reply_markup
    res = tg_api("editMessageText", payload)
    if not res:
        payload.pop("parse_mode", None)
        return tg_api("editMessageText", payload)
    return res

def answer_callback(cb_id, text=None):
    payload = {"callback_query_id": cb_id}
    if text:
        payload["text"] = text
    return tg_api("answerCallbackQuery", payload)

# ─────────────────────────────────────────────────────────────────────────────
# TECLADO INTERACTIVO (INLINE KEYBOARD)
# ─────────────────────────────────────────────────────────────────────────────
def get_main_keyboard():
    return {
        "inline_keyboard": [
            [
                {"text": "📊 Resumen Clúster", "callback_data": "cluster_summary"},
                {"text": "🌐 Estadísticas DNS", "callback_data": "dns_stats"}
            ],
            [
                {"text": "🧠 Memoria Nodo 1", "callback_data": "mem_n1"},
                {"text": "🧠 Memoria Nodo 2", "callback_data": "mem_n2"}
            ],
            [
                {"text": "🔑 Clientes VPN", "callback_data": "vpn_status"},
                {"text": "🛡️ Ciberdefensa & IPS", "callback_data": "security_alerts"}
            ],
            [
                {"text": "🔄 Actualizar Menú", "callback_data": "menu"}
            ]
        ]
    }

def get_back_keyboard():
    return {
        "inline_keyboard": [
            [
                {"text": "« Volver al Menú Principal", "callback_data": "menu"}
            ]
        ]
    }

# ─────────────────────────────────────────────────────────────────────────────
# RECOLECTORES DE INFORMACIÓN DEL CLÚSTER
# ─────────────────────────────────────────────────────────────────────────────
def run_cmd(cmd, timeout=10):
    try:
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        return res.stdout.strip()
    except Exception as e:
        return f"Error: {e}"

def ping_host(host):
    out = run_cmd(f"ping -c 1 -W 1 {host} 2>/dev/null", timeout=2)
    if "1 received" in out or "1 packets received" in out:
        try:
            time_ms = out.split("time=")[1].split(" ")[0]
            return True, f"{float(time_ms):.1f} ms"
        except:
            return True, "<1 ms"
    return False, "Offline"

def get_cluster_summary():
    # Ping a los 3 nodos
    n1_ok, n1_lat = True, "Local"
    n2_ok, n2_lat = ping_host(NODE2_IP)
    n3_ok, n3_lat = ping_host(NODE3_IP)

    # Contenedores en Nodo 1
    n1_running = run_cmd("docker ps -q | wc -l").strip()
    n1_total = run_cmd("docker ps -a -q | wc -l").strip()

    # Contenedores en Nodo 2 via SSH
    n2_running = run_cmd(f"ssh -o ConnectTimeout=2 {NODE2_IP} 'docker ps -q | wc -l' 2>/dev/null").strip() or "?"
    n2_total = run_cmd(f"ssh -o ConnectTimeout=2 {NODE2_IP} 'docker ps -a -q | wc -l' 2>/dev/null").strip() or "?"

    # Uptime Nodo 1
    uptime_raw = run_cmd("uptime -p").replace("up ", "")

    n1_icon = "🟢" if n1_ok else "🔴"
    n2_icon = "🟢" if n2_ok else "🔴"
    n3_icon = "🟢" if n3_ok else "🔴"

    msg = f"""📊 *[ HOME SOC ] Resumen Global del Clúster*
━━━━━━━━━━━━━━━━━━━━━━━━━━
{n1_icon} *NODO 1: RPi 4 (Master Gateway)*
• Estado: *Online* ({n1_lat}) | Uptime: {uptime_raw}
• Contenedores: `{n1_running}/{n1_total}` activos
• Servicios: AdGuard Master, Unbound, WireGuard, CrowdSec LAPI

{n2_icon} *NODO 2: RPi 3 (HA Backup DNS)*
• Estado: *{'Online' if n2_ok else 'Offline'}* ({n2_lat})
• Contenedores: `{n2_running}/{n2_total}` activos
• Servicios: AdGuard Backup (:53), Unbound, CrowdSec Sensor

{n3_icon} *NODO 3: RPi Zero 2 W (Honeypot Decoy)*
• Estado: *{'Online' if n3_ok else 'Offline'}* ({n3_lat})
• Trampas: SSH (:2222), HTTP (:80), SMB (:445)
• Función: Detección temprana de intrusiones en LAN

🛡️ *Diagnóstico:* Clúster operativo y coordinado."""
    return msg

def get_memory_info(target="local"):
    ssh_prefix = "" if target == "local" else f"ssh -o ConnectTimeout=3 {NODE2_IP} "
    node_label = "NODO 1 (RPi 4 Master)" if target == "local" else "NODO 2 (RPi 3 Backup)"
    
    raw_mem = run_cmd(f"{ssh_prefix}cat /proc/meminfo")
    mem = {}
    for line in raw_mem.split("\n"):
        parts = line.split(":")
        if len(parts) == 2:
            key = parts[0].strip()
            val = parts[1].strip().split(" ")[0]
            try:
                mem[key] = int(val)
            except:
                pass

    total = mem.get("MemTotal", 1) // 1024
    avail = mem.get("MemAvailable", 0) // 1024
    used = total - avail
    pct = (used / total) * 100 if total > 0 else 0
    st = mem.get("SwapTotal", 0) // 1024
    sf = mem.get("SwapFree", 0) // 1024
    su = st - sf
    
    if target == "local":
        raw_stats = run_cmd("docker stats --no-stream --format '{{.Name}}|{{.MemUsage}}|{{.MemPerc}}' 2>/dev/null")
    else:
        raw_stats = run_cmd(f"ssh -o ConnectTimeout=3 {NODE2_IP} 'docker stats --no-stream --format \"{{{{.Name}}}}|{{{{.MemUsage}}}}|{{{{.MemPerc}}}}\"' 2>/dev/null")
    
    stats_lines = []
    for s_line in raw_stats.split("\n"):
        if "|" in s_line:
            parts = s_line.split("|")
            if len(parts) >= 3 and parts[0].strip():
                stats_lines.append(f"• `{parts[0].strip()}`: {parts[1].strip()} ({parts[2].strip()})")
    stats = "\n".join(stats_lines)

    msg = f"""🧠 *[ HOME SOC ] Memoria — {node_label}*
━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 *RAM Física:* {used} MB / {total} MB (*{pct:.1f}%*)
🟢 *RAM Disponible:* {avail} MB libres
💾 *ZRAM Swap:* {su} MB / {st} MB

🐳 *Consumo por Contenedor:*
{stats if stats else '• Sin contenedores reportados'}

✅ *Estado de Memoria:* Estable y monitorizado."""
    return msg

def get_dns_stats():
    def fetch_adguard(host, port, user, pwd):
        url = f"http://{host}:{port}/control/stats"
        req = urllib.request.Request(url)
        import base64
        auth = base64.b64encode(f"{user}:{pwd}".encode("utf-8")).decode("ascii")
        req.add_header("Authorization", f"Basic {auth}")
        try:
            with urllib.request.urlopen(req, timeout=3) as r:
                return json.loads(r.read().decode("utf-8"))
        except:
            return None

    s1 = fetch_adguard("172.28.0.3", "80", ADGUARD_USER, ADGUARD_PASS)
    s2 = fetch_adguard(NODE2_IP, "8085", ADGUARD_USER, ADGUARD_PASS)

    def parse_stats(s):
        if not s:
            return "• Estado: *Inaccesible / Offline*"
        total = s.get("num_dns_queries", 0)
        blocked = s.get("num_blocked_filtering", 0)
        pct = (blocked / total * 100) if total > 0 else 0
        avg_time = s.get("avg_processing_time", 0) * 1000
        return f"• Consultas: *{total:,}*\n• Bloqueadas: *{blocked:,} ({pct:.1f}%)*\n• Latencia DNSSEC: *{avg_time:.1f} ms*"

    top_blocked = ""
    if s1 and s1.get("top_blocked_domains"):
        top_list = []
        for item in s1["top_blocked_domains"][:4]:
            for domain, count in item.items():
                top_list.append(f"  - `{domain}` ({count})")
        top_blocked = "\n".join(top_list)

    msg = f"""🌐 *[ HOME SOC ] Métricas de DNS (AdGuard + Unbound)*
━━━━━━━━━━━━━━━━━━━━━━━━━━
🛡️ *Nodo 1 (Servidor Primario :53)*:
{parse_stats(s1)}

🛡️ *Nodo 2 (Servidor Backup HA :53)*:
{parse_stats(s2)}

🚫 *Top Amenazas y Rastreadores Bloqueados:*
{top_blocked if top_blocked else '  - Sin bloqueos recientes registrados'}

🔒 *Validación DNSSEC:* Activa recursiva en localhost:5335."""
    return msg

def get_vpn_status():
    dump = run_cmd("docker exec wg-easy wg show wg0 dump 2>/dev/null")
    cfg_json = run_cmd("docker exec wg-easy cat /etc/wireguard/wg0.json 2>/dev/null")
    
    clients_map = {}
    if cfg_json:
        try:
            data = json.loads(cfg_json)
            for cid, c in data.get("clients", {}).items():
                clients_map[c.get("publicKey")] = c.get("name", "Desconocido")
        except:
            pass

    clients_info = []
    lines = dump.strip().split("\n") if dump else []
    for line in lines[1:]:
        parts = line.split("\t")
        if len(parts) >= 6:
            pubkey = parts[0]
            endpoint = parts[2]
            allowed_ip = parts[3]
            handshake = int(parts[4])
            rx = int(parts[5])
            tx = int(parts[6])

            name = clients_map.get(pubkey, pubkey[:8] + "...")
            if handshake > 0:
                elapsed = int(time.time()) - handshake
                if elapsed < 180:
                    status = "🟢 *Conectado ahora*"
                else:
                    status = f"⚪ Último visto hace {elapsed // 60} min"
            else:
                status = "⚪ Nunca conectado"

            rx_mb = rx / (1024 * 1024)
            tx_mb = tx / (1024 * 1024)

            clients_info.append(
                f"• 👤 *{name}* ({allowed_ip})\n"
                f"  - Estado: {status}\n"
                f"  - Endpoint: `{endpoint if endpoint != '(none)' else 'Sin conexión'}`\n"
                f"  - Tráfico: ⬇️ {rx_mb:.2f} MB | ⬆️ {tx_mb:.2f} MB"
            )

    msg = f"""🔑 *[ HOME SOC ] Clientes WireGuard VPN*
━━━━━━━━━━━━━━━━━━━━━━━━━━
Puerto de escucha: `51820/UDP` (MTU 1280, Keepalive 25s)

{chr(10).join(clients_info) if clients_info else '• No hay clientes dados de alta en WireGuard'}

💡 *Tip:* Toda la navegación pasa cifrada y filtrada por AdGuard Home."""
    return msg

def get_security_alerts():
    decisions_raw = run_cmd("docker exec crowdsec cscli decisions list -o json 2>/dev/null")
    alerts_raw = run_cmd("docker exec crowdsec cscli alerts list -l 3 -o json 2>/dev/null")

    bans_count = 0
    bans_text = "• Ninguna IP atacante baneada actualmente (Todo tranquilo)."
    try:
        decisions = json.loads(decisions_raw) if decisions_raw else []
        if decisions:
            bans_count = len(decisions)
            bans_list = []
            for d in decisions[:3]:
                bans_list.append(f"  - 🚫 `{d.get('value')}` ({d.get('scenario')}) por {d.get('duration')}")
            bans_text = "\n".join(bans_list)
    except:
        pass

    recent_alerts = []
    try:
        alerts = json.loads(alerts_raw) if alerts_raw else []
        for a in alerts[:3]:
            recent_alerts.append(f"  - ⚠️ `{a.get('source', {}).get('ip')}`: {a.get('scenario')} ({a.get('created_at')[:19]})")
    except:
        pass

    msg = f"""🛡️ *[ HOME SOC ] Ciberdefensa & CrowdSec IPS*
━━━━━━━━━━━━━━━━━━━━━━━━━━
🧠 *Baneos Activos (LAPI Central)*:
{bans_text}

🚨 *Últimas Alertas Registradas:*
{chr(10).join(recent_alerts) if recent_alerts else '  - No se registran incidentes recientes.'}

🍯 *Honeypot OpenCanary (Trampa LAN)*:
• Puertos señuelo: `:2222` (SSH), `:80` (Web), `:445` (SMB)
• Los intentos de escaneo en la red local reportan automáticamente al LAPI para neutralizar al atacante."""
    return msg

# ─────────────────────────────────────────────────────────────────────────────
# BUCLE PRINCIPAL DE LONG POLLING (getUpdates)
# ─────────────────────────────────────────────────────────────────────────────
def main():
    if not BOT_TOKEN or not AUTHORIZED_ID:
        print("[-] Error: TELEGRAM_BOT_TOKEN y TELEGRAM_CHAT_ID deben estar definidos en .env", file=sys.stderr)
        sys.exit(1)
    print("[+] 🤖 Iniciando demonio del Bot de Telegram de Home SOC...")
    offset = 0
    
    # Enviar mensaje de inicialización
    welcome_text = (
        "🛡️ *[ HOME SOC ] Bot Interactivo Conectado*\n"
        "━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
        "El clúster está listo. Pulsa cualquier botón o escribe `/menu` para consultar información en tiempo real:"
    )
    send_msg(AUTHORIZED_ID, welcome_text, get_main_keyboard())

    while True:
        try:
            updates = tg_api(f"getUpdates?offset={offset}&timeout=25")
            if not updates or not updates.get("ok"):
                time.sleep(2)
                continue

            for u in updates.get("result", []):
                offset = u["update_id"] + 1

                # 1. Procesar pulsar botones (Callback Query)
                if "callback_query" in u:
                    cb = u["callback_query"]
                    cb_id = cb["id"]
                    user_id = cb.get("from", {}).get("id")
                    data = cb.get("data")
                    msg_id = cb.get("message", {}).get("message_id")
                    chat_id = cb.get("message", {}).get("chat", {}).get("id")

                    if user_id != AUTHORIZED_ID:
                        answer_callback(cb_id, "⛔ Acceso denegado.")
                        continue

                    answer_callback(cb_id)

                    if data == "menu":
                        edit_msg(chat_id, msg_id, welcome_text, get_main_keyboard())
                    elif data == "cluster_summary":
                        edit_msg(chat_id, msg_id, get_cluster_summary(), get_back_keyboard())
                    elif data == "dns_stats":
                        edit_msg(chat_id, msg_id, get_dns_stats(), get_back_keyboard())
                    elif data == "mem_n1":
                        edit_msg(chat_id, msg_id, get_memory_info("local"), get_back_keyboard())
                    elif data == "mem_n2":
                        edit_msg(chat_id, msg_id, get_memory_info("node2"), get_back_keyboard())
                    elif data == "vpn_status":
                        edit_msg(chat_id, msg_id, get_vpn_status(), get_back_keyboard())
                    elif data == "security_alerts":
                        edit_msg(chat_id, msg_id, get_security_alerts(), get_back_keyboard())

                # 2. Procesar mensajes de texto escritos
                elif "message" in u:
                    m = u["message"]
                    user_id = m.get("from", {}).get("id")
                    chat_id = m.get("chat", {}).get("id")
                    text = m.get("text", "").strip().lower()

                    if user_id != AUTHORIZED_ID:
                        send_msg(chat_id, "⛔ *Acceso Denegado:* Este bot de seguridad es estrictamente privado.")
                        continue

                    if text in ["/start", "/menu", "menu", "hola", "inicio"]:
                        send_msg(chat_id, welcome_text, get_main_keyboard())
                    elif text in ["/status", "/resumen", "status", "resumen"]:
                        send_msg(chat_id, get_cluster_summary(), get_main_keyboard())
                    elif text in ["/dns", "dns"]:
                        send_msg(chat_id, get_dns_stats(), get_main_keyboard())
                    elif text in ["/nodo1", "/ram1", "nodo1"]:
                        send_msg(chat_id, get_memory_info("local"), get_main_keyboard())
                    elif text in ["/nodo2", "/ram2", "nodo2"]:
                        send_msg(chat_id, get_memory_info("node2"), get_main_keyboard())
                    elif text in ["/vpn", "vpn", "wireguard"]:
                        send_msg(chat_id, get_vpn_status(), get_main_keyboard())
                    elif text in ["/alertas", "/seguridad", "alertas", "seguridad"]:
                        send_msg(chat_id, get_security_alerts(), get_main_keyboard())
                    else:
                        send_msg(chat_id, "❓ Comando no reconocido. Usa los botones del menú:", get_main_keyboard())

        except Exception as e:
            print(f"[-] Excepción en bucle principal: {e}", file=sys.stderr)
            time.sleep(3)

if __name__ == "__main__":
    main()
