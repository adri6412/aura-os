#!/bin/bash
# Marca i .desktop su ~/Desktop come eseguibili e trusted.
# Attende che gvfs-metadata sia pronto prima di usare gio set,
# altrimenti gio set fallisce silenziosamente e le icone restano non trusted.
_wait_gvfs() {
    for i in $(seq 1 15); do
        gio info "$HOME" &>/dev/null 2>&1 && return 0
        sleep 1
    done
    return 1
}

_wait_gvfs

for f in "$HOME/Desktop"/*.desktop; do
    [ -f "$f" ] || continue
    chmod +x "$f" 2>/dev/null || true
    gio set -t string "$f" "metadata::trusted" "yes" 2>/dev/null || true
done
