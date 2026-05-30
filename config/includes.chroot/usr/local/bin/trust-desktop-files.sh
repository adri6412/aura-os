#!/bin/bash
# Marca i .desktop su ~/Desktop come eseguibili e trusted
# GNOME 44+: basta il bit eseguibile
# GNOME < 44: serve anche metadata::trusted
for f in "$HOME/Desktop"/*.desktop; do
    [ -f "$f" ] || continue
    chmod +x "$f" 2>/dev/null || true
    gio set -t string "$f" "metadata::trusted" "yes" 2>/dev/null || true
done
