#!/bin/bash
# Pulizia post-installazione: rimuove Calamares e componenti live dal sistema installato.
# Chiamato da shellprocess@cleanup (chroot: true) durante l'installazione Calamares.
# Chiamato anche da auraos-firstboot.service al primo avvio se la prima rimozione fallì.

set +e
export DEBIAN_FRONTEND=noninteractive

LOG=/var/log/auraos-cleanup.log
log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG"; }

log "=== AuraOS cleanup post-install avviato ==="

# --- Rimuovi Calamares ---
log "Rimozione Calamares..."
if dpkg -l calamares 2>/dev/null | grep -q '^ii'; then
    apt-get remove --purge -y calamares calamares-settings-debian 2>>"$LOG" \
        || dpkg --purge --force-remove-reinstreq calamares calamares-settings-debian 2>>"$LOG" \
        || log "WARN: rimozione Calamares fallita"
    log "Calamares rimosso."
else
    log "Calamares non trovato (già rimosso o non installato)."
fi

# --- Rimuovi componenti live ---
log "Rimozione componenti live..."
for pkg in live-boot live-boot-initramfs-tools live-config live-config-systemd \
           live-config-doc live-tools live-task-recommended; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
        dpkg --purge --force-remove-reinstreq "$pkg" 2>>"$LOG" || true
    fi
done
log "Componenti live rimossi."

# --- Autoremove e pulizia cache ---
apt-get autoremove --purge -y 2>>"$LOG" || true
apt-get clean 2>>"$LOG" || true

# --- File e directory residui live ---
rm -f /etc/apt/sources.list.d/live.list /etc/apt/sources.list.d/live-media.list
rm -rf /etc/live /var/log/live
rm -f /lib/live/config/9999-auraos-mode
rm -f /usr/share/xsessions/calamares-kiosk.desktop
rm -f /usr/local/bin/calamares-kiosk-session
rm -f /usr/local/bin/calamares-kiosk.sh
rm -f /etc/xdg/autostart/calamares-kiosk.desktop
rm -f /etc/skel/.config/autostart/calamares-kiosk.desktop
rm -f /var/lib/AccountsService/users/user
rm -f /usr/share/applications/calamares.desktop

# --- LightDM: rimuovi autologin live e abilita sessione GNOME Wayland ---
# user-session=gnome-xorg era necessario nel live (Calamares/pkexec su X11)
# Sul sistema installato usiamo gnome (GNOME preferisce Wayland automaticamente)
sed -i '/^autologin-user=/d'         /etc/lightdm/lightdm.conf 2>/dev/null || true
sed -i '/^autologin-user-timeout=/d' /etc/lightdm/lightdm.conf 2>/dev/null || true
sed -i 's/^user-session=gnome-xorg$/user-session=gnome/' \
    /etc/lightdm/lightdm.conf 2>/dev/null || true

# --- Configurazione overlay persistente ───────────────────────────────────────
# Determina quale partizione usare come upper layer dell'overlay.
# Priorità:
#   1. LABEL=auraos-data  → partizione creata seguendo la guida interattiva
#   2. Partizione /home   → doppio uso: home + overlay
#   3. Qualsiasi altra ext4 non-root → fallback generico
# L'UUID viene salvato in /etc/auraos/overlay.conf; l'initramfs lo legge
# ad ogni avvio per montare la partizione dati prima di costruire l'overlay.

log "Ricerca partizione dati per overlay persistente..."

# Forza probe diretto di tutti i device (non dipendere dalla cache blkid
# che può essere vuota nel chroot Calamares dove udev non gira)
blkid -g 2>/dev/null || true
for _dev in /dev/sd?[0-9] /dev/vd?[0-9] /dev/nvme?n?p[0-9]; do
    [ -b "$_dev" ] && blkid "$_dev" >/dev/null 2>&1 || true
done

ROOT_DEV=$(findmnt -n -o SOURCE / 2>/dev/null || true)
ROOT_UUID=$(blkid -o value -s UUID "$ROOT_DEV" 2>/dev/null || true)
OVERLAY_UUID=""
OVERLAY_NOTE=""

# 1. Partizione con LABEL=auraos-data
DATA_DEV=$(blkid -L "auraos-data" 2>/dev/null || true)
if [ -n "$DATA_DEV" ]; then
    DATA_UUID=$(blkid -o value -s UUID "$DATA_DEV" 2>/dev/null || true)
    if [ -n "$DATA_UUID" ] && [ "$DATA_UUID" != "$ROOT_UUID" ]; then
        OVERLAY_UUID="$DATA_UUID"
        OVERLAY_NOTE="partizione con LABEL=auraos-data ($DATA_DEV)"
    fi
fi

# 2. Partizione /home (se l'utente non ha usato la label)
if [ -z "$OVERLAY_UUID" ]; then
    HOME_UUID=$(findmnt -n -o UUID /home 2>/dev/null || true)
    if [ -n "$HOME_UUID" ] && [ "$HOME_UUID" != "$ROOT_UUID" ]; then
        OVERLAY_UUID="$HOME_UUID"
        OVERLAY_NOTE="partizione /home (doppio uso: home + overlay)"
    fi
fi

# 3. Qualsiasi altra partizione ext4 non root
if [ -z "$OVERLAY_UUID" ]; then
    for dev in $(blkid -t TYPE=ext4 -o device 2>/dev/null); do
        uuid=$(blkid -o value -s UUID "$dev" 2>/dev/null || true)
        [ "$uuid" = "$ROOT_UUID" ] && continue
        OVERLAY_UUID="$uuid"
        OVERLAY_NOTE="partizione ext4 generica ($dev)"
        break
    done
fi

install -d /etc/auraos

if [ -n "$OVERLAY_UUID" ]; then
    # Ridimensiona il filesystem della partizione dati a tutta la partizione.
    # Necessario se la partizione è stata espansa dopo la formattazione.
    DATA_DEV=$(blkid -U "$OVERLAY_UUID" 2>/dev/null || true)
    if [ -n "$DATA_DEV" ]; then
        log "Ridimensionamento filesystem $DATA_DEV alla dimensione della partizione..."
        e2fsck -f -y "$DATA_DEV" 2>>"$LOG" || true
        resize2fs "$DATA_DEV" 2>>"$LOG" && log "resize2fs OK" || log "WARN: resize2fs fallito (non critico)"
    fi

    cat > /etc/auraos/overlay.conf <<EOF
# AuraOS — configurazione overlay persistente
# Generato da Calamares durante l'installazione. Non modificare.
# Per reset completo del sistema: eliminare la directory .auraos-overlay
# dalla partizione dati e riavviare.
OVERLAY_UUID="$OVERLAY_UUID"
OVERLAY_SUBDIR=".auraos-overlay"
EOF
    log "Overlay configurato su $OVERLAY_NOTE (UUID=$OVERLAY_UUID)"
    log "Struttura: .auraos-overlay/{upper,work} sulla partizione dati"
else
    # Nessuna partizione trovata: avviso, userà tmpfs al boot
    cat > /etc/auraos/overlay.conf <<EOF
# AuraOS — overlay.conf
# ATTENZIONE: nessuna partizione dati trovata durante l'installazione.
# Il sistema userà un tmpfs come upper layer (modifiche perse al riavvio).
# Per abilitare la persistenza: creare una partizione ext4, trovarne l'UUID
# con 'blkid', e impostare OVERLAY_UUID= qui.
OVERLAY_UUID=""
OVERLAY_SUBDIR=".auraos-overlay"
EOF
    log "WARN: nessuna partizione dati disponibile — overlay userà tmpfs (non persistente)"
fi

# --- Deduplicazione /etc/fstab ---
# Calamares può aggiungere due volte /boot/efi se rileva sia sda1 (EFI System)
# sia sda2 (BIOS compat, FAT32). systemd-fstab-generator fallisce con "duplicate".
# Teniamo solo la prima occorrenza di ogni mount point.
if [ -f /etc/fstab ]; then
    awk '!seen[$2]++ || $1~/^#/ || $2=="none" || $2=="swap"' \
        /etc/fstab > /tmp/fstab.dedup && mv /tmp/fstab.dedup /etc/fstab
    log "fstab deduplicato"
fi

# --- Permessi wrapper apt ---
chmod +x /usr/local/bin/apt /usr/local/bin/apt-get 2>/dev/null || true

# --- Rimuovi prompt (live) dal sistema installato ---
# live-boot scrive "live" in /etc/debian_chroot; il PS1 standard Debian
# ${debian_chroot:+($debian_chroot)} lo mostra come "(live)".
rm -f /etc/debian_chroot
rm -f /etc/profile.d/live-prompt.sh /etc/profile.d/live.sh 2>/dev/null || true

# --- Pulizia generale ---
rm -f /root/.bash_history
rm -f /etc/machine-id /var/lib/dbus/machine-id
systemd-machine-id-setup 2>/dev/null || true

# --- Disabilita il servizio di primo avvio ---
systemctl disable auraos-firstboot.service 2>/dev/null || true

log "=== Cleanup completato ==="
exit 0
