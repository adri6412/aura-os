# AuraOS

AuraOS è una distribuzione Linux live/installabile basata su **Debian 13 (Trixie)**, costruita con [live-build](https://live-team.pages.debian.net/live-manual/).

Progettata per essere sicura, privata e con filesystem immutabile tramite OverlayFS.

---

## Caratteristiche

### Filesystem immutabile
- Root in sola lettura con OverlayFS; le modifiche persistono su una partizione dati separata (`auraos-data`) e sopravvivono ai riavvii
- Reset completo alle impostazioni di fabbrica con un comando

### Sicurezza
- **Kernel hardening** — ASLR massimo, kptr_restrict, ptrace_scope, TCP SYN cookies, blocco ICMP redirect/source routing, rp_filter
- **AppArmor** — abilitato in enforce mode con profili per browser e applicazioni
- **Firejail** — sandbox per Vivaldi e Thunderbird
- **AdGuard Home** — filtro DNS locale con DNSSEC, DoH upstream, blocco malware/pubblicità
- **UFW** — firewall con policy default-deny incoming
- **ClamAV** — antivirus con aggiornamento automatico definizioni
- **Fail2Ban** + **rkhunter** — intrusion prevention e rilevamento rootkit
- **unattended-upgrades** — aggiornamenti di sicurezza automatici

### Desktop
- **GNOME 46** con tema macOS (WhiteSur), Dash-to-Dock, Blur-My-Shell
- **Vivaldi** come browser predefinito (hardened: HTTPS-only, Safe Browsing, blocco popup/notifiche/geolocalizzazione)
- **Thunderbird** con telemetry disabilitata
- **LibreOffice**, **VLC**, GNOME Software + Flatpak

### Strumenti AuraOS
- **AuraOS Manager** — app GTK4 per gestione profili, aggiornamenti, kernel, stato sistema e **dashboard di sicurezza**
- `auraos-status/unlock/lock/update/reset` — gestione overlay da terminale
- `auraos-change-kernel` — installa/rimuovi kernel nel lower layer immutabile
- `auraos-security-audit` — audit Lynis con score salvato in cache

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

### 1. Scarica i pacchetti di terze parti

I pacchetti non distribuibili via git (Ivanti VPN, ecc.) vanno scaricati prima del build:

```bash
./download-extras.sh
```

Questo scarica i `.deb` in `config/packages.chroot/`. Se un URL non è più raggiungibile, puoi piazzare manualmente il file nella stessa directory — i nomi attesi sono documentati in `download-extras.sh`.

> **Nota:** i file in `config/packages.chroot/` sono esclusi da git (`.gitignore`).  
> Chiunque cloni il repo deve eseguire `download-extras.sh` prima di buildare.

### 2. Compila la ISO

```bash
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
├── download-extras.sh            # Scarica pacchetti non inclusi in git
├── bootstrap.sh                  # Aggiorna gli script auraos-* su sistemi installati
└── config/
    ├── bootloaders/              # GRUB (EFI) e Syslinux (BIOS) custom
    ├── hooks/
    │   ├── normal/               # Hook chroot (0010 base, 0045 overlay, 0050 hardening)
    │   └── binary/               # Hook binary stage
    ├── includes.chroot/          # File copiati direttamente nella ISO
    │   ├── etc/bluetooth/        # Configurazione bluetoothd (AutoEnable)
    │   ├── etc/calamares/        # Configurazione installer Calamares
    │   ├── etc/sysctl.d/         # Kernel hardening parameters
    │   ├── etc/systemd/          # Servizi systemd custom
    │   ├── opt/auraos-manager/   # AuraOS Manager (GTK4)
    │   ├── usr/local/sbin/       # Strumenti auraos-* (update/lock/unlock/audit/kernel)
    │   └── etc/initramfs-tools/  # Script OverlayFS nell'initramfs
    ├── package-lists/            # Liste pacchetti apt
    └── packages.chroot/          # .deb locali installati nel chroot (esclusi da git)
                                  # → riempire con download-extras.sh
```

---

## Filesystem immutabile

Il root è montato read-only; le modifiche utente vanno su una partizione `ext4` separata (label `auraos-data`) tramite OverlayFS. La struttura è:

```
lower  = partizione root (sola lettura, sistema base)
upper  = partizione auraos-data/.auraos-overlay/upper  (modifiche persistenti)
merged = / (quello che l'utente vede)
```

### Strumenti di gestione overlay

| Comando | Descrizione |
|---|---|
| `sudo auraos-status` | Mostra stato overlay (persistente/tmpfs) |
| `sudo auraos-unlock` | Sblocca il root reale in scrittura |
| `sudo auraos-lock`   | Torna in sola lettura |
| `sudo auraos-update` | Aggiorna il sistema (sblocca, apt upgrade, riblocca) |
| `sudo auraos-reset`  | Cancella l'upper layer (reset alle impostazioni di fabbrica) |
| `sudo auraos-change-kernel list\|install\|remove` | Gestione kernel nel lower layer |
| `sudo auraos-security-audit` | Esegue audit Lynis e salva lo score |

---

## Aggiornamenti su sistemi installati

Gli script `auraos-*` e il manager si aggiornano automaticamente senza rebuild della ISO:

```bash
sudo auraos-update
```

Per il primo aggiornamento (bootstrap):

```bash
curl -fsSL https://raw.githubusercontent.com/adri6412/aura-os/main/bootstrap.sh | sudo bash
sudo auraos-update
```

---

## Layout partizioni (installazione automatica)

| Partizione | Dimensione | Tipo | Etichetta |
|---|---|---|---|
| EFI | 800 MiB | FAT32 | EFI |
| Root | 10 GiB | ext4 | AuraOS |
| Dati overlay | Spazio rimanente | ext4 | auraos-data |

---

## Licenza

AuraOS build system è rilasciato sotto **GNU General Public License v3.0**.  
Vedi [LICENSE](LICENSE) per i dettagli.

I pacchetti installati nella ISO mantengono le rispettive licenze originali.  
Debian e i suoi componenti sono distribuiti secondo i termini della [Debian Free Software Guidelines](https://www.debian.org/social_contract#guidelines).
