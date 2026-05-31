#!/bin/bash
# bootstrap.sh — sostituisce gli script auraos-* con l'ultima versione da GitHub.
# Serve per il primo aggiornamento o quando il meccanismo automatico è rotto.
#
# Uso:
#   curl -fsSL https://raw.githubusercontent.com/adri6412/aura-os/main/bootstrap.sh | sudo bash

set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "Errore: eseguire come root (sudo bash)." >&2; exit 1; }

LOWER="/run/aura-lower"

echo "[bootstrap] Recupero ultima versione da GitHub..."
TAG=$(curl -sf --max-time 15 \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/adri6412/aura-os/releases/latest" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['tag_name'])" 2>/dev/null || echo "")

[[ -z "$TAG" ]] && { echo "Errore: impossibile recuperare la versione da GitHub." >&2; exit 1; }
echo "[bootstrap] Ultima versione: $TAG"

BASE="https://raw.githubusercontent.com/adri6412/aura-os/${TAG}/config/includes.chroot"
SCRIPTS=(auraos-update auraos-check-updates auraos-switch auraos-lock auraos-unlock
         auraos-status auraos-reset auraos-change-kernel)

OVERLAY=false
if [[ -d "$LOWER/usr" ]]; then
    echo "[bootstrap] Overlay attivo — aggiorno lower layer e sistema in esecuzione."
    mount -o remount,rw "$LOWER"
    OVERLAY=true
    restore_ro() { mount -o remount,ro "$LOWER" 2>/dev/null || true; }
    trap restore_ro EXIT
else
    echo "[bootstrap] Overlay non attivo — aggiorno direttamente."
fi

install_script() {
    local src="$1" dst_lower="$2" dst_live="$3"
    local tmp
    tmp=$(mktemp)
    if curl -fsSL --max-time 30 "$src" -o "$tmp" 2>/dev/null; then
        # Scrivi nel lower layer (persistenza dopo riavvio)
        cp "$tmp" "$dst_lower"
        chmod +x "$dst_lower"
        # Scrivi nel path in esecuzione (merged view) per effetto immediato.
        # Senza questo, se l'upper layer ha una copia vecchia la shadowing
        # e il lower layer aggiornato non viene usato finché non si riavvia.
        cp "$tmp" "$dst_live" 2>/dev/null || true
        chmod +x "$dst_live" 2>/dev/null || true
        rm -f "$tmp"
        echo "OK"
    else
        rm -f "$tmp"
        echo "ERRORE (skip)"
    fi
}

for script in "${SCRIPTS[@]}"; do
    printf "[bootstrap]  %-30s" "$script"
    if $OVERLAY; then
        install_script \
            "${BASE}/usr/local/sbin/${script}" \
            "$LOWER/usr/local/sbin/${script}" \
            "/usr/local/sbin/${script}"
        ln -sf "/usr/local/sbin/${script}" "$LOWER/usr/local/bin/${script}" 2>/dev/null || true
        ln -sf "/usr/local/sbin/${script}" "/usr/local/bin/${script}" 2>/dev/null || true
    else
        install_script \
            "${BASE}/usr/local/sbin/${script}" \
            "/usr/local/sbin/${script}" \
            "/usr/local/sbin/${script}"
    fi
done

# Manager (file Python — contiene le tab UI)
printf "[bootstrap]  %-30s" "auraos_manager.py"
if $OVERLAY; then
    install_script \
        "${BASE}/opt/auraos-manager/auraos_manager.py" \
        "$LOWER/opt/auraos-manager/auraos_manager.py" \
        "/opt/auraos-manager/auraos_manager.py"
else
    install_script \
        "${BASE}/opt/auraos-manager/auraos_manager.py" \
        "/opt/auraos-manager/auraos_manager.py" \
        "/opt/auraos-manager/auraos_manager.py"
fi

# Aggiorna versions.conf nel lower layer
if $OVERLAY; then
    VFILE="$LOWER/etc/auraos/versions.conf"
else
    VFILE="/etc/auraos/versions.conf"
fi
if [[ -f "$VFILE" ]]; then
    sed -i "s/^AURAOS_VERSION=.*/AURAOS_VERSION=\"${TAG}\"/" "$VFILE"
    echo "[bootstrap] versions.conf → AURAOS_VERSION=\"$TAG\""
fi

echo ""
echo "[bootstrap] Script aggiornati. Esegui ora: sudo auraos-update"
echo "[bootstrap] (applicherà le migrazioni pendenti)"
