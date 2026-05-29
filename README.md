# AuraOS

AuraOS è una distribuzione Linux live/installabile basata su **Debian 13 (Trixie)**, costruita con [live-build](https://live-team.pages.debian.net/live-manual/).

Progettata per essere sicura, semplice e con filesystem immutabile tramite OverlayFS.

---

## Caratteristiche

- **Filesystem immutabile** — root in sola lettura con OverlayFS; le modifiche vanno su una partizione dati separata (`auraos-data`) e sopravvivono ai riavvii
- **Desktop GNOME** con tema macOS e estensioni personalizzate
- **Installer grafico** Calamares integrato nel live (sessione kiosk)
- **AdGuard Home** preconfigurato come filtro DNS locale (anti-pubblicità/malware)
- **Protezione** — UFW, ClamAV, Fail2Ban, rkhunter attivi di default
- **Vivaldi** come browser predefinito
- **RustDesk** per assistenza remota

---

## Requisiti di build

- Debian 13 (Trixie) o derivata — **non funziona su Windows/macOS direttamente**
- Se il progetto è su NTFS/WSL, il build script gestisce automaticamente la build in `/var/tmp/`
- Pacchetti: `live-build`, `debootstrap`, `squashfs-tools`, `xorriso`  
  (installati automaticamente da `build.sh`)
- Accesso root (`sudo`)
- ~20 GB di spazio libero, connessione internet

---

## Build

```bash
# Clona il repo
git clone https://github.com/adri6412/aura-os.git
cd aura-os

# Build veloce: aggiorna i file nel chroot esistente e ricostruisce solo la ISO (~5-10 min)
sudo ./build.sh

# Build media: ricostruisce il chroot mantenendo la cache dei pacchetti (~30-40 min)
sudo ./build.sh --chroot

# Build completa da zero (~60 min)
sudo ./build.sh --clean
```

La ISO viene salvata in `output/auraos-1.0-amd64.iso`.

### Test con QEMU

```bash
qemu-system-x86_64 -cdrom output/auraos-1.0-amd64.iso -m 4G -boot d -enable-kvm -cpu host
```

### Scrittura su USB

```bash
sudo dd if=output/auraos-1.0-amd64.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

---

## Struttura del progetto

```
aura-os/
├── auto/config                   # Configurazione live-build (lb config)
├── build.sh                      # Script di build principale
└── config/
    ├── bootloaders/              # GRUB (EFI) e Syslinux (BIOS) custom
    ├── hooks/
    │   ├── normal/               # Hook chroot personalizzati (0010-0045)
    │   └── binary/               # Hook binary (symlink, permessi)
    ├── includes.chroot/          # File copiati direttamente nella ISO
    │   ├── etc/calamares/        # Configurazione installer Calamares
    │   ├── etc/systemd/          # Servizi systemd custom
    │   ├── lib/live/config/      # Hook live-config (avvio sessione)
    │   ├── usr/local/sbin/       # Strumenti auraos-* (update/lock/unlock)
    │   └── etc/initramfs-tools/  # Script OverlayFS nell'initramfs
    └── package-lists/            # Liste pacchetti apt
```

---

## Filesystem immutabile

Il root è montato read-only; le modifiche utente vanno su una partizione `ext4` separata (label `auraos-data`) tramite OverlayFS. La struttura è:

```
lower  = partizione root (sola lettura, sistema base)
upper  = partizione auraos-data/.auraos-overlay/upper  (modifiche persistenti)
merged = / (quello che l'utente vede)
```

### Strumenti di gestione

| Comando | Descrizione |
|---|---|
| `sudo auraos-status` | Mostra stato overlay (persistente/tmpfs) |
| `sudo auraos-unlock` | Sblocca il root reale in scrittura |
| `sudo auraos-lock`   | Torna in sola lettura |
| `sudo auraos-update` | Aggiorna il sistema (sblocca, apt upgrade, ribloccca) |
| `sudo auraos-reset`  | Cancella l'upper layer (reset alle impostazioni di fabbrica) |

---

## Layout partizioni (installazione automatica)

| Partizione | Dimensione | Tipo | Etichetta |
|---|---|---|---|
| EFI | 800 MiB | FAT32 | EFI |
| Root | 15 GiB | ext4 | AuraOS |
| Dati overlay | Spazio rimanente | ext4 | auraos-data |

---

## Licenza

AuraOS build system è rilasciato sotto **GNU General Public License v3.0**.  
Vedi [LICENSE](LICENSE) per i dettagli.

I pacchetti installati nella ISO mantengono le rispettive licenze originali.  
Debian e i suoi componenti sono distribuiti secondo i termini della [Debian Free Software Guidelines](https://www.debian.org/social_contract#guidelines).
