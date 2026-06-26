# caddy (nanabox)

Caddyfile + systemd drop-in for the nanabox HTTP front door.

The runtime package's `postinst` (packaging/postinst) symlinks
`/etc/caddy/Caddyfile` at this file (shipped under `/usr/lib/nanabox/caddy/`)
and drops `caddy.service.d.conf` into
`/etc/systemd/system/caddy.service.d/nanabox.conf` so caddy runs as root.

Caddy binds `127.0.0.1:80` only — nothing here faces the public internet
directly. The HTTP layout is intentionally minimal:

- `/<handle>/*` — reverse-proxied to the agent's own loopback service over a
  unix socket at `/run/nanabox/agents/<handle>.sock` (the publish-web feature).
- `/browser*` — the per-box headless Chromium's KasmVNC web UI
  (`nanabox-chrome.service`, `127.0.0.1:3000`), for watch-along.
- everything else — static files from `/srv/webapp/public`.

To expose a port on the public internet, an agent runs an ephemeral
`cloudflared tunnel --url http://localhost:PORT` quick tunnel (a throwaway
`*.trycloudflare.com` link, no account or domain required).
