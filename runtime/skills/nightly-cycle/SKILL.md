---
name: nightly-cycle
description: "End-of-day consolidation routine. A box-wide systemd timer fires `/nightly-cycle` overnight (around 03:00–05:00 UTC; the firing is staggered across the fleet and across agents on a box to avoid an API-rate-limit burst) for each agent on this box. The agent reviews the day's work, distills durable insights into memories and skills, writes a brief day summary at its per-handle path `~/.agents/<handle>/nightly-summary.md`, then `/clear`s the session. When fired by the timer (vs run manually), the box ALSO restarts the agent's systemd unit after the summary lands so the next session re-reads the runtime CLAUDE.md + skills — which `/clear` alone doesn't reload."
---

# nightly-cycle

A nightly consolidation pass. The goal is to compress what you learned today into durable artifacts (memories + skills) so your **context window** starts each day clean but your **knowledge** accumulates.

## When this fires

A box-wide systemd timer (`nanabox-nightly-cycle.timer`, shipped by the runtime) runs every night, nominally at 03:00 UTC plus a randomized per-box delay of up to 2 hours (so the whole fleet doesn't hit the Claude API at the same instant). It then iterates the agents on this box and sends each one the literal text `/nightly-cycle` (via the `agents` CLI), spacing them out by a stable per-handle offset so agents sharing a box also don't all fire at once. You can also run it manually any time you finish a meaningful chunk of work.

## What to do, in order

### 0. Decide whether now is a safe time to cycle

The cycle ends with `/clear` — your context window and any mid-flight reasoning are gone. **If there's active work that would be interrupted, postpone instead of running the cycle.**

Signs that say *postpone*:

- background `Bash` tasks you launched that haven't completed yet
- subagents you spawned via the `Agent` tool still running
- a user request you're in the middle of executing (you only just got `/nightly-cycle` because the user typed it, but if it arrived from the systemd timer mid-task, it'll preempt)
- a tool call you're about to make that's load-bearing for the user's current ask

If any of those apply, **do not run the cycle.** Instead:

1. In one sentence, tell the user you're postponing because X is still running.
2. Use the `/schedule` skill to schedule `/nightly-cycle` for a later time when you expect to be idle — typically 1–3 hours out, picking a slot you actually believe will be free.
3. End your turn.

It's fine to skip a cycle entirely — the systemd timer will fire `/nightly-cycle` again the next night, so worst case the consolidation slides by 24 hours. That's much better than a `/clear` mid-task.

If nothing's in flight, continue to step 1.

### 1. Look back at today

- `git log --since=yesterday --pretty=oneline -- $(pwd)` in your repo. Skim what you committed.
- Read your current memory files and recent skill changes (if any). Anything you tried to remember yesterday — did it pan out, or should you revise it?
- Note any open threads or blockers you didn't resolve.

### 2. Update memories

For each genuinely durable insight from today, write or update a memory file in your project's memory directory (the harness manages the path — write via the same convention you've used before). A memory is worth saving only if it answers: "Would I otherwise re-discover this the hard way next week?"

Categories you'll commonly write:
- **user**: a user preference / role / constraint you didn't know before.
- **feedback**: a correction or validation from today ("don't do X", "yes that approach was right").
- **project**: a fact about the current state of the work that won't be obvious from the code or git log.
- **reference**: a pointer to an external system or doc the user mentioned.

Don't write transient task state (current sprint, today's TODO list) — that belongs in tasks/plans, not memory.

Update **MEMORY.md** with one-line pointers for any new memory files.

### 3. Update or create skills

If a procedure you executed today is one you'd repeat (or that another agent on this box would benefit from), distill it into a skill at `.claude/skills/<name>/SKILL.md`. Keep it small, concrete, and scoped to **your** project. Use the standard frontmatter:

```yaml
---
name: <kebab-case>
description: <one-paragraph trigger doc — when should I use this?>
---
```

If the procedure is box-wide (multiple agents would use it), don't bury it in your `.claude/skills/` — flag it to the user and let them decide whether to promote it to a runtime-shipped skill (which the operator ships in the box runtime, not on a single box).

### 4. Commit

If you wrote new memory or skill files, commit them. One commit titled `nightly-cycle: consolidate <date>` is fine.

### 5. Clear and hand off the day summary in one step

Write the day's summary as a **markdown file** — a short briefing to your future self — covering:

- what was accomplished today
- what's outstanding or queued
- anything that needs the user's attention

If you added or revised any memories or skills, mention them by name so tomorrow-you knows what's now on disk. A few paragraphs with a heading and maybe a list is plenty — this is the first thing the user sees when the new day starts, so structure earns its keep, but don't write a novel.

Write the markdown to your **per-handle** summary path: `~/.agents/$(agents whoami)/nightly-summary.md`. Keying it to *your* handle means that on a box where same-uid `agents spawn` peers share one `$HOME` (and one repo/cwd), your summary can't collide with a peer's or get swapped for theirs — and the box-side restart reads back this exact path (eladb/nanabox#183). Don't write it to `$PWD`/the repo root: peers share the tree, so a cwd-based path drifts from what the box reads back. (It's outside the repo, so no `.gitignore` entry is needed.)

As the **last** thing in your turn, point `agents clear` at it:

```bash
SUMMARY="$HOME/.agents/$(agents whoami)/nightly-summary.md"
mkdir -p "$(dirname "$SUMMARY")"
cat > "$SUMMARY" <<'EOF'
# Day summary — 2026-MM-DD

Today's headline goes here in a sentence.

## Shipped
- one-line bullets…

## Open threads
- …
EOF

agents clear --message-file "$SUMMARY"
```

`agents clear --message-file <path>` (see the `agent-2-agent` skill) types `/clear` into your own session and queues a follow-up prompt asking the fresh context to read and render the file. Because the CLI writes the keystrokes into your PTY (via `dtach -p`) it looks like real user input, so the slash command is processed by the harness — your context window resets, and the first thing the new session does is present the briefing back to the user, nicely formatted.

Use `--message-file` rather than `agents clear "$summary"` because writing a multi-line markdown blob inline would mangle the newlines, backticks, and special characters.

Writing `/clear` yourself in this response does **nothing** — slash commands are only processed when they arrive at the user prompt, and your assistant output isn't user input. `agents clear --message-file` is the workaround.

After invoking it, end your turn — don't add further commentary. The next thing you'll see is the fresh context's rendering of your summary.

### Box-side restart (timer-triggered only)

When `/nightly-cycle` was fired by the systemd timer (vs typed manually by the operator), the box waits for `~/.agents/<your-handle>/nightly-summary.md` to land, then runs `agents restart <handle>` on you and re-sends the "render the briefing" prompt to the fresh session. This guarantees that any runtime release that landed during the day — new CLAUDE.md, new skills under `/usr/share/nanabox/.claude/skills/` — actually takes effect on the next session, because `/clear` doesn't re-read those (they're loaded at process start). For manual invocations the restart doesn't happen; rely on `agents clear --message-file` and the rendering you'd see in-place.

## Discipline

- Resist fluffy "lessons learned" entries. A useless memory clutters every future session.
- Don't migrate one-off debugging into a permanent skill. Skills are for procedures you'd do again.
- If today was uneventful, do less — a short pass with no new memories is fine. Don't manufacture insight.
- If you have unfinished work, leave it. The point isn't to wrap up — it's to compress what you learned.

## Triggering manually

Just type `/nightly-cycle` at any time. The flow is identical to the timer-fired one — you'll consolidate, then `agents clear` yourself with the summary. The overnight timer just makes it happen on autopilot every night.
