---
name: publish-web
description: Publish a web app (a page, an API, a webhook receiver) from this nanabox. Use when the user asks to host a page, expose an API, share a script as a URL, set up a webhook, or otherwise serve something over HTTP from this box. Your app binds a unix socket; Caddy reverse-proxies your handle's path to it, and an ephemeral cloudflared quick tunnel makes it reachable on the public internet.
---

# publish-web

Caddy on this box (bound to `127.0.0.1:80`) gives each agent its own URL space under its handle, reverse-proxying that path to a **unix socket** your app binds. Run your server as a `systemctl --user` service and it stays up across restarts and reboots. To reach it from the public internet, open an ephemeral cloudflared quick tunnel (covered below) — there is no persistent public domain.

Your own handle equals your unix username and `$AGENT_NAME` (already exported into your environment).

## The model: bind a socket, Caddy proxies your path

Bind a unix socket at:

```
/run/nanabox/agents/$AGENT_NAME.sock
```

Caddy reverse-proxies every request under `/<your-handle>/*` to that socket, so your app is live locally at:

```
http://localhost/<your-handle>/
```

The **full path is preserved** — a request to `/<your-handle>/api/incoming` arrives at your server as `/<your-handle>/api/incoming` (the prefix is NOT stripped). Route your handlers on the full path. There's no port to pick, no registry to update, no deploy step: bind the socket and the route is live.

- The `/run/nanabox/agents` dir already exists (mode `2770 root:agents`); as an `agents`-group member you can create your socket there. It's on tmpfs, so the socket disappears on reboot — re-bind it on every (re)start. A `systemctl --user` service does that for you.
- **Remove a stale socket before binding** (`rm -f /run/nanabox/agents/$AGENT_NAME.sock`) so a restart doesn't fail with "address already in use".
- If your app isn't running, the route returns `502` — that's expected; just start your service.
- Serve both static files and dynamic routes from the one server. There's no separate "drop a static dir" path — your process owns everything under your handle.

## Run it as a `systemctl --user` service

You're a **non-sudoer**, so system units (`/etc/systemd/system`) are off-limits — use `systemctl --user` only. Linger is enabled for you, so user services survive logout and reboot.

Example unit (`~/.config/systemd/user/myapp.service`):

```ini
[Unit]
Description=My web app

[Service]
ExecStartPre=/bin/rm -f /run/nanabox/agents/%u.sock
ExecStart=/usr/bin/python3 /home/%u/myapp/serve.py --unix /run/nanabox/agents/%u.sock
Restart=always

[Install]
WantedBy=default.target
```

(`%u` expands to your username, which equals your handle / `$AGENT_NAME`.) Enable and start it:

```bash
systemctl --user daemon-reload
systemctl --user enable --now myapp
```

### Persist it — required, not optional

A service that lives only in `~/.config/systemd/user/` is **lost on the next reprovision** — your repo is the only thing that survives, and once the post-clone hook (#35) lands, anything not in your repo's `install.sh` simply won't come back. So in the *same* change, before you call this done:

1. **Commit the unit as a tracked file** in your repo (e.g. `systemd/<name>.service`), next to `serve.py` / your app code. `~/.config/...` is NOT your repo.
2. **Add an idempotent `install.sh` at your repo root** that installs + enables it, safe to re-run:

```bash
#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"   # non-interactive shells may not set it
install -D -m 0644 "$REPO/systemd/myapp.service" "$HOME/.config/systemd/user/myapp.service"
systemctl --user daemon-reload
systemctl --user enable --now myapp
systemctl --user restart myapp   # a re-run picks up unit / code changes
```

`install.sh` is the box's single source of truth for setup (see the box CLAUDE.md's "Box-specific setup" section) — a live service with no `install.sh` entry is a latent outage. Keep stateful data (session DBs, OAuth caches) out of git via `.gitignore`.

## Minimal example

A tiny Python server that listens on the unix socket and echoes the request path:

```python
#!/usr/bin/env python3
import os, sys, socketserver, http.server

SOCK = sys.argv[sys.argv.index("--unix") + 1]
if os.path.exists(SOCK):
    os.unlink(SOCK)

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(f"hello from {os.environ.get('AGENT_NAME','?')} at {self.path}\n".encode())

class UnixServer(socketserver.UnixStreamServer):
    def server_bind(self):
        super().server_bind()
        os.chmod(self.server_address, 0o660)

with UnixServer(SOCK, Handler) as srv:
    srv.serve_forever()
```

Once the service is running, `curl http://localhost/<your-handle>/` returns the greeting.

Most frameworks bind a unix socket directly:
- **Node/Express:** `app.listen('/run/nanabox/agents/' + process.env.AGENT_NAME + '.sock')`
- **Python/uvicorn:** `uvicorn app:app --uds /run/nanabox/agents/$AGENT_NAME.sock`
- **Gunicorn:** `gunicorn -b unix:/run/nanabox/agents/$AGENT_NAME.sock app:app`

## Make it reachable from the internet: an ephemeral cloudflared tunnel

Caddy binds localhost only, so by default your app is reachable on the box but not from the outside. When you need a public URL, open an **ephemeral cloudflared quick tunnel** — no Cloudflare account, no domain, no DNS:

```bash
cloudflared tunnel --url http://127.0.0.1:80
```

It prints a throwaway `https://<random>.trycloudflare.com` URL that forwards to Caddy, so your app is then public at:

```
https://<random>.trycloudflare.com/<your-handle>/
```

The tunnel lives only as long as the `cloudflared` process. For a one-off share, run it in the foreground and stop it (Ctrl-C) when done. To keep it up, run it from a `systemctl --user` service (and persist that in `install.sh`, same as your app) — note the hostname changes each time the tunnel restarts, since quick tunnels get a fresh random name.

**There is no built-in auth on a quick tunnel** — anyone with the URL reaches your app. The URL is unguessable, but treat it as a bearer secret: don't expose secrets or destructive actions without your app doing its own authentication.

## Things to know

- **One socket per agent.** Your handle's path maps to exactly one socket — one app process. If you want to serve multiple distinct things, route them as paths within your own server (e.g. `/<handle>/landing/`, `/<handle>/api/...`), not as separate sockets.
- **Re-bind on restart.** The socket is on tmpfs and vanishes on reboot; the `ExecStartPre` + `Restart=always` in the unit handle this. Don't store anything important in `/run`.
- **Webhooks work the same way.** A webhook receiver is just a route in your server; start a cloudflared tunnel and point the third party at `https://<random>.trycloudflare.com/<your-handle>/<your-route>`. Because a quick tunnel's hostname changes whenever the tunnel restarts, keep the tunnel running persistently (a `systemctl --user` service) if a webhook sender needs a stable URL — or re-register the hook after each restart.

## When NOT to use this

- **Things that must run unprivileged on a system port or below 1024** — you can't; bind your unix socket and let Caddy front it.
- **Anything that needs a stable custom domain or a managed TLS cert** — quick tunnels give you a throwaway `*.trycloudflare.com` name only. A persistent named tunnel or your own domain is outside what this skill sets up.
