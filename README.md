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

### Getting a Hetzner Cloud token

`nana` provisions on [Hetzner Cloud](https://www.hetzner.com/cloud), so you need
an API token for a Hetzner **project**:

1. Sign in at https://console.hetzner.cloud and pick (or create) a project.
2. In the left sidebar: **Security → API Tokens → Generate API Token**.
3. Give it a name, set permissions to **Read & Write** (write is required —
   `nana` creates and deletes servers), and click **Generate**.
4. **Copy the token now** — Hetzner shows it only once. It looks like a 64-char
   string.

Give the token to `nana` in any of these ways (it checks them in this order):

```bash
export HCLOUD_TOKEN=<your-token>     # 1. environment variable (simplest for automation)
# 2. an `hcloud` CLI context, if you use the hcloud CLI
# 3. otherwise nana prompts for it interactively
```

For an unattended/agent run, set `HCLOUD_TOKEN` in the environment. Billing is
per-hour at the rates in the [Cost](#cost) table; `nana delete` stops the meter.

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

## Signing in — the OAuth handshake

The box reaches Claude using **your** Claude subscription. `nana new` signs the
root agent in via a one-time OAuth code-paste that needs a human to click
through. Here's the exact contract, so it can be driven by hand or by an agent:

1. `nana new` provisions the box (a few minutes), then prints to its output:
   ```
   Signing in the root agent to Claude:
     Open: https://claude.com/cai/oauth/authorize?…&state=<STATE>
     Paste code#state:
   ```
   …and then **blocks reading one line from stdin**.
2. A human opens that URL, signs into Claude, and authorizes. Claude shows a
   string of the form `<code>#<state>`.
3. Feed that string back to `nana` on **stdin** (the line it's waiting for). The
   part after `#` must equal the `state=` value in the URL — that's how the two
   halves are matched; a mismatch means the wrong URL/code pair.
4. `nana` submits it, waits for the credentials to land on the box, restarts the
   agent so Remote Control registers, and finishes. A Remote-Control session
   named after the box then appears in any Claude app on that subscription.

The URL and code are short-lived — complete the round-trip promptly.

**Driving it programmatically (e.g. from an AI agent).** Run `nana new` with a
pipe/PTY you control: stream its stdout until you see the `Open: https://…claude…`
line, relay that URL to the human, collect the `code#state` they paste back, and
write it (plus a newline) to `nana`'s stdin. Don't re-trigger the flow after you
have a URL — each new sign-in attempt mints a fresh `state`, which would
invalidate a code the human is already fetching.

**Or split it.** Provision unattended with `nana new <name> --no-login`, then run
the sign-in on its own later — same URL→`code#state` contract:

```bash
nana ssh <name> agents login <name>
```

`agents login` is idempotent: if the box is already signed in it just re-registers
Remote Control and exits.

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
