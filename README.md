# Agent Vault — Omarchy bar widget

An agent secret vault on **gnome-keyring**: secrets live as ordinary keyring
items tagged `vault=agent name=<name>`, so agents (via pi's `secret_*` tools)
only see what you deliberately put in the vault — never the rest of your
keyring. The keyring unlocks with your login session; nothing extra to manage.

Bar: `󰌾 3` (lock + secret count; middle-click refreshes).

Panel:

- **Secret list** with `/` filter — Enter/click/`y` copies the value to the
  clipboard (`wl-copy`); the value never renders on screen.
- **`a` Add** — name + masked value field, stored via `secret-tool`.
- **`e` Edit** — add form prefilled with the selected name; a new value replaces it.
- **`d` Delete ×2** — two-press confirm.

## Agent side (pi)

`~/.pi/agent/extensions/secret-vault.ts` exposes `secret_list`, `secret_get`,
`secret_set`, `secret_delete` over the same scope. CLI equivalent:

```bash
printf '%s' "$VALUE" | secret-tool store --label='agent-vault: my-token' vault agent name my-token
secret-tool lookup vault agent name my-token
secret-tool clear  vault agent name my-token
```

`secret_get` returns a `{{secret:name}}` placeholder, not the value; pi
substitutes the real value into tool arguments at execution time, so the
plaintext never enters the conversation or session log. Vault only what agents
are allowed to use.

## Install

```bash
cp -r ~/code/agent-vault ~/.config/omarchy/plugins/skh.agent-vault
omarchy bar put skh.agent-vault --after skh.pibar
```

Plugin code hot-reloads on save under `~/.config/omarchy/plugins/`.

## Fedora / COSMIC (or any GTK desktop)

`fedora/agent-vault.py` is a standalone GTK4/libadwaita window with the same
scope and features (filter, copy via `wl-copy`, add, edit, delete). It talks to
the Secret Service through libsecret, so it works with gnome-keyring or KDE's
`ksecretd`, and items stay interchangeable with `secret-tool` and pi.

```bash
fedora/install.sh   # ~/.local/bin/agent-vault, launcher entry, app icon
```

Keys: `/` filter, Enter/`y` copy, `a` add, `e` edit, `d` delete (twice), `r`
refresh, Esc close. Bind `agent-vault` to a shortcut in COSMIC Settings →
Keyboard → Custom shortcuts.
