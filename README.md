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
- **`d` Delete ×2** — two-press confirm.

## Agent side (pi)

`~/.pi/agent/extensions/secret-vault.ts` exposes `secret_list`, `secret_get`,
`secret_set`, `secret_delete` over the same scope. CLI equivalent:

```bash
printf '%s' "$VALUE" | secret-tool store --label='agent-vault: my-token' vault agent name my-token
secret-tool lookup vault agent name my-token
secret-tool clear  vault agent name my-token
```

Note: `secret_get` puts the value into the agent's conversation context (and
session log). Vault only what agents are allowed to hold.

## Install

```bash
cp -r ~/code/agent-vault ~/.config/omarchy/plugins/skh.agent-vault
omarchy bar put skh.agent-vault --after skh.pibar
```

Plugin code hot-reloads on save under `~/.config/omarchy/plugins/`.
