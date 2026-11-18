#!/usr/bin/env bash
# Install Agent Vault for the current user (symlinks, so edits in the repo apply).
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
missing=()
for c in secret-tool wl-copy; do command -v "$c" >/dev/null || missing+=("$c"); done
python3 -c 'import gi; [gi.require_version(n, v) for n, v in (("Gtk","4.0"),("Adw","1"),("Secret","1"))]' 2>/dev/null \
  || missing+=("python3-gobject gtk4 libadwaita libsecret")
if ((${#missing[@]})); then
  echo "Missing: ${missing[*]}  ->  sudo dnf install python3-gobject gtk4 libadwaita libsecret wl-clipboard" >&2
  exit 1
fi
mkdir -p ~/.local/bin ~/.local/share/applications
ln -sf "$here/agent-vault.py" ~/.local/bin/agent-vault
# Copied, not symlinked: some launchers skip symlinked desktop entries.
cp --remove-destination "$here/agent-vault.desktop" ~/.local/share/applications/dk.skh.AgentVault.desktop
for f in "$here"/icons/hicolor/*/apps/*.png; do
  dest=~/.local/share/icons/hicolor/${f#"$here"/icons/hicolor/}
  mkdir -p "$(dirname "$dest")" && ln -sf "$f" "$dest"
done
# Non-GTK icon loaders (COSMIC) only scan theme dirs that carry an index.theme.
[ -e ~/.local/share/icons/hicolor/index.theme ] || ln -s /usr/share/icons/hicolor/index.theme ~/.local/share/icons/hicolor/index.theme
gtk-update-icon-cache -f -t ~/.local/share/icons/hicolor 2>/dev/null || true
update-desktop-database ~/.local/share/applications 2>/dev/null || true
echo "Installed: run 'agent-vault' or launch 'Agent Vault' from the launcher."
