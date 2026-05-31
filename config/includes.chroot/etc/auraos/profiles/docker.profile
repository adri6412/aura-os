# AuraOS Profile — Docker CE
PROFILE_NAME="Docker CE"
PROFILE_DESC="Docker Engine + Compose + Buildx — installato nell'upper layer (non persiste ad auraos-reset)"

# Installazione nell'upper layer: i pacchetti vengono installati sul sistema
# in esecuzione, non nel lower layer immutabile. Docker e le sue immagini/volumi
# vengono persi se si esegue auraos-reset. Usare 'docker save' prima del reset.
INSTALL_UPPER=true

REMOVE_PACKAGES=""
INSTALL_PACKAGES=""
DISABLE_SERVICES=""
ENABLE_SERVICES=""

CUSTOM_APPLY_SCRIPT='
set -e

echo "[docker] Aggiunta chiave GPG e repository Docker CE..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
    -o /etc/apt/keyrings/docker.asc \
    || { echo "[docker] ERRORE: impossibile scaricare la chiave GPG Docker." >&2; exit 1; }
chmod a+r /etc/apt/keyrings/docker.asc

# Rileva il codename Debian; se non supportato da Docker CE usa bookworm
DISTRO=$(. /etc/os-release 2>/dev/null && echo "${VERSION_CODENAME:-bookworm}" || echo "bookworm")
DOCKER_DIST=""
for codename in "$DISTRO" bookworm; do
    HTTP=$(curl -s -o /dev/null -w "%{http_code}" \
        "https://download.docker.com/linux/debian/dists/${codename}/Release" 2>/dev/null || true)
    if [[ "$HTTP" == "200" ]]; then
        DOCKER_DIST="$codename"
        break
    fi
done
DOCKER_DIST="${DOCKER_DIST:-bookworm}"
echo "[docker] Utilizzo repo Docker per: $DOCKER_DIST"

echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/debian ${DOCKER_DIST} stable" \
    > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

# ── Fix overlay-on-overlay ────────────────────────────────────────────────────
# AuraOS usa overlayfs come root filesystem. Docker e containerd usano
# overlayfs per i layer dei container: il kernel rifiuta overlay annidati
# ("invalid argument"). La soluzione è puntare sia Docker (data-root) che
# containerd (root) direttamente all ext4 della partizione auraos-data
# accessibile via /run/aura-rw, bypassando il layer overlay.
CONF=/etc/auraos/overlay.conf
if [[ -f "$CONF" ]]; then
    OVERLAY_SUBDIR=""
    . "$CONF"
    SUBDIR="${OVERLAY_SUBDIR:-.auraos-overlay}"
    EXT4="/run/aura-rw/${SUBDIR}/upper"

    # Docker data-root su ext4
    mkdir -p "$EXT4/var/lib/docker" /etc/docker
    echo "{\"data-root\": \"$EXT4/var/lib/docker\"}" > /etc/docker/daemon.json
    echo "[docker] data-root → $EXT4/var/lib/docker"

    # Containerd root su ext4 (snapshotter overlay separato da Docker)
    mkdir -p "$EXT4/var/lib/containerd" /etc/containerd
    containerd config default > /etc/containerd/config.toml
    sed -i "s|^root = .*|root = \"$EXT4/var/lib/containerd\"|" /etc/containerd/config.toml
    echo "[docker] containerd root → $EXT4/var/lib/containerd"
else
    echo "[docker] WARN: overlay.conf non trovato — Docker potrebbe non funzionare su AuraOS overlayfs."
fi

systemctl enable docker
systemctl restart docker

# Aggiunge l utente principale al gruppo docker
MAIN_USER=$(loginctl list-users --no-legend 2>/dev/null \
    | awk '"'"'$1 > 999 && $1 < 65000 {print $2; exit}'"'"')
if [[ -n "$MAIN_USER" ]]; then
    usermod -aG docker "$MAIN_USER"
    echo "[docker] Utente $MAIN_USER aggiunto al gruppo docker."
    echo "[docker] Fai logout e login per usare Docker senza sudo."
fi

echo "[docker] Installazione completata. Versione:"
docker --version
'

CUSTOM_REVERT_SCRIPT='
set -e

echo "[docker] Rimozione Docker CE..."
systemctl stop docker docker.socket containerd 2>/dev/null || true
systemctl disable docker docker.socket 2>/dev/null || true

apt-get remove --purge -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
apt-get autoremove --purge -y 2>/dev/null || true

rm -f /etc/apt/sources.list.d/docker.list \
      /etc/apt/keyrings/docker.asc \
      /etc/docker/daemon.json \
      /etc/containerd/config.toml
apt-get update -qq

echo "[docker] Docker rimosso. Le immagini in /var/lib/docker sono ancora presenti."
echo "[docker] Per rimuoverle: sudo rm -rf /var/lib/docker"
'
