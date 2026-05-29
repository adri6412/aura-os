#!/bin/bash
# Fallback: avvia Calamares in kiosk se per qualche motivo
# la sessione openbox non è partita e si è avviato GNOME.
# NON tocca il tema o le estensioni GNOME.

# Solo in ambiente live
grep -q "boot=live" /proc/cmdline 2>/dev/null || exit 0

# Se la sessione kiosk openbox è già attiva, non fare nulla
pgrep -x calamares >/dev/null 2>&1 && exit 0

# Aspetta che GNOME Shell sia pronto
for i in $(seq 1 40); do
    wmctrl -l 2>/dev/null | grep -q . && break
    sleep 1
done
sleep 2

# Avvia Calamares come root (fullscreen via wmctrl dopo l'avvio)
sudo -E calamares &
CAL_PID=$!

for i in $(seq 1 25); do
    if wmctrl -l 2>/dev/null | grep -qi "calamares"; then
        wmctrl -r "Calamares" -b add,fullscreen 2>/dev/null || true
        break
    fi
    sleep 1
done

wait $CAL_PID 2>/dev/null
