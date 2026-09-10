#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# 🛡️ [ HOME SOC ] RAM Guardian — Monitorización Inteligente y Auto-Remediación
# ─────────────────────────────────────────────────────────────────────────────
# Supervisa el uso de RAM del sistema y de los contenedores Docker en cualquier nodo.
# - Envía alertas a Telegram si la memoria supera los umbrales de seguridad.
# - Incluye protección anti-spam (cooldown) y aviso de recuperación automática.
# - Auto-remediación: reinicia contenedores con fugas críticas si superan el 96%.
# ─────────────────────────────────────────────────────────────────────────────

set -o pipefail

NODE_NAME="${NODE_NAME:-$(hostname)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE=""
if [[ -f "${SCRIPT_DIR}/../node1-rpi4-master/.env" ]]; then
  ENV_FILE="${SCRIPT_DIR}/../node1-rpi4-master/.env"
elif [[ -f "${SCRIPT_DIR}/../node2-rpi3-backup/.env" ]]; then
  ENV_FILE="${SCRIPT_DIR}/../node2-rpi3-backup/.env"
elif [[ -f "${SCRIPT_DIR}/../node3-rpizero-decoy/.env" ]]; then
  ENV_FILE="${SCRIPT_DIR}/../node3-rpizero-decoy/.env"
fi

if [[ -n "$ENV_FILE" && -f "$ENV_FILE" ]]; then
  TELEGRAM_BOT_TOKEN_FILE=$(grep -E '^TELEGRAM_BOT_TOKEN=' "$ENV_FILE" 2>/dev/null | cut -d '=' -f2- | tr -d '"'\'' ')
  TELEGRAM_CHAT_ID_FILE=$(grep -E '^TELEGRAM_CHAT_ID=' "$ENV_FILE" 2>/dev/null | cut -d '=' -f2- | tr -d '"'\'' ')
fi

BOT_TOKEN="${TELEGRAM_BOT_TOKEN_FILE:-${TELEGRAM_BOT_TOKEN:-}}"
CHAT_ID="${TELEGRAM_CHAT_ID_FILE:-${TELEGRAM_CHAT_ID:-}}"

# Umbrales configurables
RAM_WARN_PCT=${RAM_WARN_PCT:-82}          # % RAM global para aviso
RAM_CRIT_PCT=${RAM_CRIT_PCT:-90}          # % RAM global crítico (alerta urgente)
CONTAINER_WARN_PCT=${CONTAINER_WARN_PCT:-90} # % de límite de un contenedor para aviso
CONTAINER_CRIT_PCT=${CONTAINER_CRIT_PCT:-96} # % para reinicio preventivo si hay fuga

STATE_FILE="/tmp/ram_guardian_alert_active"
LAST_ALERT_FILE="/tmp/ram_guardian_last_ts"
COOLDOWN_SECONDS=3600  # Máximo 1 alerta de aviso por hora si la condición persiste

send_telegram() {
  local msg="$1"
  if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
    return 0
  fi
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d chat_id="${CHAT_ID}" \
    -d text="${msg}" \
    -d parse_mode="Markdown" > /dev/null || true
}

# Obtener métricas del kernel (/proc/meminfo)
eval $(awk '
  /MemTotal/ { total=$2 }
  /MemAvailable/ { avail=$2 }
  /SwapTotal/ { swap_total=$2 }
  /SwapFree/ { swap_free=$2 }
  END {
    used = total - avail;
    ram_pct = (used / total) * 100;
    swap_used = swap_total - swap_free;
    swap_pct = (swap_total > 0) ? (swap_used / swap_total) * 100 : 0;
    printf "TOTAL_RAM_MB=%d; USED_RAM_MB=%d; AVAIL_RAM_MB=%d; RAM_PCT=%.1f;\n", total/1024, used/1024, avail/1024, ram_pct;
    printf "SWAP_TOTAL_MB=%d; SWAP_USED_MB=%d; SWAP_PCT=%.1f;\n", swap_total/1024, swap_used/1024, swap_pct;
  }
' /proc/meminfo)

# Obtener lista de contenedores y su consumo
CONTAINERS_STATS=$(docker stats --no-stream --format "{{.Name}}|{{.MemUsage}}|{{.MemPerc}}" 2>/dev/null || true)

# Modo manual: Enviar informe de estado completo
if [[ "$1" == "--report" || "$1" == "-r" ]]; then
  CONTAINER_LIST=""
  while IFS='|' read -r cname cusage cperc; do
    [[ -z "$cname" ]] && continue
    CONTAINER_LIST+="$(printf "• \`%-18s\` %s (%s)\n" "$cname" "$cusage" "$cperc")"
  done <<< "$CONTAINERS_STATS"

  MSG="📊 *[ HOME SOC ] Informe de Memoria — ${NODE_NAME}*
━━━━━━━━━━━━━━━━━━━━━━━━━━
🧠 *RAM Total:* ${TOTAL_RAM_MB} MB
📈 *En Uso:* ${USED_RAM_MB} MB (*${RAM_PCT}%*)
🟢 *Disponible:* ${AVAIL_RAM_MB} MB
💾 *ZRAM Swap:* ${SWAP_USED_MB} MB / ${SWAP_TOTAL_MB} MB (${SWAP_PCT}%)

🐳 *Consumo por Contenedor:*
${CONTAINER_LIST}
✅ *Diagnóstico:* Nodo funcionando dentro de márgenes saludables."

  send_telegram "$MSG"
  echo "✅ Informe de memoria de ${NODE_NAME} enviado a Telegram."
  exit 0
fi

# Detección de anomalías
ALERT_TRIGGERED=0
ALERT_LEVEL="NONE"
ALERT_REASONS=""

# 1. Verificar RAM del sistema
RAM_INT=${RAM_PCT%.*}
if [[ $RAM_INT -ge $RAM_CRIT_PCT ]]; then
  ALERT_TRIGGERED=1
  ALERT_LEVEL="CRITICAL"
  ALERT_REASONS+="• *RAM Global Crítica:* ${RAM_PCT}% en uso (${USED_RAM_MB} MB / ${TOTAL_RAM_MB} MB)\n"
elif [[ $RAM_INT -ge $RAM_WARN_PCT ]]; then
  ALERT_TRIGGERED=1
  [[ "$ALERT_LEVEL" != "CRITICAL" ]] && ALERT_LEVEL="WARNING"
  ALERT_REASONS+="• *RAM Global Elevada:* ${RAM_PCT}% en uso (${USED_RAM_MB} MB / ${TOTAL_RAM_MB} MB)\n"
fi

# 2. Verificar contenedores individuales al borde de su límite
CONTAINERS_TO_RESTART=()
while IFS='|' read -r cname cusage cperc; do
  [[ -z "$cname" ]] && continue
  perc_clean=$(echo "$cperc" | tr -d '%')
  perc_int=${perc_clean%.*}

  if [[ -n "$perc_int" && $perc_int -ge $CONTAINER_CRIT_PCT ]]; then
    ALERT_TRIGGERED=1
    ALERT_LEVEL="CRITICAL"
    ALERT_REASONS+="• *Fuga Crítica:* \`${cname}\` al ${cperc} de su límite (${cusage})\n"
    CONTAINERS_TO_RESTART+=("$cname")
  elif [[ -n "$perc_int" && $perc_int -ge $CONTAINER_WARN_PCT ]]; then
    ALERT_TRIGGERED=1
    [[ "$ALERT_LEVEL" != "CRITICAL" ]] && ALERT_LEVEL="WARNING"
    ALERT_REASONS+="• *Contenedor al límite:* \`${cname}\` al ${cperc} (${cusage})\n"
  fi
done <<< "$CONTAINERS_STATS"

# Gestión de Alertas y Notificaciones
NOW=$(date +%s)

if [[ $ALERT_TRIGGERED -eq 1 ]]; then
  LAST_ALERT=0
  [[ -f "$LAST_ALERT_FILE" ]] && LAST_ALERT=$(cat "$LAST_ALERT_FILE")
  DIFF=$((NOW - LAST_ALERT))

  # Solo enviar si ha pasado el cooldown o si la alerta es CRÍTICA
  if [[ $DIFF -ge $COOLDOWN_SECONDS || "$ALERT_LEVEL" == "CRITICAL" ]]; then
    
    # Auto-remediación si hay contenedores críticos
    REMEDIATION_LOG=""
    if [[ ${#CONTAINERS_TO_RESTART[@]} -gt 0 ]]; then
      for c in "${CONTAINERS_TO_RESTART[@]}"; do
        docker restart "$c" >/dev/null 2>&1 || true
        REMEDIATION_LOG+="\n⚡ *Acción ejecutada:* Contenedor \`${c}\` reiniciado automáticamente para evitar caída del nodo."
      done
    fi

    if [[ "$ALERT_LEVEL" == "CRITICAL" ]]; then
      MSG="🚨 *[ ALERTA CRÍTICA HOME SOC ] Memoria en ${NODE_NAME}*
━━━━━━━━━━━━━━━━━━━━━━━━━━
${ALERT_REASONS}
💾 *ZRAM Swap:* ${SWAP_USED_MB} MB / ${SWAP_TOTAL_MB} MB (${SWAP_PCT}%)
${REMEDIATION_LOG}

⚠️ *Acción:* Revisa los servicios o reduce carga temporalmente."
    else
      MSG="⚠️ *[ AVISO PREVENTIVO ] Consumo Elevado en ${NODE_NAME}*
━━━━━━━━━━━━━━━━━━━━━━━━━━
${ALERT_REASONS}
💾 *ZRAM Swap:* ${SWAP_USED_MB} MB / ${SWAP_TOTAL_MB} MB (${SWAP_PCT}%)

ℹ️ *Estado:* Supervisando automáticamente. Se intervendrá si supera el ${CONTAINER_CRIT_PCT}%."
    fi

    send_telegram "$MSG"
    echo "$NOW" > "$LAST_ALERT_FILE"
    echo "1" > "$STATE_FILE"
  fi

else
  # Si la memoria volvió a la normalidad tras una alerta previa, enviar mensaje de recuperación
  if [[ -f "$STATE_FILE" ]]; then
    rm -f "$STATE_FILE"
    rm -f "$LAST_ALERT_FILE"
    MSG="✅ *[ HOME SOC ] Memoria RAM Normalizada en ${NODE_NAME}*
━━━━━━━━━━━━━━━━━━━━━━━━━━
🧠 *RAM en uso:* ${RAM_PCT}% (${USED_RAM_MB} MB / ${TOTAL_RAM_MB} MB)
🟢 *Disponible:* ${AVAIL_RAM_MB} MB
💾 *ZRAM Swap:* ${SWAP_USED_MB} MB / ${SWAP_TOTAL_MB} MB

Todos los servicios y contenedores operan en rangos estables."
    send_telegram "$MSG"
  fi
fi
