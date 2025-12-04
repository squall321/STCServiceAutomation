#!/usr/bin/env bash
#
# apt_diagnose.sh
#  - Diagnose why APT is not working on this machine
#  - Checks: network, DNS, proxy, APT config, certificates, firewall, and apt-get itself
#

set -o pipefail

TS="$(date +%Y%m%d_%H%M%S)"
HOST="$(hostname 2>/dev/null || echo unknown)"
LOGFILE="/tmp/apt_diag_${HOST}_${TS}.log"

echo "=== APT DIAGNOSTIC REPORT ==="
echo " Host : ${HOST}"
echo " Time : ${TS}"
echo " Log  : ${LOGFILE}"
echo

# Initialize log file
{
  echo "=== APT DIAGNOSTIC DETAIL LOG ==="
  echo "Host: ${HOST}"
  echo "Time: ${TS}"
  echo
} > "${LOGFILE}"

# ---------- Helper functions ----------

report_ok()   { printf "[OK]   %s\n"   "$1"; }
report_fail() { printf "[FAIL] %s\n"   "$1"; }
report_warn() { printf "[WARN] %s\n"   "$1"; }

run_check() {
  local desc="$1"
  shift
  echo "---- ${desc} ----" >> "${LOGFILE}"
  if "$@" >> "${LOGFILE}" 2>&1; then
    report_ok "${desc}"
  else
    local rc=$?
    report_fail "${desc} (exit=${rc})"
    echo "  ? See log file for details: ${LOGFILE}"
  fi
  echo >> "${LOGFILE}"
}

run_info() {
  # Always marked as OK; used just to collect info into the log
  local desc="$1"
  shift
  echo "---- ${desc} ----" >> "${LOGFILE}"
  "$@" >> "${LOGFILE}" 2>&1 || true
  report_ok "${desc}"
  echo >> "${LOGFILE}"
}

print_section() {
  echo
  echo "========== $1 =========="
  echo
}

# ---------- Extract APT repository host ----------

detect_apt_host() {
  # Take the first "deb" line and extract the URI (2nd field)
  local uri host
  uri="$(grep -hE '^[[:space:]]*deb[[:space:]]' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null | awk '{print $2}' | head -n1)"

  if [[ -z "${uri}" ]]; then
    echo "archive.ubuntu.com"
    return
  fi

  # Extract host from http(s)://host/path
  host="$(echo "${uri}" | sed -E 's#^[a-zA-Z]+://([^/]+)/?.*#\1#')"
  if [[ -z "${host}" ]]; then
    echo "archive.ubuntu.com"
  else
    echo "${host}"
  fi
}

APT_HOST="$(detect_apt_host)"

# ---------- 1. Basic system info ----------

print_section "1. Basic System Information"

run_info "OS information (/etc/os-release or uname)" bash -c '
  if [ -f /etc/os-release ]; then
    cat /etc/os-release
  else
    uname -a
  fi
'

run_info "Network interfaces (ip addr)" ip addr

run_info "Routing table (ip route)" ip route

run_info "DNS configuration (/etc/resolv.conf)" bash -c '
  if [ -f /etc/resolv.conf ]; then
    cat /etc/resolv.conf
  else
    echo "/etc/resolv.conf not found."
  fi
'

# ---------- 2. Network / DNS / TCP connectivity ----------

print_section "2. Network and DNS Status"

run_check "Default route exists" bash -c '
  ip route | grep -q "^default "
'

# Ping test (ICMP may be blocked, so treat failure as WARN)
echo "---- Ping test ----" >> "${LOGFILE}"
if ping -c 1 -W 1 8.8.8.8 >> "${LOGFILE}" 2>&1; then
  report_ok "ping 8.8.8.8 (basic internet connectivity test)"
else
  report_warn "ping 8.8.8.8 failed (ICMP may be blocked or no internet)"
fi
echo >> "${LOGFILE}"

# DNS resolution test
run_check "DNS resolves ${APT_HOST} (getent hosts)" bash -c "
  getent hosts ${APT_HOST}
"

# TCP connectivity test using /dev/tcp
run_check "TCP connection test to ${APT_HOST}:80" bash -c "
  timeout 5 bash -c '</dev/tcp/${APT_HOST}/80' >/dev/null 2>&1
"

run_check "TCP connection test to ${APT_HOST}:443" bash -c "
  timeout 5 bash -c '</dev/tcp/${APT_HOST}/443' >/dev/null 2>&1
"

# ---------- 3. Proxy configuration ----------

print_section "3. Proxy Configuration (Environment, APT)"

# Environment proxy variables
run_info "Environment proxy variables (http_proxy/https_proxy)" bash -c '
  env | grep -iE "^(http|https)_proxy=" || echo "No proxy environment variables set."
'

# /etc/environment proxies
run_info "Proxy settings in /etc/environment" bash -c '
  if [ -f /etc/environment ]; then
    grep -i "proxy" /etc/environment || echo "No proxy-related lines in /etc/environment."
  else
    echo "/etc/environment not found."
  fi
'

# APT proxy config
run_info "Proxy settings in /etc/apt/apt.conf and apt.conf.d" bash -c '
  for f in /etc/apt/apt.conf /etc/apt/apt.conf.d/*; do
    [ -f "$f" ] || continue
    echo "### $f ###"
    grep -i "proxy" "$f" || echo "(no proxy entries)"
    echo
  done
'

run_info "Proxy settings in apt-config dump" bash -c '
  apt-config dump 2>/dev/null | grep -i proxy || echo "(no proxy settings in apt-config)"
'

# ---------- 4. APT sources list ----------

print_section "4. APT Repository (sources.list) Check"

run_info "List of APT sources files" bash -c '
  ls -l /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null || echo "Cannot list sources.list files."
'

run_info "Contents of /etc/apt/sources.list" bash -c '
  if [ -f /etc/apt/sources.list ]; then
    cat /etc/apt/sources.list
  else
    echo "/etc/apt/sources.list not found."
  fi
'

run_info "Contents of /etc/apt/sources.list.d/*.list" bash -c '
  for f in /etc/apt/sources.list.d/*.list; do
    [ -f "$f" ] || continue
    echo "### $f ###"
    cat "$f"
    echo
  done
'

# Simple syntax check: "deb" lines with too few fields
run_check "Look for suspicious deb lines in sources.list" bash -c '
  problem=0

  if [ -f /etc/apt/sources.list ]; then
    while IFS= read -r line; do
      trimmed=$(echo "$line" | sed "s/^[[:space:]]*//")
      [ -z "$trimmed" ] && continue
      echo "$trimmed" | grep -q "^#" && continue

      if echo "$trimmed" | grep -q "^deb "; then
        cnt=$(echo "$trimmed" | awk "{print NF}")
        if [ "$cnt" -lt 4 ]; then
          echo "Suspicious line in /etc/apt/sources.list: $trimmed"
          problem=1
        fi
      fi
    done < /etc/apt/sources.list
  fi

  for f in /etc/apt/sources.list.d/*.list; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
      trimmed=$(echo "$line" | sed "s/^[[:space:]]*//")
      [ -z "$trimmed" ] && continue
      echo "$trimmed" | grep -q "^#" && continue

      if echo "$trimmed" | grep -q "^deb "; then
        cnt=$(echo "$trimmed" | awk "{print NF}")
        if [ "$cnt" -lt 4 ]; then
          echo "Suspicious line in $f: $trimmed"
          problem=1
        fi
      fi
    done < "$f"
  done

  [ "$problem" -eq 0 ]
'

# ---------- 5. Certificates / CA bundle ----------

print_section "5. Certificates / CA Basic Check (HTTPS issues)"

run_info "List CA bundle directory (/etc/ssl/certs)" bash -c '
  ls /etc/ssl/certs 2>/dev/null | head -n 20
  echo "... (truncated) ..."
'

run_check "HTTPS handshake test with curl to https://${APT_HOST}/" bash -c "
  curl -I --max-time 10 https://${APT_HOST}/ >/dev/null 2>&1
"

# ---------- 6. APT behavior test ----------

print_section "6. APT Behavior Test (apt-get update)"

APT_CMD="apt-get"
if [ "$EUID" -ne 0 ]; then
  # Check if sudo is available
  if command -v sudo >/dev/null 2>&1; then
    APT_CMD="sudo apt-get"
  else
    report_warn "Not running as root and sudo not found; apt-get update may fail due to permissions."
    APT_CMD="apt-get"
  fi
fi

run_check "apt-get update test (NoLocking, Timeout=10s)" bash -c "
  ${APT_CMD} update -o Debug::NoLocking=1 -o Acquire::http::Timeout=10
"

# ---------- 7. Firewall / iptables ----------

print_section "7. Firewall (iptables) Status"

run_check "iptables -L -n" bash -c '
  if command -v iptables >/dev/null 2>&1; then
    iptables -L -n
  else
    echo "iptables command not found."
  fi
'

print_section "DIAGNOSTIC COMPLETED"

echo "Summary:"
echo " - Check the [OK] / [FAIL] / [WARN] lines above."
echo " - Detailed log file: ${LOGFILE}"
echo
echo "Run this script on BOTH:"
echo "   (1) the machine where apt works"
echo "   (2) the machine where apt fails"
echo "Then compare the two log files to see what is different."
