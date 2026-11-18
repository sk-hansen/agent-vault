#!/usr/bin/env python3
"""Agent Vault — GTK4/libadwaita window for the agent secret vault.

Fedora/COSMIC port of the Omarchy bar widget in the repo root. Same scope:
Secret Service items tagged `vault=agent name=<name>`, labelled
`agent-vault: <name>` (what pi's secret-vault.ts and `secret-tool` use).
Values are never rendered; copying pipes them to `wl-copy`.

Keys: / filter · Enter/y copy · a add · e edit · d delete (twice) · r refresh · Esc close
"""
import subprocess
import sys
from datetime import datetime

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
gi.require_version("Secret", "1")
from gi.repository import Adw, Gdk, Gio, GLib, Gtk, Secret  # noqa: E402

APP_ID = "dk.skh.AgentVault"
LABEL_PREFIX = "agent-vault: "
# DONT_MATCH_NAME: match items stored by secret-tool, which carry no xdg:schema.
SCHEMA = Secret.Schema.new(
    "org.freedesktop.Secret.Generic",
    Secret.SchemaFlags.DONT_MATCH_NAME,
    {"vault": Secret.SchemaAttributeType.STRING, "name": Secret.SchemaAttributeType.STRING},
)


def attrs(name=None):
    a = {"vault": "agent"}
    if name is not None:
        a["name"] = name
    return a


def list_secrets():
    """[(name, modified_epoch)] sorted by name — never loads values."""
    service = Secret.Service.get_sync(Secret.ServiceFlags.OPEN_SESSION, None)
    items = service.search_sync(SCHEMA, attrs(), Secret.SearchFlags.ALL | Secret.SearchFlags.UNLOCK, None)
    out = []
    for item in items:
        name = item.get_attributes().get("name") or item.get_label().removeprefix(LABEL_PREFIX)
        out.append((name, item.get_modified()))
    return sorted(out)


def lookup(name):
    return Secret.password_lookup_sync(SCHEMA, attrs(name), None)


def store(name, value):
    Secret.password_store_sync(SCHEMA, attrs(name), Secret.COLLECTION_DEFAULT, LABEL_PREFIX + name, value, None)


def clear(name):
    Secret.password_clear_sync(SCHEMA, attrs(name), None)


def relative(epoch):
    secs = max(0, int(datetime.now().timestamp() - epoch))
    for unit, size in (("day", 86400), ("hour", 3600), ("minute", 60)):
        if secs >= size:
            n = secs // size
            return f"{n} {unit}{'s' if n != 1 else ''} ago"
    return "just now"


HINTS = "<b>/</b> filter   <b>Enter</b> copy   <b>a</b> add   <b>e</b> edit   <b>d d</b> delete   <b>r</b> refresh"


class VaultWindow(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Agent Vault", default_width=560, default_height=680)
        self.secrets = []
        self.rows = {}  # name -> Adw.ActionRow
        self.armed = None  # (name, timeout source id) awaiting a second delete press
        self.editing = None  # name being edited, None when adding

        # ---- header ---------------------------------------------------------
        self.heading = Adw.WindowTitle(title="Agent Vault")
        title_box = Gtk.Box(spacing=8, halign=Gtk.Align.CENTER)
        title_box.append(Gtk.Image(icon_name=APP_ID, pixel_size=28))
        title_box.append(self.heading)
        header = Adw.HeaderBar(title_widget=title_box)
        self.add_btn = Gtk.ToggleButton(icon_name="list-add-symbolic", tooltip_text="Add secret (a)")
        self.add_btn.connect("toggled", self._on_add_toggled)
        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic", tooltip_text="Refresh (r)")
        refresh_btn.connect("clicked", lambda *_: self.refresh())
        header.pack_start(self.add_btn)
        header.pack_end(refresh_btn)

        # ---- inline add/edit form (survives switching apps to fetch a value) --
        self.form_group = Adw.PreferencesGroup()
        self.name_row = Adw.EntryRow(title="Name")
        self.value_row = Adw.PasswordEntryRow(title="Value")
        for r in (self.name_row, self.value_row):
            r.connect("changed", self._validate)
            r.connect("entry-activated", lambda *_: self.save())
            self.form_group.add(r)
        self.save_btn = Gtk.Button(label="Save", css_classes=["suggested-action", "pill"])
        self.save_btn.connect("clicked", lambda *_: self.save())
        cancel_btn = Gtk.Button(label="Cancel", css_classes=["pill"])
        cancel_btn.connect("clicked", lambda *_: self.close_form())
        buttons = Gtk.Box(spacing=8, halign=Gtk.Align.END, margin_top=12)
        buttons.append(cancel_btn)
        buttons.append(self.save_btn)
        form = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, margin_top=12, margin_bottom=6)
        form.append(self.form_group)
        form.append(buttons)
        self.form = Gtk.Revealer(child=self._clamp(form), transition_type=Gtk.RevealerTransitionType.SLIDE_DOWN)

        # ---- filter + list --------------------------------------------------
        self.search = Gtk.SearchEntry(placeholder_text="Filter secrets", margin_top=6)
        self.search.connect("search-changed", lambda *_: self._refilter())
        self.search.connect("activate", lambda *_: self.copy_selected())
        self.search.connect("stop-search", lambda *_: self._focus_list())

        self.listbox = Gtk.ListBox(selection_mode=Gtk.SelectionMode.SINGLE, valign=Gtk.Align.START,
                                   css_classes=["boxed-list"])
        self.listbox.set_filter_func(self._filter)
        self.listbox.set_placeholder(Gtk.Label(label="No matches", css_classes=["dim-label"],
                                               margin_top=18, margin_bottom=18))
        self.listbox.connect("row-activated", lambda *_: self.copy_selected())
        self.listbox.connect("row-selected", lambda *_: self.disarm())

        add_first = Gtk.Button(label="Add secret", halign=Gtk.Align.CENTER, css_classes=["suggested-action", "pill"])
        add_first.connect("clicked", lambda *_: self.open_form())
        empty = Adw.StatusPage(icon_name=APP_ID, title="Vault is empty", child=add_first,
                               description="Agents can only use secrets you add here.\n"
                                           "pi refers to them as {{secret:name}} and never sees the value.")
        self.stack = Gtk.Stack(vexpand=True, transition_type=Gtk.StackTransitionType.CROSSFADE)
        list_page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12, margin_bottom=12)
        list_page.append(self._clamp(self.search))
        list_page.append(self._clamp(self.listbox))
        self.stack.add_named(Gtk.ScrolledWindow(child=list_page, hscrollbar_policy=Gtk.PolicyType.NEVER), "list")
        self.stack.add_named(empty, "empty")

        content = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        content.append(self.form)
        content.append(self.stack)

        footer = Gtk.Label(use_markup=True, label=HINTS, css_classes=["dim-label", "caption"],
                           margin_top=8, margin_bottom=8, wrap=True, justify=Gtk.Justification.CENTER)
        view = Adw.ToolbarView(content=content)
        view.add_top_bar(header)
        view.add_bottom_bar(footer)
        self.toasts = Adw.ToastOverlay(child=view)
        self.set_content(self.toasts)

        keys = Gtk.EventControllerKey()
        keys.connect("key-pressed", self._on_key)
        self.add_controller(keys)

        self.refresh()

    @staticmethod
    def _clamp(child):
        return Adw.Clamp(child=child, maximum_size=600, margin_start=12, margin_end=12)

    # ---- data ---------------------------------------------------------------
    def refresh(self):
        try:
            self.secrets = list_secrets()
        except GLib.Error as e:
            self.secrets = []
            self.toast(f"Could not read the keyring: {e.message}")
        self.disarm()
        self.listbox.remove_all()
        self.rows = {}
        for name, modified in self.secrets:
            self.listbox.append(self._make_row(name, modified))
        n = len(self.secrets)
        self.heading.set_subtitle(f"{n} secret{'s' if n != 1 else ''}")
        self.stack.set_visible_child_name("list" if self.secrets else "empty")
        self._select_first_visible()

    def _make_row(self, name, modified):
        row = Adw.ActionRow(title=name, subtitle=f"Changed {relative(modified)}", activatable=True,
                            tooltip_text=datetime.fromtimestamp(modified).strftime("%Y-%m-%d %H:%M"))
        row.secret_name = name

        def button(icon, tip, cb):
            b = Gtk.Button(icon_name=icon, tooltip_text=tip, valign=Gtk.Align.CENTER, css_classes=["flat"])
            b.connect("clicked", lambda *_: cb(name))
            row.add_suffix(b)
            return b

        row.copy_btn = button("edit-copy-symbolic", "Copy value (Enter)", self.copy)
        button("document-edit-symbolic", "Replace value (e)", self.open_form)
        row.del_btn = button("user-trash-symbolic", "Delete (d twice)", self.delete)
        self.rows[name] = row
        return row

    def _filter(self, row):
        q = self.search.get_text().strip().lower()
        return not q or q in row.secret_name.lower()

    def _visible_rows(self):
        return [r for r in self.rows.values() if self._filter(r)]

    def _refilter(self):
        self.listbox.invalidate_filter()
        sel = self.listbox.get_selected_row()
        if sel is None or not self._filter(sel):
            self._select_first_visible()

    def _select_first_visible(self):
        visible = self._visible_rows()
        self.listbox.select_row(visible[0] if visible else None)

    def _focus_list(self):
        row = self.listbox.get_selected_row()
        (row or self.listbox).grab_focus()

    def selected_name(self):
        row = self.listbox.get_selected_row()
        return row.secret_name if row is not None and self._filter(row) else None

    # ---- actions ------------------------------------------------------------
    def toast(self, text):
        self.toasts.add_toast(Adw.Toast(title=text, timeout=2))

    def copy(self, name):
        try:
            value = lookup(name)
        except GLib.Error as e:
            return self.toast(f"Lookup failed: {e.message}")
        if value is None:
            return self.toast(f"'{name}' not found")
        # wl-copy keeps serving the clipboard after this window closes; a
        # GdkClipboard would lose the value on exit.
        subprocess.run(["wl-copy", "--type", "text/plain"], input=value.encode(), check=False)
        self.toast(f"Copied '{name}'")
        btn = self.rows[name].copy_btn
        btn.set_icon_name("object-select-symbolic")
        GLib.timeout_add(1500, lambda: btn.set_icon_name("edit-copy-symbolic") or False)

    def copy_selected(self):
        if name := self.selected_name():
            self.copy(name)

    def delete(self, name):
        if self.armed and self.armed[0] == name:
            self.disarm()
            try:
                clear(name)
            except GLib.Error as e:
                return self.toast(f"Delete failed: {e.message}")
            self.toast(f"Deleted '{name}'")
            return self.refresh()
        self.disarm()
        btn = self.rows[name].del_btn
        btn.set_label("Delete?")  # replaces the icon until disarmed
        btn.set_css_classes(["destructive-action"])
        self.armed = (name, GLib.timeout_add(3000, self._disarm_timeout))

    def _disarm_timeout(self):
        self.armed = (self.armed[0], 0)  # source is finishing, don't remove it twice
        self.disarm()
        return False

    def disarm(self):
        if not self.armed:
            return
        name, source = self.armed
        self.armed = None
        if source:
            GLib.source_remove(source)
        if row := self.rows.get(name):
            row.del_btn.set_icon_name("user-trash-symbolic")
            row.del_btn.set_css_classes(["flat"])

    # ---- inline form --------------------------------------------------------
    def open_form(self, name=None):
        self.editing = name
        self.form_group.set_title(f"Replace '{name}'" if name else "Add secret")
        self.form_group.set_description("The new value overwrites the stored one." if name else None)
        self.name_row.set_text(name or "")
        self.name_row.set_editable(name is None)
        self.value_row.set_text("")
        self._validate()
        self.form.set_reveal_child(True)
        self.add_btn.set_active(True)
        (self.value_row if name else self.name_row).grab_focus()

    def close_form(self):
        self.form.set_reveal_child(False)
        self.add_btn.set_active(False)
        self.value_row.set_text("")
        self._focus_list()

    def _on_add_toggled(self, btn):
        if btn.get_active() and not self.form.get_reveal_child():
            self.open_form()
        elif not btn.get_active() and self.form.get_reveal_child():
            self.close_form()

    def _validate(self, *_):
        self.save_btn.set_sensitive(bool(self.name_row.get_text().strip() and self.value_row.get_text()))

    def save(self):
        if not self.save_btn.get_sensitive():
            return
        name, value = self.name_row.get_text().strip(), self.value_row.get_text()
        existed = name in self.rows
        try:
            store(name, value)
        except GLib.Error as e:
            return self.toast(f"Store failed: {e.message}")
        self.close_form()
        self.toast(("Updated '" if existed else "Stored '") + name + "'")
        self.refresh()
        if row := self.rows.get(name):
            self.listbox.select_row(row)

    # ---- keys ---------------------------------------------------------------
    def _focus_in(self, widget):
        focus = self.get_focus()
        return focus is not None and (focus == widget or focus.is_ancestor(widget))

    def _on_key(self, _ctrl, keyval, _code, state):
        key = Gdk.keyval_name(keyval)
        if self.form.get_reveal_child() and self._focus_in(self.form):
            if key == "Escape":
                self.close_form()
                return True
            return False
        if self._focus_in(self.search):
            return False
        if state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.ALT_MASK):
            return False
        name = self.selected_name()
        if key == "Escape":
            if self.armed:
                self.disarm()
            else:
                self.close()
        elif key == "slash":
            self.search.grab_focus()
        elif key in ("Return", "KP_Enter", "y") and name:
            self.copy(name)
        elif key == "a":
            self.open_form()
        elif key == "e" and name:
            self.open_form(name)
        elif key == "d" and name:
            self.delete(name)
        elif key == "r":
            self.refresh()
        else:
            return False
        return True


class VaultApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id=APP_ID, flags=Gio.ApplicationFlags.DEFAULT_FLAGS)

    def do_startup(self):
        Adw.Application.do_startup(self)
        Gtk.Window.set_default_icon_name(APP_ID)

    def do_activate(self):
        win = self.get_active_window() or VaultWindow(self)
        win.present()


if __name__ == "__main__":
    sys.exit(VaultApp().run(sys.argv))
