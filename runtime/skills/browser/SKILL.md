---
name: browser
description: Drive the long-lived Chromium running on this nanabox over the Chrome DevTools Protocol. Use when the user asks to scrape a page, automate a browser flow, fill a form, log into a site, take a screenshot, or otherwise control a real browser. The user can watch and take over the same session from their own browser tab — useful for one-off logins, captchas, or MFA.
---

# browser

A headed Chromium runs in a Docker container on this box (managed by
`nanabox-chrome.service`). Two ways to reach it:

| Endpoint | Who uses it | Reachable from |
|---|---|---|
| `http://localhost:9222` (CDP) | agents on this box | localhost only |
| `http://localhost/browser` (KasmVNC web UI) | the human, to watch / take over | localhost only by default (expose via an ephemeral cloudflared quick tunnel — see below) |

The user-data dir is persisted to `/var/lib/nanabox/chrome/profile` on the box,
so logins, cookies, and extensions survive container restarts.

## Default tool: `agent-browser`

`agent-browser` is a Rust CLI from Vercel Labs built specifically for AI agents — it returns accessibility snapshots with stable refs (`@e1`, `@e2`, …) so you can interact deterministically without writing selectors. It's pre-installed on this box.

**Always pass `--cdp 9222`** so it attaches to the shared Chromium instead of launching its own.

Typical loop:

```bash
agent-browser --cdp 9222 open https://example.com
# ✓ Example Domain
#   https://example.com/

agent-browser --cdp 9222 snapshot -i
# - heading "Example Domain" [level=1, ref=e1]
# - link "Learn more" [ref=e2]

agent-browser --cdp 9222 click @e2
agent-browser --cdp 9222 fill @e1 "hello"
agent-browser --cdp 9222 screenshot /tmp/page.png
```

Other useful commands: `type`, `press`, `select`, `scroll`, `wait`, `eval <js>`, `pdf`, `back`, `forward`, `reload`. Run `agent-browser --help` for the full list.

**Read the bundled skill first** — it ships version-matched docs with workflow patterns and copy-paste templates:

```bash
agent-browser skills get core --full
```

Specialized skills exist for Slack, Electron apps, etc. — `agent-browser skills list`.

### Sessions and tabs

By default each `agent-browser` invocation operates on the active tab in the shared browser. If you need an isolated tab, use the session flags shown in `agent-browser skills get core --full` (or open a new tab via `open <url>` — it reuses the same tab; use `eval 'window.open(...)'` for a new one).

## Alternative: Playwright / Puppeteer

When you need programmatic control (loops, complex async, framework integration), connect a regular CDP client. Get the WebSocket URL first:

```bash
curl -s http://localhost:9222/json/version | jq -r .webSocketDebuggerUrl
```

**Playwright** (Python):

```python
from playwright.sync_api import sync_playwright
with sync_playwright() as p:
    browser = p.chromium.connect_over_cdp("http://localhost:9222")
    ctx = browser.contexts[0]
    page = ctx.new_page()
    page.goto("https://example.com")
    print(page.title())
```

**Puppeteer** (Node):

```js
import puppeteer from "puppeteer-core";
const browser = await puppeteer.connect({ browserURL: "http://localhost:9222" });
const [page] = await browser.pages();
await page.goto("https://example.com");
console.log(await page.title());
await browser.disconnect();   // NEVER browser.close() — that kills the shared instance
```

## When the human needs to step in

The watch-along UI is served at `http://localhost/browser` (Caddy → the
container's KasmVNC UI), reachable on the box itself. To let a human watch and
take over from elsewhere, open an **ephemeral cloudflared quick tunnel** (no
account, no domain) and share the `/browser` path of the printed URL:

```bash
cloudflared tunnel --url http://127.0.0.1:80
# → https://<random>.trycloudflare.com   (then point them at .../browser)
```

Tell the user:

> Open `https://<random>.trycloudflare.com/browser` — you'll see the same browser the agent is using. Do the login / captcha / MFA, then tell me to continue.

The tunnel lives only as long as the `cloudflared` process; stop it when you're
done. After they're done, your existing CDP connection can keep using the page
they finished setting up.

## Important caveats

- **One shared browser per box.** This box runs a single Chromium; every agent on it attaches to the same process and the same profile. Concurrent agents will fight over tabs. Open your own tab (or use `agent-browser`'s session flags) and don't close other agents' tabs.
- **Shared profile.** A login one agent performs is visible to the next, and to the human watching. Treat it as a shared workstation, not a sandbox. For isolation, use a new browser context (Playwright `new_context()`) rather than the default.
- **Never close the browser.** In Puppeteer use `disconnect()` not `close()`. With `agent-browser`, never run `agent-browser close --all`. Closing kills the container's session for everyone.
- **CDP is localhost-only by design.** Don't try to expose `:9222` externally. The `/browser` watch-along is reached locally, or through an ephemeral cloudflared quick tunnel you start when a human needs to step in.
- **You can't restart it yourself.** `nanabox-chrome.service` is a system unit and you're a non-sudoer, so restarting Chromium (or running `docker`) is the box operator's job. If the browser is wedged, ask the operator to restart `nanabox-chrome.service`; the profile volume is preserved across restarts.

## Troubleshooting

- `connection reset by peer` from CDP → Chromium is still launching, retry in a few seconds.
- `agent-browser` says it can't reach CDP → make sure you passed `--cdp 9222`. If `curl -s http://localhost:9222/json/version` also fails, the container is down — ask the operator to restart `nanabox-chrome.service`.
- KasmVNC UI loads but desktop is black → Chromium crashed; ask the operator to restart `nanabox-chrome.service`.
