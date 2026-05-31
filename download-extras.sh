#!/bin/bash
# Scarica pacchetti di terze parti necessari per il build ma non inclusi in git.
# Eseguire PRIMA di build.sh.

set -e

DEST="config/packages.chroot"
mkdir -p "$DEST"

echo "=== Download pacchetti extra ==="

# Ivanti Secure Access Client (Pulse VPN)
IVANTI_URL="https://cdn.ku.edu.tr/cdn/files/help/ivanti/ivanti-linux-22.8r5-b41063-64bit-installer.deb"
IVANTI_FILE="$DEST/ivanti-linux-22.8r5-b41063-64bit-installer.deb"

if [ -f "$IVANTI_FILE" ]; then
    echo "[skip] Ivanti già presente: $IVANTI_FILE"
else
    echo "[download] Ivanti Secure Access Client..."
    curl -L --progress-bar "$IVANTI_URL" -o "$IVANTI_FILE"
    echo "[ok] $IVANTI_FILE"
fi

echo "=== Download completato. Ora puoi eseguire: sudo ./build.sh ==="
