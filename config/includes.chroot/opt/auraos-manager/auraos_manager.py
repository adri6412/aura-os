#!/usr/bin/env python3
# AuraOS Manager — gestione profili di sistema e aggiornamenti
# GTK4 + libadwaita, nessuna dipendenza extra rispetto a quelle già installate.

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, GLib, Gio

import json
import os
import subprocess
import tempfile
import threading
import urllib.request

INDEX_URL     = "https://adri6412.github.io/aura-os/profiles/index.json"
VERSIONS_FILE = "/etc/auraos/versions.conf"
ACTIVE_FILE   = "/etc/auraos/active-profiles.conf"

# Path completi — /usr/local/sbin non è nel PATH degli utenti normali
BIN_CHECK_UPDATES = "/usr/local/sbin/auraos-check-updates"
BIN_SWITCH        = "/usr/local/sbin/auraos-switch"
BIN_UPDATE        = "/usr/local/sbin/auraos-update"
BIN_STATUS        = "/usr/local/sbin/auraos-status"


# ── Helpers ───────────────────────────────────────────────────────────────────

def read_versions():
    versions = {}
    if os.path.exists(VERSIONS_FILE):
        with open(VERSIONS_FILE) as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    k, _, v = line.partition("=")
                    v = v.strip().strip('"')
                    if v:
                        versions[k.strip()] = v
    return versions


def read_active_profiles():
    active = set()
    if os.path.exists(ACTIVE_FILE):
        with open(ACTIVE_FILE) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    active.add(line)
    return active


def fetch_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "AuraOS-Manager/1.0"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return json.loads(r.read())


def run_privileged(args, output_callback=None):
    """Esegue un comando con pkexec; chiama output_callback(line) per ogni riga."""
    cmd = ["pkexec"] + args
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
    )
    if output_callback:
        for line in proc.stdout:
            GLib.idle_add(output_callback, line.rstrip())
    proc.wait()
    return proc.returncode


# ── Tab Profili ───────────────────────────────────────────────────────────────

class ProfilesPage(Gtk.Box):
    def __init__(self, win):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.win = win
        self._profiles = []
        self._active = set()
        self._rows = {}

        toolbar = Adw.HeaderBar()
        toolbar.set_show_end_title_buttons(False)
        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic",
                                 tooltip_text="Aggiorna lista")
        refresh_btn.connect("clicked", lambda *_: self._load())
        toolbar.pack_end(refresh_btn)
        self.append(toolbar)

        self._spinner = Gtk.Spinner(spinning=True, margin_top=48)
        self._status_lbl = Gtk.Label(label="Caricamento profili…",
                                     margin_top=8, margin_bottom=48)
        self._spinner_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL,
                                    valign=Gtk.Align.CENTER, vexpand=True)
        self._spinner_box.append(self._spinner)
        self._spinner_box.append(self._status_lbl)
        self.append(self._spinner_box)

        scroll = Gtk.ScrolledWindow(vexpand=True)
        self._list_box = Gtk.ListBox(css_classes=["boxed-list"],
                                     margin_top=12, margin_bottom=12,
                                     margin_start=12, margin_end=12,
                                     selection_mode=Gtk.SelectionMode.NONE)
        scroll.set_child(self._list_box)
        self._scroll = scroll
        scroll.set_visible(False)
        self.append(scroll)

        self._load()

    def _load(self):
        self._spinner_box.set_visible(True)
        self._scroll.set_visible(False)
        self._spinner.set_spinning(True)
        self._status_lbl.set_text("Caricamento profili…")
        threading.Thread(target=self._fetch, daemon=True).start()

    def _fetch(self):
        try:
            data = fetch_json(INDEX_URL)
            profiles = data.get("profiles", [])
            GLib.idle_add(self._populate, profiles, None)
        except Exception as e:
            GLib.idle_add(self._populate, [], str(e))

    def _populate(self, profiles, error):
        while (child := self._list_box.get_first_child()):
            self._list_box.remove(child)
        self._rows.clear()
        self._active = read_active_profiles()

        if error:
            self._status_lbl.set_text(f"Errore: {error}")
            self._spinner.set_spinning(False)
            return

        self._profiles = profiles
        if not profiles:
            self._status_lbl.set_text("Nessun profilo trovato.")
            self._spinner.set_spinning(False)
            return

        for p in profiles:
            row = self._make_row(p)
            self._list_box.append(row)
            self._rows[p["id"]] = row

        self._spinner_box.set_visible(False)
        self._scroll.set_visible(True)

    def _make_row(self, p):
        pid = p["id"]
        is_active = pid in self._active
        is_default = p.get("default", False)

        row = Adw.ActionRow(title=p["name"], subtitle=p.get("description", ""))

        if is_default:
            row.add_suffix(Gtk.Label(label="Default", css_classes=["dim-label"],
                                     valign=Gtk.Align.CENTER))
        if is_active:
            row.add_suffix(Gtk.Label(label="Attivo", css_classes=["success"],
                                     valign=Gtk.Align.CENTER))

        btn_label = "Rimuovi" if is_active else "Applica"
        btn_css = ["destructive-action"] if is_active else ["suggested-action"]
        btn = Gtk.Button(label=btn_label, valign=Gtk.Align.CENTER, css_classes=btn_css)
        btn.connect("clicked", self._on_action, p, is_active)
        row.add_suffix(btn)
        return row

    def _on_action(self, btn, profile, is_active):
        verb = "Rimuovere" if is_active else "Applicare"
        action = "revert" if is_active else "apply"
        dialog = Adw.AlertDialog(
            heading=f"{verb} profilo?",
            body=f"{profile['name']}\n\nSarà necessario riavviare il sistema."
        )
        dialog.add_response("cancel", "Annulla")
        dialog.add_response("ok", verb)
        dialog.set_response_appearance("ok",
            Adw.ResponseAppearance.DESTRUCTIVE if is_active
            else Adw.ResponseAppearance.SUGGESTED)
        dialog.set_default_response("ok")
        dialog.connect("response", self._on_confirm, profile, action)
        dialog.present(self.win)

    def _on_confirm(self, dialog, response, profile, action):
        if response != "ok":
            return
        self.win.show_progress(f"Operazione in corso: {profile['name']}…")
        threading.Thread(target=self._do_apply, args=(profile, action), daemon=True).start()

    def _do_apply(self, profile, action):
        try:
            if action == "apply":
                tmp = tempfile.NamedTemporaryFile(
                    suffix=".profile", delete=False,
                    prefix=f"auraos-{profile['id']}-"
                )
                req = urllib.request.Request(
                    profile["url"], headers={"User-Agent": "AuraOS-Manager/1.0"}
                )
                with urllib.request.urlopen(req, timeout=15) as r:
                    tmp.write(r.read())
                tmp.close()
                rc = run_privileged(
                    [BIN_SWITCH, "apply-from", tmp.name],
                    output_callback=lambda l: self.win.append_log(l)
                )
                os.unlink(tmp.name)
            else:
                rc = run_privileged(
                    [BIN_SWITCH, "revert", profile["id"]],
                    output_callback=lambda l: self.win.append_log(l)
                )
        except Exception as e:
            GLib.idle_add(self.win.show_error, str(e))
            return
        GLib.idle_add(self._after_apply, rc, profile)

    def _after_apply(self, rc, profile):
        self.win.hide_progress()
        if rc == 0:
            self._show_reboot_dialog(profile["name"])
            self._load()
        else:
            self.win.show_error("Operazione fallita. Controlla i log di sistema.")

    def _show_reboot_dialog(self, name):
        dialog = Adw.AlertDialog(
            heading="Riavvio richiesto",
            body=f"'{name}' applicato.\nRiavvia il sistema per attivare le modifiche."
        )
        dialog.add_response("later", "Dopo")
        dialog.add_response("reboot", "Riavvia ora")
        dialog.set_response_appearance("reboot", Adw.ResponseAppearance.SUGGESTED)
        dialog.connect("response", lambda d, r: subprocess.run(
            ["systemctl", "reboot"], check=False) if r == "reboot" else None)
        dialog.present(self.win)


# ── Tab Aggiornamenti ─────────────────────────────────────────────────────────

class UpdatesPage(Gtk.Box):
    def __init__(self, win):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.win = win

        toolbar = Adw.HeaderBar()
        toolbar.set_show_end_title_buttons(False)
        self.append(toolbar)

        scroll = Gtk.ScrolledWindow(vexpand=True)
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12,
                          margin_top=12, margin_bottom=12,
                          margin_start=12, margin_end=12)
        scroll.set_child(content)
        self.append(scroll)

        versions_group = Adw.PreferencesGroup(title="Componenti installati")
        content.append(versions_group)

        versions = read_versions()
        components = [
            ("AURAOS_VERSION",      "Script di sistema auraos-*"),
            ("ADGUARDHOME_VERSION", "AdGuard Home"),
        ]
        self._version_rows = {}
        for key, label in components:
            ver = versions.get(key, "non impostata")
            row = Adw.ActionRow(title=label, subtitle=f"Installata: {ver}")
            versions_group.add(row)
            self._version_rows[key] = row

        check_btn = Gtk.Button(label="Controlla aggiornamenti",
                               css_classes=["pill"],
                               halign=Gtk.Align.CENTER, margin_top=8)
        check_btn.connect("clicked", self._on_check)
        content.append(check_btn)

        self._check_lbl = Gtk.Label(label="", halign=Gtk.Align.CENTER,
                                    wrap=True, margin_top=4)
        content.append(self._check_lbl)

        self._update_btn = Gtk.Button(
            label="Aggiorna tutto",
            css_classes=["suggested-action", "pill"],
            halign=Gtk.Align.CENTER, margin_top=8, sensitive=False
        )
        self._update_btn.connect("clicked", self._on_update)
        content.append(self._update_btn)

        log_group = Adw.PreferencesGroup(title="Output", margin_top=12)
        content.append(log_group)
        sw = Gtk.ScrolledWindow(height_request=150)
        self._log_buf = Gtk.TextBuffer()
        self._log_view = Gtk.TextView(
            buffer=self._log_buf, editable=False, monospace=True,
            wrap_mode=Gtk.WrapMode.WORD_CHAR,
            css_classes=["card"], margin_top=4
        )
        sw.set_child(self._log_view)
        log_group.add(sw)

    def _on_check(self, btn):
        btn.set_sensitive(False)
        self._check_lbl.set_text("Controllo in corso…")
        self._update_btn.set_sensitive(False)
        threading.Thread(target=self._do_check, args=(btn,), daemon=True).start()

    def _do_check(self, btn):
        try:
            result = subprocess.run(
                [BIN_CHECK_UPDATES],
                capture_output=True, text=True
            )
            has_updates = result.returncode == 1
            output = result.stdout.strip() or result.stderr.strip()
            GLib.idle_add(self._after_check, btn, has_updates, output)
        except Exception as e:
            GLib.idle_add(self._after_check, btn, False, str(e))

    def _after_check(self, btn, has_updates, output):
        btn.set_sensitive(True)
        self._check_lbl.set_text(output)
        self._update_btn.set_sensitive(has_updates)

    def _on_update(self, btn):
        dialog = Adw.AlertDialog(
            heading="Aggiornare i componenti?",
            body="Verranno aggiornati gli script auraos-* e AdGuardHome.\n"
                 "Richiede connessione Internet e password amministratore."
        )
        dialog.add_response("cancel", "Annulla")
        dialog.add_response("ok", "Aggiorna")
        dialog.set_response_appearance("ok", Adw.ResponseAppearance.SUGGESTED)
        dialog.connect("response", self._on_confirm_update)
        dialog.present(self.win)

    def _on_confirm_update(self, dialog, response):
        if response != "ok":
            return
        self._update_btn.set_sensitive(False)
        self._log_buf.set_text("")
        self.win.show_progress("Aggiornamento in corso…")
        threading.Thread(target=self._do_update, daemon=True).start()

    def _do_update(self):
        rc = run_privileged(
            [BIN_UPDATE],
            output_callback=lambda l: GLib.idle_add(self._append_log, l)
        )
        GLib.idle_add(self._after_update, rc)

    def _append_log(self, line):
        end = self._log_buf.get_end_iter()
        self._log_buf.insert(end, line + "\n")
        adj = self._log_view.get_parent().get_vadjustment()
        adj.set_value(adj.get_upper())

    def _after_update(self, rc):
        self.win.hide_progress()
        msg = "Aggiornamento completato." if rc == 0 else f"Aggiornamento fallito (exit {rc})."
        self._check_lbl.set_text(msg)
        versions = read_versions()
        for key, label in [("AURAOS_VERSION", "Script di sistema auraos-*"),
                            ("ADGUARDHOME_VERSION", "AdGuard Home")]:
            ver = versions.get(key, "non impostata")
            self._version_rows[key].set_subtitle(f"Installata: {ver}")


# ── Tab Sistema ───────────────────────────────────────────────────────────────

class SystemPage(Gtk.Box):
    def __init__(self, win):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.win = win

        toolbar = Adw.HeaderBar()
        toolbar.set_show_end_title_buttons(False)
        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic",
                                 tooltip_text="Aggiorna")
        refresh_btn.connect("clicked", lambda *_: self._load())
        toolbar.pack_end(refresh_btn)
        self.append(toolbar)

        scroll = Gtk.ScrolledWindow(vexpand=True)
        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12,
                          margin_top=12, margin_bottom=12,
                          margin_start=12, margin_end=12)
        scroll.set_child(content)
        self.append(scroll)

        status_group = Adw.PreferencesGroup(title="Stato filesystem")
        content.append(status_group)

        sw = Gtk.ScrolledWindow(height_request=200)
        self._status_buf = Gtk.TextBuffer()
        self._status_view = Gtk.TextView(
            buffer=self._status_buf, editable=False, monospace=True,
            wrap_mode=Gtk.WrapMode.WORD_CHAR,
            css_classes=["card"], margin_top=4
        )
        sw.set_child(self._status_view)
        status_group.add(sw)

        # Sezione versioni installate
        ver_group = Adw.PreferencesGroup(title="Versioni componenti", margin_top=8)
        content.append(ver_group)
        self._ver_rows = {}
        for key, label in [("AURAOS_VERSION", "Script auraos-*"),
                            ("ADGUARDHOME_VERSION", "AdGuard Home")]:
            row = Adw.ActionRow(title=label)
            ver_group.add(row)
            self._ver_rows[key] = row

        self._load()

    def _load(self):
        threading.Thread(target=self._fetch_status, daemon=True).start()
        self._refresh_versions()

    def _fetch_status(self):
        try:
            result = subprocess.run(
                [BIN_STATUS], capture_output=True, text=True, timeout=10
            )
            text = result.stdout or result.stderr or "(nessun output)"
        except FileNotFoundError:
            text = f"Comando non trovato: {BIN_STATUS}"
        except Exception as e:
            text = str(e)
        GLib.idle_add(self._status_buf.set_text, text)

    def _refresh_versions(self):
        versions = read_versions()
        for key, row in self._ver_rows.items():
            ver = versions.get(key, "non impostata")
            row.set_subtitle(ver)


# ── Finestra principale ───────────────────────────────────────────────────────

class AuraOSManagerWindow(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="AuraOS Manager",
                         default_width=720, default_height=600)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.set_content(outer)

        header = Adw.HeaderBar()
        self._stack = Adw.ViewStack()
        switcher = Adw.ViewSwitcher(stack=self._stack,
                                    policy=Adw.ViewSwitcherPolicy.WIDE)
        header.set_title_widget(switcher)
        outer.append(header)

        self._toast = Adw.ToastOverlay()
        self._toast.set_child(self._stack)
        outer.append(self._toast)

        self._progress = Gtk.ProgressBar(pulse_step=0.15)
        self._progress.set_visible(False)
        outer.append(self._progress)

        profiles_page = ProfilesPage(self)
        self._stack.add_titled_with_icon(
            profiles_page, "profiles", "Profili", "preferences-system-symbolic"
        )

        updates_page = UpdatesPage(self)
        self._updates_page = updates_page
        self._stack.add_titled_with_icon(
            updates_page, "updates", "Aggiornamenti", "software-update-available-symbolic"
        )

        system_page = SystemPage(self)
        self._stack.add_titled_with_icon(
            system_page, "system", "Sistema", "drive-harddisk-symbolic"
        )

        self._pulse_id = None

    def show_progress(self, msg):
        self._progress.set_visible(True)
        self._pulse_id = GLib.timeout_add(200, self._pulse)

    def _pulse(self):
        self._progress.pulse()
        return True

    def hide_progress(self):
        if self._pulse_id:
            GLib.source_remove(self._pulse_id)
            self._pulse_id = None
        self._progress.set_visible(False)

    def append_log(self, line):
        self._updates_page._append_log(line)

    def show_error(self, msg):
        self._toast.add_toast(Adw.Toast(title=msg, timeout=5))


# ── App ───────────────────────────────────────────────────────────────────────

class AuraOSManagerApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id="it.auraos.Manager",
                         flags=Gio.ApplicationFlags.FLAGS_NONE)

    def do_activate(self):
        win = self.get_active_window()
        if not win:
            win = AuraOSManagerWindow(self)
        win.present()


if __name__ == "__main__":
    import sys
    # Supporto --page=<name> per aprire direttamente una tab specifica
    start_page = None
    filtered = [sys.argv[0]]
    for arg in sys.argv[1:]:
        if arg.startswith("--page="):
            start_page = arg.split("=", 1)[1]
        else:
            filtered.append(arg)

    if start_page:
        _orig_activate = AuraOSManagerApp.do_activate
        def _activate_with_page(self):
            _orig_activate(self)
            win = self.get_active_window()
            if win and start_page:
                win._stack.set_visible_child_name(start_page)
        AuraOSManagerApp.do_activate = _activate_with_page

    app = AuraOSManagerApp()
    sys.exit(app.run(filtered))
