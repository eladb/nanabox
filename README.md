# nanabox

Spin up a personal **Claude-agent box** on your own cloud account with one
command. You bring a cloud API token; `nana` provisions a VM, installs the agent
runtime, and signs the box's root agent into your Claude subscription. From then
on you talk to it **from any Claude app** logged into that subscription, over
Remote Control. No domain, no dashboard, nothing to host.

```
$ nana new mybox
Looking for a Hetzner token… found (HCLOUD_TOKEN)
Provisioning mybox (cpx32, fsn1)…  ready  (203.0.113.7)
Installing agent runtime…
Creating the root agent 'mybox' (box admin, sudo)…
Signing in the root agent to Claude:
  Open: https://claude.com/cai/oauth/authorize?…
  Paste code#state: ****************

mybox is live — a Remote Control session named 'mybox' appears in any Claude app
on this subscription.
```

Open the Claude app and there's a session named **`mybox`** — that session *is*
the box, and it's the box admin. From inside it you spin up and coordinate more
agents, each with its own Linux user:

```
agents new researcher        # new agent → its own user → its own RC session
agents send researcher "…"   # message between agents
```

## Install

`nana` is a single Python 3 file (stdlib only). One line:

```bash
curl -fsSL https://raw.githubusercontent.com/eladb/nanabox/main/nana -o ~/.local/bin/nana && chmod +x ~/.local/bin/nana
```

(or drop it anywhere on your `PATH`). The only local prerequisite is `ssh`.

You'll need a **Hetzner Cloud API token** — create one at *Hetzner Cloud →
Security → API Tokens* (Read & Write). `nana` finds it in `HCLOUD_TOKEN`, then an
`hcloud` context, then prompts.

## How you reach the box

* **Remote Control (default).** The box only needs *outbound* network. Nothing is
  exposed publicly — you reach every agent through the Claude app. No Cloudflare,
  no domain, no TLS.
* **Ad-hoc public URL.** When an agent wants to share something (a web app, the
  browser watch-along), the runtime spins up an ephemeral `cloudflared --url`
  quick tunnel → a throwaway `*.trycloudflare.com` link. Still no account.

## Commands

```
nana new <name> [--size small|medium|large] [--region fsn1] [--no-login]
nana list
nana ip <name>
nana ssh <name> [-- cmd…]
nana delete <name> [-y]
```

`--no-login` provisions without the interactive sign-in (the OAuth paste needs a
human); sign in later with `nana ssh <name> agents login <name>`. Sizes map to
provider SKUs (`small→cpx22`, `medium→cpx32`, `large→cpx42`). Names must match
`^[a-z][a-z0-9-]{0,29}$`.

## What's on the box

The full multi-agent runtime: the `agents` CLI (per-agent **Linux-user
isolation**, `new` / `send` / `restart`), a headless **browser** (Chromium + CDP
for `agent-browser`), **Caddy**, and one `claude --remote-control` session per
agent. The root agent (named after the box) is the box admin with passwordless
`sudo`.

## Cost

Hetzner sticker price, billed hourly. `nana delete` stops the meter immediately.

| size   | SKU   | specs                  | €/mo  |
|--------|-------|------------------------|-------|
| small  | cpx22 | 2 vCPU,  4 GB,  80 GB  |  9.49 |
| medium | cpx32 | 4 vCPU,  8 GB, 160 GB  | 16.49 |
| large  | cpx42 | 8 vCPU, 16 GB, 320 GB  | 29.99 |

## Testing

`smoke.sh` provisions a throwaway box, asserts the runtime + box-named agent came
up, then destroys it — the unattended path (no OAuth). Spends a few cents of
Hetzner time; not a CI test.

```bash
HCLOUD_TOKEN=… ./smoke.sh
```

## License

MIT — see [LICENSE](LICENSE).
