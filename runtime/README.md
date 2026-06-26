# nanabox runtime

The per-box runtime for a **nanabox** — a multi-agent Claude box. It ships as a
Debian package (`nanabox-runtime`) that you install on a fresh Ubuntu host and
that turns it into a box where several Claude Code agents run side by side, each
as its own Linux user. Installing (and every later upgrade) runs a single
`postinst` reconcile that owns all on-box state: the `agents` group, the
per-agent login shim, the systemd units, the Caddy config, the shared
credential store, tmpfiles, and the shared skills + `CLAUDE.md` that every agent
loads.

Each agent gets a long-lived `claude --remote-control <handle>` session, kept
alive in a `dtach` PTY and supervised by a per-agent systemd unit. You operate
the box with the `agents` CLI (`list`, `send`, `broadcast`, `new`, `spawn`,
`rm`, `restart`, `login`, …). Agents are reached over **Claude Remote Control**,
which is outbound-only — nothing dials into the box. A box-wide headless
Chromium (run via Docker) gives agents a real browser over the Chrome DevTools
Protocol, with a watch-along UI. When an agent wants to expose a port on the
public internet it binds a unix socket that Caddy (bound to localhost)
reverse-proxies under `/<handle>/`, and opens an ephemeral
`cloudflared tunnel --url http://localhost:PORT` quick tunnel — a throwaway
`*.trycloudflare.com` link that needs no account or domain. The box keeps itself
patched via a systemd timer that polls the GitHub Releases channel and installs
new package versions.
