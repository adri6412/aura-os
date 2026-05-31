# AuraOS Profile — WinBoat
PROFILE_NAME="WinBoat"
PROFILE_DESC="Windows in QEMU/Docker con accesso via FreeRDP — richiede il profilo Docker CE attivo"

# Installato nell'upper layer: richiede Docker CE (anch'esso nell'upper layer).
INSTALL_UPPER=true

REMOVE_PACKAGES=""
INSTALL_PACKAGES=""
DISABLE_SERVICES=""
ENABLE_SERVICES=""

CUSTOM_APPLY_SCRIPT='
set -e

# ── Prerequisito: Docker ──────────────────────────────────────────────────────
if ! command -v docker &>/dev/null || ! systemctl is-active --quiet docker; then
    echo "[winboat] ERRORE: Docker non installato o non attivo." >&2
    echo "[winboat] Installa prima il profilo 'Docker CE' dal manager AuraOS." >&2
    exit 1
fi

# ── FreeRDP ───────────────────────────────────────────────────────────────────
echo "[winboat] Installazione FreeRDP..."
apt-get update -qq
apt-get install -y freerdp3-x11 2>/dev/null \
    || apt-get install -y freerdp2-x11 2>/dev/null \
    || { echo "[winboat] WARN: nessun pacchetto freerdp trovato." >&2; }

# ── WinBoat .deb ──────────────────────────────────────────────────────────────
WINBOAT_URL="https://github.com/TibixDev/winboat/releases/download/v0.9.0/winboat-0.9.0-amd64.deb"
WINBOAT_DEB="/tmp/winboat-install.deb"

echo "[winboat] Download winboat v0.9.0..."
curl -fsSL "$WINBOAT_URL" -o "$WINBOAT_DEB" \
    || { echo "[winboat] ERRORE: download fallito." >&2; exit 1; }

echo "[winboat] Installazione winboat..."
dpkg -i "$WINBOAT_DEB" 2>/dev/null || true
apt-get install -f -y
rm -f "$WINBOAT_DEB"

echo "[winboat] Installazione completata."
'

CUSTOM_REVERT_SCRIPT='
set -e

echo "[winboat] Rimozione winboat e FreeRDP..."
apt-get remove --purge -y winboat freerdp3-x11 freerdp2-x11 2>/dev/null || true
apt-get autoremove --purge -y 2>/dev/null || true

echo "[winboat] WinBoat rimosso."
echo "[winboat] Docker rimane installato — rimuovilo dal manager se non serve."
'
