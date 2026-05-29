#!/bin/bash
# Marca i .desktop su ~/Desktop come eseguibili e trusted per GNOME 43+
for f in "$HOME/Desktop"/*.desktop; do
    [ -f "$f" ] || continue
    chmod +x "$f" 2>/dev/null
    gio set "$f" metadata::trusted true 2>/dev/null
done
