#!/bin/bash
# =============================================================================
# AuraOS — Script di Build
# Richiede: Debian 13 (trixie) o derivata con live-build installato
# Eseguire come root o con sudo
#
# IMPORTANTE: live-build richiede un filesystem Linux nativo (ext4/btrfs).
# Se invocato da /mnt/c/ (NTFS/WSL), la build viene eseguita in /var/tmp/
# e l'ISO viene copiata di ritorno su Windows al termine.
#
# MODALITÀ:
#   sudo ./build.sh               → VELOCE: sync file nel chroot esistente + solo binary (~5-10 min)
#   sudo ./build.sh --chroot      → MEDIA:  rebuild chroot+binary, cache bootstrap/pkg preservata (~30-40 min)
#   sudo ./build.sh --clean       → COMPLETA: tutto da zero (~60 min)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="binary"
case "${1:-}" in
    --chroot) MODE="chroot" ;;
    --clean)  MODE="clean"  ;;
esac

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[AuraOS]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERR]${NC} $*"; exit 1; }

# ── Finalizzazione chroot prima di ogni build ──────────────────────────────────
# Crea i symlink systemd e corregge i permessi che Windows non preserva.
# Gira su Linux (nel build.sh), prima che lb costruisca la squashfs.
auraos_finalize_chroot() {
    local C="$NATIVE_BUILD_DIR/chroot"
    [[ -d "$C/usr" ]] || return 0

    log "Finalizzazione chroot (symlink + permessi)..."

    # Permessi eseguibili
    local executables=(
        lib/live/config/9998-start-gdm3
        lib/live/config/9999-auraos-mode
        usr/local/bin/calamares-kiosk-session
        usr/local/lib/auraos-cleanup.sh
        etc/initramfs-tools/scripts/init-bottom/auraos-overlayfs
        etc/initramfs-tools/hooks/auraos-tools
        usr/local/sbin/auraos-update
        usr/local/sbin/auraos-unlock
        usr/local/sbin/auraos-lock
        usr/local/sbin/auraos-status
        usr/local/sbin/auraos-reset
        usr/local/sbin/auraos-setup-overlay
    )
    for f in "${executables[@]}"; do
        [[ -f "$C/$f" ]] && chmod +x "$C/$f"
    done

    # Symlink systemd per GDM (non creabili su Windows, li creiamo qui su Linux)
    # NON tocchiamo default.target: in live-boot è multi-user.target e va bene così.
    # GDM parte tramite display-manager.service che è richiesto da multi-user.target.
    mkdir -p "$C/etc/systemd/system/graphical.target.wants"
    ln -sf /lib/systemd/system/gdm3.service \
        "$C/etc/systemd/system/display-manager.service" 2>/dev/null || true
    ln -sf /lib/systemd/system/gdm3.service \
        "$C/etc/systemd/system/graphical.target.wants/gdm3.service" 2>/dev/null || true

    ok "Chroot finalizzato (symlink GDM + permessi OK)"
}

[[ $EUID -ne 0 ]] && err "Eseguire come root: sudo ./build.sh"
command -v lb          &>/dev/null || err "live-build non installato. Esegui: apt install live-build"
command -v debootstrap &>/dev/null || err "debootstrap non installato. Esegui: apt install debootstrap"

log "AuraOS — Build avviato (modalità: $MODE)"
log "Data: $(date)"

SOURCE_FS=$(stat -f -c '%T' "$SCRIPT_DIR" 2>/dev/null || echo "unknown")
if [[ "$SCRIPT_DIR" == /mnt/* ]] || \
   [[ "$SOURCE_FS" == "fuseblk" ]] || \
   [[ "$SOURCE_FS" == "msdos" ]]  || \
   [[ "$SOURCE_FS" == "ntfs" ]]; then
    NATIVE_BUILD_DIR="/var/tmp/auraos-build"
    ISO_OUTPUT_DIR="$SCRIPT_DIR/output"
    warn "NTFS/FUSE rilevato — build in $NATIVE_BUILD_DIR (ext4 nativo)"
else
    NATIVE_BUILD_DIR="$SCRIPT_DIR/build"
    ISO_OUTPUT_DIR="$SCRIPT_DIR/output"
    log "Filesystem nativo — build in $NATIVE_BUILD_DIR"
fi

mkdir -p "$ISO_OUTPUT_DIR"

apt-get install -y --no-install-recommends \
    live-build debootstrap squashfs-tools xorriso \
    isolinux syslinux-efi grub-efi-amd64-bin grub-pc-bin \
    mtools dosfstools rsync \
    -qq 2>/dev/null
ok "Dipendenze OK"

mkdir -p "$NATIVE_BUILD_DIR"
touch "$NATIVE_BUILD_DIR/.test_a"
ln "$NATIVE_BUILD_DIR/.test_a" "$NATIVE_BUILD_DIR/.test_b" 2>/dev/null \
    || err "Il filesystem in $NATIVE_BUILD_DIR non supporta hard link (serve ext4/btrfs)."
rm -f "$NATIVE_BUILD_DIR/.test_a" "$NATIVE_BUILD_DIR/.test_b"

CHROOT_OK=false
[[ -f "$NATIVE_BUILD_DIR/.build/chroot_package-lists.install" && -d "$NATIVE_BUILD_DIR/chroot/usr" ]] && CHROOT_OK=true

if [[ "$MODE" == "binary" ]] && ! $CHROOT_OK; then
    warn "Nessun chroot valido trovato — modalità degradata a --chroot"
    MODE="chroot"
fi


# Exclude comuni per rsync: preserva artefatti di build generati da live-build
RSYNC_EXCLUDES=(
    --exclude='cache/'
    --exclude='chroot/'
    --exclude='binary/'
    --exclude='.build/'
    --exclude='*.iso'
    --exclude='build/'
    --exclude='output/'
    --exclude='build.sh'
    --exclude='chroot.packages*'
    --exclude='chroot.files'
    --exclude='chroot-binary.packages*'
)

if [[ "$MODE" == "clean" ]]; then
    log "Rimozione completa directory di build..."
    rm -rf "$NATIVE_BUILD_DIR"
    mkdir -p "$NATIVE_BUILD_DIR"
    rsync -aH \
        "${RSYNC_EXCLUDES[@]}" \
        "$SCRIPT_DIR/" "$NATIVE_BUILD_DIR/"
    cd "$NATIVE_BUILD_DIR"
    ok "Directory di build pronta"
    chmod +x config/hooks/normal/*.hook.chroot 2>/dev/null || true
    bash auto/config
    mkdir -p .build
    log "Bootstrap (~10 min)..."
    lb bootstrap 2>&1 | tee .build/build.log  || err "lb bootstrap fallita"
    log "Build chroot (~40 min)..."
    lb chroot    2>&1 | tee -a .build/build.log || err "lb chroot fallita"
    auraos_finalize_chroot
    log "Build binary (~10 min)..."
    lb binary    2>&1 | tee -a .build/build.log || err "lb binary fallita"

elif [[ "$MODE" == "chroot" ]]; then
    log "Sync configurazione (cache bootstrap/pacchetti preservata)..."
    rsync -aH --delete \
        "${RSYNC_EXCLUDES[@]}" \
        "$SCRIPT_DIR/" "$NATIVE_BUILD_DIR/"
    cd "$NATIVE_BUILD_DIR"
    log "Pulizia chroot e binary (cache preservata)..."
    lb clean 2>/dev/null || true
    [[ -d cache/bootstrap       ]] && ok "Cache bootstrap presente"
    [[ -d cache/packages.chroot ]] && ok "Cache pacchetti presente"
    chmod +x config/hooks/normal/*.hook.chroot 2>/dev/null || true
    bash auto/config
    mkdir -p .build
    # Se la cache bootstrap esiste lb chroot la usa direttamente.
    # Se non esiste (dopo lb clean senza --clean), facciamo prima bootstrap.
    if [[ ! -d cache/bootstrap ]]; then
        log "Cache bootstrap assente, eseguo bootstrap (~10 min)..."
        lb bootstrap 2>&1 | tee .build/build.log || err "lb bootstrap fallita"
    fi
    log "Rebuild chroot (~25-35 min)..."
    lb chroot 2>&1 | tee -a .build/build.log || err "lb chroot fallita"
    auraos_finalize_chroot
    log "Rebuild binary (~5-10 min)..."
    lb binary 2>&1 | tee -a .build/build.log || err "lb binary fallita"

else
    log "Sync config nel build dir..."
    rsync -aH --delete \
        "${RSYNC_EXCLUDES[@]}" \
        "$SCRIPT_DIR/" "$NATIVE_BUILD_DIR/"
    cd "$NATIVE_BUILD_DIR"

    lb clean --binary 2>/dev/null || true

    # lb clean --binary rimuove chroot.packages.live — lo ricreiamo subito.
    # Usiamo dpkg-query --admindir per leggere il db direttamente senza chroot.
    if [[ -d chroot/var/lib/dpkg ]]; then
        dpkg-query -W --admindir=chroot/var/lib/dpkg \
            > chroot.packages.live 2>/dev/null || touch chroot.packages.live
        cp chroot.packages.live chroot.packages.install 2>/dev/null || true
        dpkg-query -W --admindir=chroot/var/lib/dpkg \
            --showformat='${Package}:${Architecture}\t${Version}\n' \
            > chroot.packages-arch.live 2>/dev/null || true
        find chroot -printf '%P\n' 2>/dev/null | sort > chroot.files || true
        ok "chroot.packages.live ricreato ($(wc -l < chroot.packages.live) pacchetti)"
    else
        warn "chroot non trovato — skip manifest"
    fi

    bash auto/config
    mkdir -p .build
    auraos_finalize_chroot
    log "Rebuild binary only (~5-10 min)..."
    lb binary 2>&1 | tee .build/build.log || err "lb binary fallita"
fi

ISO_FILE=$(find "$NATIVE_BUILD_DIR" -maxdepth 1 -name "*.iso" | head -1)
if [[ -n "$ISO_FILE" ]]; then
    DEST="$ISO_OUTPUT_DIR/auraos-1.0-amd64.iso"
    log "Copia ISO in $DEST..."
    cp -f "$ISO_FILE" "$DEST"
    SIZE=$(du -sh "$DEST" | cut -f1)
    ok "=============================================="
    ok "BUILD COMPLETATO! ($MODE)"
    ok "ISO: $DEST"
    ok "Dimensione: $SIZE"
    ok "=============================================="
    echo ""
    log "Per testare: qemu-system-x86_64 -cdrom \"$DEST\" -m 4G -boot d -enable-kvm -cpu host"
    log "Per USB:     sudo dd if=\"$DEST\" of=/dev/sdX bs=4M status=progress conv=fsync"
else
    err "ISO non trovata. Log: $NATIVE_BUILD_DIR/.build/build.log"
fi
