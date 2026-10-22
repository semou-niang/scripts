#!/usr/bin/env bash
set -euo pipefail

# ===========================================
# Linux Server Health Monitor
# Automated diagnostics with color alerts
# ===========================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

WARN_COUNT=0
CRIT_COUNT=0

log_ok() {
    printf "${GREEN}[OK]${NC} %s\n" "$1"
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

log_crit() {
    printf "${RED}[CRIT]${NC} %s\n" "$1"
    CRIT_COUNT=$((CRIT_COUNT + 1))
}
echo "========================================="
echo " Server Health Check Report"
echo " Host: $(hostname)"
echo " Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================="
echo ""

# 1. CPU and Process Check
echo "--- CPU and Process Status ---"
LOAD=$(awk '{print $1}' /proc/loadavg)
CPU_COUNT=$(nproc)

if awk "BEGIN {exit !(${LOAD} > ${CPU_COUNT})}"; then
    log_crit "Load average (${LOAD}) exceeds CPU count (${CPU_COUNT})"
else
    log_ok "Load average (${LOAD}) within capacity (${CPU_COUNT} CPUs)"
fi

HIGH_CPU=$(ps aux --sort=-%cpu | awk 'NR>1 && $3>50 {printf "  PID %s  %s  CPU: %s%%\n", $2, $11, $3}' || true)
if [[ -n "${HIGH_CPU}" ]]; then
    log_crit "High CPU processes detected:"
    echo "${HIGH_CPU}"
else
    log_ok "No processes above 50% CPU"
fi
echo ""
# 2. Disk Space Check
echo "--- Disk Space ---"
DISK_USAGE=$(df / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')

if [[ "${DISK_USAGE}" -gt 90 ]]; then
    log_crit "Root filesystem at ${DISK_USAGE}% usage"
elif [[ "${DISK_USAGE}" -gt 75 ]]; then
    log_warn "Root filesystem at ${DISK_USAGE}% usage"
else
    log_ok "Root filesystem at ${DISK_USAGE}% usage"
fi

LARGE_FILES=$(find /var/log /tmp -type f -size +50M 2>/dev/null || true)
if [[ -n "${LARGE_FILES}" ]]; then
    log_warn "Large files found (>50MB):"
    echo "${LARGE_FILES}" | while IFS= read -r f; do
        SIZE=$(du -h "$f" | awk '{print $1}')
        printf "  %s (%s)\n" "$f" "${SIZE}"
    done
else
    log_ok "No oversized files in /var/log or /tmp"
fi
echo ""
# 3. Permission Audit
echo "--- Permission Audit ---"
WORLD_WRITABLE=$(find /opt -type f -perm -o=w 2>/dev/null || true)
if [[ -n "${WORLD_WRITABLE}" ]]; then
    log_crit "World-writable files found in /opt:"
    echo "${WORLD_WRITABLE}" | while IFS= read -r f; do
        PERMS=$(stat -c '%a' "$f")
        printf "  %s (mode: %s)\n" "$f" "${PERMS}"
    done
else
    log_ok "No world-writable files in /opt"
fi
echo ""

# 4. Network Port Check
echo "--- Network Services ---"
EXPECTED_PORT=80
if ss -tlnp 2>/dev/null | grep -q ":${EXPECTED_PORT} "; then
    log_ok "Service listening on port ${EXPECTED_PORT}"
else
    log_warn "Nothing listening on expected port ${EXPECTED_PORT}"
fi
echo ""
# 5. Application Log Errors
echo "--- Application Log Errors ---"
LOG_FILE="/var/log/myapp/app.log"
if [[ -f "${LOG_FILE}" ]]; then
    ERROR_COUNT=$(grep -c "ERROR" "${LOG_FILE}" || echo "0")
    if [[ "${ERROR_COUNT}" -gt 100 ]]; then
        log_crit "${ERROR_COUNT} errors found in app.log"
        echo "  Top error patterns:"
        grep "ERROR" "${LOG_FILE}" | awk '{$1=$2=$3=""; print $0}' | sort | uniq -c | sort -rn | head -3 | while IFS= read -r line; do
            printf "    %s\n" "${line}"
        done
    elif [[ "${ERROR_COUNT}" -gt 0 ]]; then
        log_warn "${ERROR_COUNT} errors found in app.log"
    else
        log_ok "No errors in app.log"
    fi
else
    log_warn "${LOG_FILE} not found"
fi
echo ""
# Summary
echo "========================================="
printf " Summary: %d critical, %d warnings\n" "${CRIT_COUNT}" "${WARN_COUNT}"
if [[ "${CRIT_COUNT}" -gt 0 ]]; then
    printf " Status: ${RED}UNHEALTHY${NC}\n"
    echo "========================================="
    exit 2
elif [[ "${WARN_COUNT}" -gt 0 ]]; then
    printf " Status: ${YELLOW}DEGRADED${NC}\n"
    echo "========================================="
    exit 1
else
    printf " Status: ${GREEN}HEALTHY${NC}\n"
    echo "========================================="
    exit 0
fi
