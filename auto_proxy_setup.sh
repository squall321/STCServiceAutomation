#!/usr/bin/env bash
#
# setup_proxy.sh
#   - Configure corporate proxy + CA (crt) in one shot
#   - Applies to: /etc/environment, apt, snap, pip, curl, VSCode
#
# Usage:
#   1) Edit the variables in the "USER CONFIG" section.
#   2) Place your company CA .crt file in the same directory as this script.
#   3) Run: sudo ./setup_proxy.sh
#

### ==== [ USER CONFIG ] ============================================

# Proxy server info
# PROXY_HOST: hostname or IP ONLY (NO port here)
PROXY_HOST="168.219.61.252"      # e.g. "proxy.mycompany.com" or "168.219.61.252"
PROXY_PORT="8080"                # e.g. "8080"

# If your proxy requires authentication, fill these (otherwise leave empty)
PROXY_USER=""                    # e.g. "myuser"
PROXY_PASS=""                    # e.g. "mypassword"
# NOTE: If your password contains special characters (@, :, /, etc.),
#       you may need to URL-encode it manually.

# Company CA crt file located in the same directory as this script
CRT_FILE_NAME="DigitalCity.crt"  # e.g. "corp-proxy.crt"

# no_proxy setting (add your internal domains if needed)
NO_PROXY_LIST="localhost,127.0.0.1,::1"

### ================================================================

set -e

# Require root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run as root (sudo)."
  echo "Example: sudo ./setup_proxy.sh"
  exit 1
fi

# Determine target (non-root) user ? the user who will use pip/curl/VSCode
TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo "")}"
if [ -z "$TARGET_USER" ]; then
  echo "WARNING: Could not detect target user (SUDO_USER/logname)."
  echo "pip, curl, VSCode user-level configuration will be skipped."
fi

TARGET_HOME=""
if [ -n "$TARGET_USER" ]; then
  TARGET_HOME="$(eval echo "~${TARGET_USER}")"
fi

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Starting corporate proxy + CA setup ==="

### 1) Build proxy URL ################################################

if [ -n "$PROXY_USER" ] && [ -n "$PROXY_PASS" ]; then
  PROXY_URL="http://${PROXY_USER}:${PROXY_PASS}@${PROXY_HOST}:${PROXY_PORT}"
else
  PROXY_URL="http://${PROXY_HOST}:${PROXY_PORT}"
fi

echo "Using proxy URL: ${PROXY_URL}"

### 2) Register company CA (crt) system-wide ##########################

CRT_SRC_PATH="${SCRIPT_DIR}/${CRT_FILE_NAME}"
CRT_DST_PATH="/usr/local/share/ca-certificates/${CRT_FILE_NAME}"

if [ -f "$CRT_SRC_PATH" ]; then
  echo "[CA] Copying CA file: ${CRT_SRC_PATH} -> ${CRT_DST_PATH}"
  cp "$CRT_SRC_PATH" "$CRT_DST_PATH"
  echo "[CA] Running update-ca-certificates"
  update-ca-certificates
else
  echo "[CA] WARNING: CA file not found: ${CRT_SRC_PATH}"
  echo "[CA] Skipping CA registration."
fi

### 3) Update /etc/environment with proxy variables ###################

echo "[env] Updating /etc/environment with proxy variables"

# Backup existing /etc/environment if it exists
if [ -f /etc/environment ]; then
  ENV_BACKUP="/etc/environment.$(date +%Y%m%d_%H%M%S).bak"
  cp /etc/environment "$ENV_BACKUP"
  echo "[env] Backup created: ${ENV_BACKUP}"
fi

# Append proxy settings (do not overwrite existing environment variables)
cat <<EOF >> /etc/environment

# Added by setup_proxy.sh on $(date)
http_proxy="${PROXY_URL}"
https_proxy="${PROXY_URL}"
HTTP_PROXY="${PROXY_URL}"
HTTPS_PROXY="${PROXY_URL}"
no_proxy="${NO_PROXY_LIST}"
NO_PROXY="${NO_PROXY_LIST}"
EOF

echo "[env] /etc/environment updated (proxy variables appended)"

### 4) apt proxy configuration ########################################

echo "[apt] Configuring /etc/apt/apt.conf.d/80proxy"

cat >/etc/apt/apt.conf.d/80proxy <<EOF
Acquire::http::Proxy "${PROXY_URL}";
Acquire::https::Proxy "${PROXY_URL}";
EOF

echo "[apt] apt proxy configuration complete."

### 5) snap proxy configuration #######################################

if command -v snap >/dev/null 2>&1; then
  echo "[snap] Configuring snap system proxy"
  snap set system proxy.http="${PROXY_URL}"   || echo "[snap] proxy.http configuration failed (check snapd status)."
  snap set system proxy.https="${PROXY_URL}"  || echo "[snap] proxy.https configuration failed (check snapd status)."
else
  echo "[snap] snap command not found. Skipping snap configuration."
fi

### 5-1) Snap Store GUI proxy configuration ##########################

echo "[snap-store] Setting systemd override for snap-store (GUI)"

# Create user-level override directory
mkdir -p /etc/systemd/system/snap-store.service.d

# Override file for proxy
cat >/etc/systemd/system/snap-store.service.d/proxy.conf <<EOF
[Service]
Environment="http_proxy=${PROXY_URL}"
Environment="https_proxy=${PROXY_URL}"
Environment="HTTP_PROXY=${PROXY_URL}"
Environment="HTTPS_PROXY=${PROXY_URL}"
Environment="no_proxy=${NO_PROXY_LIST}"
Environment="NO_PROXY=${NO_PROXY_LIST}"
EOF

# Reload and restart snap-store (if running)
systemctl daemon-reload || true
systemctl restart snap-store.service || true

echo "[snap-store] Proxy applied to snap-store (GUI)"

### 6) User-level pip configuration ###################################

if [ -n "$TARGET_HOME" ]; then
  PIP_DIR="${TARGET_HOME}/.config/pip"
  PIP_CONF="${PIP_DIR}/pip.conf"

  echo "[pip] Setting pip proxy for user ${TARGET_USER}: ${PIP_CONF}"
  mkdir -p "$PIP_DIR"

  cat >"$PIP_CONF" <<EOF
[global]
proxy = ${PROXY_URL}
EOF

  chown -R "${TARGET_USER}:${TARGET_USER}" "$PIP_DIR"
else
  echo "[pip] No target user detected. Skipping pip configuration."
fi

### 7) User-level curl configuration ##################################

if [ -n "$TARGET_HOME" ]; then
  CURL_RC="${TARGET_HOME}/.curlrc"
  echo "[curl] Setting curl proxy for user ${TARGET_USER}: ${CURL_RC}"

  cat >"$CURL_RC" <<EOF
proxy = ${PROXY_URL}
EOF

  chown "${TARGET_USER}:${TARGET_USER}" "$CURL_RC"
else
  echo "[curl] No target user detected. Skipping curl configuration."
fi

### 8) VSCode settings (if present) ###################################

if [ -n "$TARGET_HOME" ]; then
  VSCODE_DIR="${TARGET_HOME}/.config/Code/User"
  SETTINGS_JSON="${VSCODE_DIR}/settings.json"

  if [ -d "$VSCODE_DIR" ]; then
    echo "[VSCode] Found settings directory: ${VSCODE_DIR}"

    mkdir -p "$VSCODE_DIR"

    # Backup existing settings.json if present
    if [ -f "$SETTINGS_JSON" ]; then
      BACKUP="${SETTINGS_JSON}.$(date +%Y%m%d_%H%M%S).bak"
      echo "[VSCode] Backing up existing settings.json -> ${BACKUP}"
      cp "$SETTINGS_JSON" "$BACKUP"
    fi

    # Use Python to safely merge JSON (avoid jq dependency)
    python3 - "$SETTINGS_JSON" "$PROXY_URL" << 'EOF'
import json, os, sys

path = sys.argv[1]
proxy_url = sys.argv[2]

data = {}
if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            content = f.read().strip()
            if content:
                data = json.loads(content)
    except Exception:
        # If parsing fails, start from empty settings
        data = {}

# Set VSCode HTTP proxy settings
data["http.proxy"] = proxy_url
data["http.proxyStrictSSL"] = True

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
EOF

    chown -R "${TARGET_USER}:${TARGET_USER}" "$VSCODE_DIR"
    echo "[VSCode] Proxy settings applied to settings.json."

  else
    echo "[VSCode] ${VSCODE_DIR} not found. VSCode may not have been run yet. Skipping VSCode configuration."
  fi
else
  echo "[VSCode] No target user detected. Skipping VSCode configuration."
fi

### 9) Summary ########################################################

echo
echo "=== Proxy/CA setup summary ==="
echo "Proxy URL     : ${PROXY_URL}"
echo "CA file       : ${CRT_DST_PATH} (registered if file existed)"
echo "/etc/environment : Proxy variables appended"
echo "apt           : /etc/apt/apt.conf.d/80proxy configured"
echo "snap          : proxy.http / proxy.https set (if snap is available)"
[ -n "$TARGET_HOME" ] && echo "User-level    : pip / curl / VSCode configured for user ${TARGET_USER} (if directories exist)"

echo
echo "To fully apply these changes, you should:"
echo "  - Open a new terminal session, or"
echo "  - Log out and log back in, or"
echo "  - Reboot the system if needed."
echo "========================================="