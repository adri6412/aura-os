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

if [[ -d "$LOWER/usr" ]]; then
    echo "[bootstrap] Overlay attivo — aggiorno nel lower layer ($LOWER)."
    mount -o remount,rw "$LOWER"
    TARGET="$LOWER"
    restore_ro() { mount -o remount,ro "$LOWER" 2>/dev/null || true; }
    trap restore_ro EXIT
else
    echo "[bootstrap] Overlay non attivo — aggiorno direttamente."
    TARGET=""
fi

for script in "${SCRIPTS[@]}"; do
    printf "[bootstrap]  %-30s" "$script"
    if curl -fsSL --max-time 30 "${BASE}/usr/local/sbin/${script}" \
            -o "${TARGET}/usr/local/sbin/${script}" 2>/dev/null; then
        chmod +x "${TARGET}/usr/local/sbin/${script}"
        ln -sf "/usr/local/sbin/${script}" "${TARGET}/usr/local/bin/${script}" 2>/dev/null || true
        echo "OK"
    else
        echo "ERRORE (skip)"
    fi
done

# Aggiorna anche il manager (file Python — contiene le tab UI)
printf "[bootstrap]  %-30s" "auraos_manager.py"
if curl -fsSL --max-time 30 "${BASE}/opt/auraos-manager/auraos_manager.py" \
        -o "${TARGET}/opt/auraos-manager/auraos_manager.py" 2>/dev/null; then
    chmod +x "${TARGET}/opt/auraos-manager/auraos_manager.py"
    echo "OK"
else
    echo "ERRORE (skip)"
fi

VFILE="${TARGET}/etc/auraos/versions.conf"
if [[ -f "$VFILE" ]]; then
    sed -i "s/^AURAOS_VERSION=.*/AURAOS_VERSION=\"${TAG}\"/" "$VFILE"
    echo "[bootstrap] versions.conf aggiornato → AURAOS_VERSION=\"$TAG\""
fi

echo ""
echo "[bootstrap] Fatto. Riavvia il manager per vedere le modifiche."
