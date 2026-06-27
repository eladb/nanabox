---
name: onboard
description: First-run guided onboarding for a freshly provisioned nanabox, run by the box's root/admin agent. Interactively walks the user through every runtime capability — captures what the box is for (and writes it into the system prompt), optional GitHub access, creating their first non-root agent, inter-agent messaging, shared secrets, the headless browser, publishing web apps, and custom skills. Use when a box is new, on the root agent's first session, or when the user says "onboard me", "get me started", "give me a tour", or "what can this box do?".
---

# onboard

You are the **root/admin agent** of this box (name: `cat /etc/nanabox/handle`). Run a
hands-on onboarding that gets the user productive fast and teaches every capability.

**How to run it — read this first:**
- Be **interactive and terse**. Ask ONE decision at a time (use multiple-choice /
  ask-user prompts), DO the thing, confirm in one line, move on.
- **Demonstrate, don't lecture.** No walls of text. Optimize for a working box, not prose.
- Let the user **skip** any step ("skip" / "not now"). Keep an internal checklist so you
  can resume if interrupted.
- You have passwordless `sudo` (you're the box admin) — verify once with `sudo -n true`.

## 1. Orient (one line)
"I'm the admin agent for **<box>**. I'll set you up and show you what this box can do —
tell me to skip anything." Then go.

## 2. About this box → your system prompt
Ask 2–3 quick things (free-text is fine): **who are you?**, **what will you use this box
for?**, **any standing preferences** (languages, tools, style, do/don'ts)?
Append their answers as an `## About this box` section to your own `~/CLAUDE.md` so every
future session starts with this context (it's durable — survives restarts and updates).
Read it back in one line and confirm it's right.

## 3. GitHub access (optional)
Ask: **want this box to work with your GitHub repos?**
- If yes: run `gh auth login` and relay the device code + `https://github.com/login/device`
  URL it prints; the user authorizes in their browser. Verify with `gh auth status`.
  Agents can now clone / push / open PRs.
- For tighter scope, mention they can instead pipe a fine-grained PAT or a GitHub App
  installation token: `gh auth login --with-token`.

## 4. Your first agent
One line on the model: each agent is its own Linux user **and** its own Remote Control
session (`<handle>@<box>`); you're the admin. Ask for a **handle** + **what it's for**.
Run `agents new <handle> --login` and drive the Claude sign-in (relay the OAuth URL, take
the `code#state` they paste back). Write its purpose into `/home/<handle>/CLAUDE.md`.
Tell them it now appears as `<handle>@<box>` in any Claude app on their subscription.

## 5. Talk between agents
Demonstrate live: `agents send <handle> "ping from root — reply to confirm"`, then
`agents list`. Mention `agents broadcast` for all agents at once. (Depth: `agent-2-agent`.)

## 6. Shared secrets
Explain `/etc/nanabox/shared/shared.env` — only you (root) write it; every agent reads it.
Ask if they have a secret to add (API key, etc.). If so, append a `# what it is` comment +
`KEY=value` as root, `chmod 0640`, and confirm every agent can now read it. (Per-agent-only
secrets go in that agent's own `~/.env`.)

## 7. The browser
One line: the box runs a long-lived headless Chromium; agents drive it with `agent-browser`
and you can watch live. Offer a quick demo (open a page, screenshot it). To watch along:
`cloudflared tunnel --url http://127.0.0.1:80`, then open the printed
`https://<random>.trycloudflare.com/browser`. (Depth: `browser`.)

## 8. Publish a web app
One line: any agent can serve a page / API / webhook and expose it on a throwaway public
URL — no domain, no account. Offer to scaffold a hello-world and spin an ephemeral tunnel so
they see a live link. (Depth: `publish-web`.)

## 9. Custom skills
Explain: skills are reusable playbooks at `.claude/skills/<name>/SKILL.md`. Ask if there's a
task they do repeatedly; if so, capture it as a skill in `~/.claude/skills/` (per-agent).
Built-in skills already cover the basics — list them with what's under
`/usr/share/nanabox/.claude/skills`.

## 10. Wrap
Recap in ≤5 bullets what's now set up and the obvious next moves. Point at the per-feature
skills for depth (`manage-agents`, `agent-2-agent`, `browser`, `publish-web`, `nightly-cycle`).
Close: "You're set — just talk to me, or any `<handle>@<box>` session, to get going."
