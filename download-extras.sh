#!/bin/bash
# Verifica che i pacchetti di terze parti siano presenti prima del build.
# Eseguire PRIMA di build.sh.
#
# I .deb non sono inclusi in git (vedi .gitignore).
# Piazzarli manualmente in config/packages.chroot/ prima di eseguire questo script.

set -e

DEST="config/packages.chroot"
mkdir -p "$DEST"

ERRORS=0

check_pkg() {
    local label="$1"
    local pattern="$2"
    local hint="$3"
    if ls "$DEST"/$pattern 2>/dev/null | grep -q .; then
        echo "[ok]   $label — $(ls "$DEST"/$pattern 2>/dev/null | head -1)"
    else
        echo "[MANCANTE] $label"
        echo "           → $hint"
        ERRORS=$((ERRORS + 1))
    fi
}

echo "=== Verifica pacchetti extra ==="
echo ""

# Ivanti Secure Access Client (Pulse VPN)
check_pkg "Ivanti Secure Access Client" \
    "ivanti-*.deb" \
    "Copia il .deb in config/packages.chroot/ (es. ivanti-linux-22.8r5-b41063-64bit-installer.deb)"

echo ""
if [ "$ERRORS" -eq 0 ]; then
    echo "=== Tutto OK. Puoi eseguire: sudo ./build.sh ==="
else
    echo "=== $ERRORS pacchett$([ "$ERRORS" -eq 1 ] && echo 'o mancante' || echo 'i mancanti') — il build partirà ma quei componenti saranno saltati. ==="
fi
