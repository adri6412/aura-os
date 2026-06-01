# AuraOS Profile — Ivanti Secure Access Client (Pulse VPN)
PROFILE_NAME="Ivanti Secure Access"
PROFILE_DESC="Client VPN Ivanti/Pulse Secure — il .deb va scaricato dal portale aziendale"

INSTALL_UPPER=true

REMOVE_PACKAGES=""
INSTALL_PACKAGES=""
DISABLE_SERVICES=""
ENABLE_SERVICES=""

CUSTOM_APPLY_SCRIPT='
set -e

DEB_PATH="${AURAOS_DEB_PATH:-}"
if [ -z "$DEB_PATH" ] || [ ! -f "$DEB_PATH" ]; then
    echo "[ivanti] ERRORE: file .deb non trovato: ${DEB_PATH:-non specificato}" >&2
    echo "[ivanti] Usa il Manager AuraOS per installare questo profilo." >&2
    exit 1
fi

echo "[ivanti] Installazione dipendenze Bookworm/Bullseye (richieste da Ivanti su Trixie)..."
# libwebkit2gtk-4.0-37, libicu72 sono in Bookworm
# libjpeg8 e libjavascriptcoregtk-4.0-18 sono stati rimossi da Bookworm: servono da Bullseye
echo "deb http://deb.debian.org/debian bookworm main" \
    > /etc/apt/sources.list.d/compat-ivanti.list
echo "deb http://deb.debian.org/debian bullseye main" \
    >> /etc/apt/sources.list.d/compat-ivanti.list
apt-get update -qq

apt-get install -y \
    libwebkit2gtk-4.0-37 \
    libjavascriptcoregtk-4.0-18 \
    libicu72 \
    libjpeg8 \
    libgtkmm-3.0-1t64 \
    libcurl4t64 \
    libnss3-tools \
    acl

rm -f /etc/apt/sources.list.d/compat-ivanti.list
apt-get update -qq

echo "[ivanti] Installazione $DEB_PATH..."
dpkg -i "$DEB_PATH" 2>/dev/null || true
apt-get install -f -y

# AppArmor complain mode: Ivanti usa tun/routing che i profili enforce bloccherebbero
if command -v aa-complain &>/dev/null; then
    for bin in /opt/pulsesecure/bin/pulsesecure \
                /opt/pulsesecure/bin/pulselauncher \
                /opt/pulsesecure/bin/pulseUI; do
        [ -x "$bin" ] && aa-complain "$bin" 2>/dev/null || true
    done
fi

# Dispatcher NetworkManager: sincronizza DNS VPN con AdGuard Home
install -d /etc/NetworkManager/dispatcher.d
{
echo "#!/bin/bash"
echo "AGH=/opt/AdGuardHome/AdGuardHome.yaml"
echo "[ -f \"\$AGH\" ] || exit 0"
echo "case \"\$2\" in"
echo "    vpn-up)"
echo "        logger -t auraos-vpn VPN_up"
echo "        systemctl reload-or-restart AdGuardHome 2>/dev/null || true ;;"
echo "    vpn-down)"
echo "        logger -t auraos-vpn VPN_down"
echo "        systemctl reload-or-restart AdGuardHome 2>/dev/null || true ;;"
echo "esac"
} > /etc/NetworkManager/dispatcher.d/99-auraos-vpn-dns
chmod +x /etc/NetworkManager/dispatcher.d/99-auraos-vpn-dns

# Il servizio NON parte automaticamente al boot (risparmio ~70MB RAM)
systemctl disable pulsesecure.service 2>/dev/null || true

echo "[ivanti] Installazione completata."
echo "[ivanti] Avvia Ivanti Secure Access dalla barra delle applicazioni."
'

CUSTOM_REVERT_SCRIPT='
set -e

echo "[ivanti] Rimozione Ivanti Secure Access..."
systemctl stop pulsesecure 2>/dev/null || true
systemctl disable pulsesecure 2>/dev/null || true

# Il nome pacchetto varia tra le versioni
for pkg in ivanti-secure-access pulse-secure pulsesecure; do
    dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" && \
        dpkg --purge "$pkg" 2>/dev/null || true
done
apt-get autoremove --purge -y 2>/dev/null || true

rm -f /etc/NetworkManager/dispatcher.d/99-auraos-vpn-dns

echo "[ivanti] Rimosso."
'
