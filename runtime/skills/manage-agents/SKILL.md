---
name: manage-agents
description: Understand and operate the agents on this nanabox — list them, peek at a session for debugging, restart a wedged one, and push a one-off prompt in. Use when the user asks about "the agents" or a specific agent's session. Creating/removing agents and changing box config are the box operator's job, not yours.
---

# manage-agents

This box runs one long-lived `claude` session per agent — each agent is its own unix user, with its session managed by a per-agent systemd unit (`nanabox-agent@<handle>.service`) and its PTY held open by `dtach` (socket at `~<handle>/.dtach/<handle>.sock`, owned `<handle>:agents` so peers in the `agents` group can deliver messages). The session flags come from the box runtime's harness.

**What you (an agent) can do vs. what's the operator's job:**

| Action | Who | How |
|---|---|---|
| List agents, message them, restart a session | any agent | the `agents` CLI (below) |
| Peek at a session to debug | any agent | `agents tail` |
| Create or remove an agent | **operator** (root) | `agents new` / `agents rm` — escalates via sudo, which you can't do |
| Change box config (Caddy routes, system services) | **operator** | not reachable from an agent session |

You're a non-sudoer, so anything in the operator column you ask the operator to do — don't reach for `sudo`.

## Inspecting sessions

```bash
agents list                               # all agents on this box (+ which are online)
agents tail <handle>                      # attach a peer's running session
# Detach with the dtach detach key (Ctrl-\). NEVER exit the inner shell /
# claude process — that kills the agent's session.
```

`dtach` has no scrollback / capture primitive. To read what an agent's terminal is showing without holding an interactive attach, snapshot one redraw read-only (see Path B below for the `script` + `dtach -a -r winch` recipe).

## Pushing a one-off prompt into an agent

Use the `agents` CLI (covered in depth by the `agent-2-agent` skill):

```bash
agents send <handle> "your prompt here"
agents broadcast "tell every other agent the same thing"
```

The agent treats the line as a fresh user message. If the target's session is live the message lands immediately via `dtach -p`; if not, it's queued to that agent's inbox and drained when the session next starts.

## Restarting a wedged agent

```bash
agents restart <handle>           # restart that agent's nanabox-agent@<handle> session
```

This bounces the systemd unit; the session comes back at a fresh `claude` prompt. Restarting an already-logged-in agent keeps its credentials (`~<handle>/.claude/.credentials.json` is preserved). A *newly created* agent still has to complete `/login` first — see the next section.

## Signing in to Claude (first-time auth for a new agent)

The harness doesn't export a shared `CLAUDE_CODE_OAUTH_TOKEN` — every agent runs on **its own** interactive OAuth grant, stored at `~<handle>/.claude/.credentials.json`. So a freshly created agent isn't authenticated yet: until someone drives `/login` in its session, `claude` sits at the login prompt and the agent can't respond.

Multiple full-scope grants on the same Claude account coexist, so adding a new login for `<handle>` does **not** invalidate the operator's existing grants on this box or anywhere else. Safe to do.

There are two paths. **Path A is the default** — one CLI call owns the whole dance for the operator. Path B is the raw dtach recipe Path A is built on, kept here as a fallback for when the CLI isn't available.

### Path A — one CLI round-trip (default; eladb/nanabox#128)

The operator runs a single command. It injects `/login` into the agent's session, prints the OAuth URL on stdout, blocks reading the `code#state` from stdin, writes credentials, restarts the unit so Remote Control re-registers, and exits 0 once both have landed.

```bash
sudo agents login <handle>
# stdout: the OAuth URL on one line
# stdin:  paste the code#state from the OAuth callback, press Enter
# exit 0: creds written AND session bounced (RC live within ~1 min)
```

For scripted use, pass the code instead of pipelining stdin:

```bash
sudo agents login <handle> --code "<code#state>"
```

Compose with provisioning to take a brand-new agent all the way from "doesn't exist" to "Remote Control live" in one go:

```bash
sudo agents new <handle> --description "…" --login
```

`agents login` is idempotent: if the agent already has full creds it just restarts the unit to make sure RC is live, then exits.

### Path B — raw `dtach` injection (fallback)

The recipe Path A wraps. Useful when `agents login` isn't available (older runtime, debugging the CLI itself). Only works for `<handle>` whose dtach socket your unix user can write to (the socket is owned `<handle>:agents` mode `0660`, so any agent in the `agents` group qualifies; root always qualifies).

```bash
SOCK=~<handle>/.dtach/<handle>.sock

# 1. Fire /login
printf '/login\r' | dtach -p "$SOCK"

# 2. Select "Claude subscription" (option 1)
printf '\r' | dtach -p "$SOCK"

# 3. Read the OAuth URL. dtach has no scrollback primitive, so we attach
#    read-only with a wide terminal (keeps the URL on one line), capture
#    one redraw, and strip ANSI. Use 1000 cols — the URL is ~450 chars and
#    240/500 can truncate it on some renderings; 1000 leaves ample margin.
script -qc "stty cols 1000; timeout 2 dtach -a $SOCK -r winch" /tmp/login-cap >/dev/null
sed -r 's/\x1B\[[0-9;?]*[ -\/]*[@-~]//g' /tmp/login-cap | grep -oE 'https://[^ ]+' | tail -1
```

Hand the URL to the operator. They sign in and return a `code#state` string:

```bash
# 4. Paste the code (bracketed paste so '#' goes through), then Enter
printf '\033[200~%s\033[201~\r' '<code#state>' | dtach -p "$SOCK"
# 5. Final Enter at the "Press Enter to continue" prompt
printf '\r' | dtach -p "$SOCK"
# 6. Bounce so Remote Control re-registers with the new grant
sudo agents restart <handle>
```

### Verify

```bash
sudo -u <handle> jq -r '
  if (.claudeAiOauth.accessToken // "") != "" and (.claudeAiOauth.subscriptionType // "") != ""
  then "ok: " + .claudeAiOauth.subscriptionType
  else "missing accessToken or subscriptionType"
  end
' ~<handle>/.claude/.credentials.json
```

`ok: max` (or `pro` etc.) confirms the grant. Anything else — or a missing file — means the login didn't complete. The agent also appears in claude.ai Remote Control within a minute or so of the post-login restart.

(Claude Code v2.1.153+ no longer writes `claudeAiOauth.oauthAccount.emailAddress` — a real working grant now serializes as just `accessToken` / `refreshToken` / `expiresAt` / `scopes` / `subscriptionType` / `rateLimitTier`. Check accessToken+subscriptionType presence instead.)

### Gotchas

- **A `CLAUDE_CODE_OAUTH_TOKEN` setup-token is not enough.** Tokens minted by `claude setup-token` are inference-only — they let `claude -p` run but the agent **will not appear in claude.ai Remote Control**, regardless of which account minted them. RC presence requires a full-scope interactive `/login`. Don't shortcut this with a token.
- **Don't share one credential file across agents.** `claude` refreshes credentials by writing a new temp file and atomic-renaming — so symlinks across unix users get replaced by `0600` private files within ~1h, and the single-use refresh tokens race. Each agent needs its own independent grant.
- **The "Trust this folder?" prompt is pre-stamped** by `agents new` (since v0.2.11 / #87), so a fresh agent should land straight at `/login`. If you see the trust prompt anyway, the stamp didn't take — accept it with `1` + Enter, then retry `/login`.

## Agent icon

Every agent can ship its own tiny icon. Any UI that lists the agents can pick it up next to the agent's name.

Drop **one** of these in the agent's home (SVG wins if both exist):

```
~<handle>/.nana/icon.svg    # preferred, sits next to ~/.nana/config.json
~<handle>/.nana/icon.png    # 64×64 or 128×128, transparent bg ideal
```

(Legacy fallback: `~<handle>/.claude/icon.svg|png` is still read for older agents. New icons go under `.nana/`.)

Keep it square, visually distinct from other agents on this box, and readable at small sizes. Avoid lots of detail or thin strokes.

For repo-backed agents, commit the file to the repo so a reprovision restores it.
