---
name: agent-2-agent
description: List the other agents on this box and send them a message (one-to-one or broadcast). Use when the user asks "who else is running here?", "tell the other agents X", "broadcast to all agents", or when you want to coordinate work with a peer agent — e.g. handing a sub-task to a peer while you stay focused on your repo. Messages are fire-and-forget; the receiver reacts on its next turn.
---

# agent-2-agent

This box can run several long-lived `claude` sessions in parallel — one per agent, each as its own unix user with its own home/repo. They're peers: you can ask the user "who else is here?" or hand off a sub-task to a peer agent. This skill is the thin CLI for doing that.

## The `agents` command

```text
agents list                          # all agents on this box (+ which are online)
agents whoami                        # handle of the agent calling it (you)
agents send <name> <message...>     # inject a prompt into one peer
agents broadcast <message...>       # inject into every peer except yourself
agents broadcast --all <message...> # broadcast and include yourself
agents tail <name>                  # attach a peer's session (debugging)
agents clear [message...]           # type /clear into your own session, then optionally a follow-up
agents restart [name...]            # restart an agent's systemd session
```

(Adding or removing agents — `agents new` / `agents rm` — is a root/operator action, not something you can do as a non-sudoer agent.)

"Sending a message" means: the receiving agent gets the text as if the user just typed it. The receiver processes it on its next turn — no acknowledgement, no return channel built into the protocol. Treat it like leaving a sticky note, not a phone call.

## Message-writing convention

Every `agents send` or `agents broadcast` message MUST include:

1. **Who it's from.** Start the body with `[from: <your-name>]` (use `agents whoami` to fill it in). Without this the receiver can't tell who to reply to — they just see "the user said X" with no return address.
2. **What to do when done.** End the body with `When you're done, send me a quick status back: agents send <your-name> "...".` Or, if no callback is needed, say so explicitly: `Fire-and-forget — no need to reply.` Don't leave the callback expectation implicit; the receiver shouldn't have to guess.

Skipping these is the most common a2a footgun — the receiver either spins wondering whether anyone's waiting, or finishes the work and the sender never finds out.

### Template

```text
[from: <your-name>] <one-line summary of the ask>.

<context, file paths, links, anything they need to do the work>

When you're done, send me a quick status back:
  agents send <your-name> "Done with X — see <link or path>."
```

## Recipes

### Find out who's around
```bash
agents list
```
Each agent's handle equals its unix username. Your own handle is in there too — use `agents whoami` to identify yourself.

### Hand a discrete task to a specific peer
```bash
ME=$(agents whoami)
agents send <peer> "[from: $ME] Please regenerate the daily summary digest and commit it. When you're done, send me a quick status: agents send $ME \"daily digest done — commit <sha>\"."
```

### Fire-and-forget heads-up (no callback expected)
```bash
ME=$(agents whoami)
agents broadcast "[from: $ME] Heads-up: I just pushed a change to the shared widget config; re-pull your repo to pick it up. Fire-and-forget — no need to reply."
```

### Acknowledge work back to the sender
When you (the receiver) finish a task another agent asked you to do, close the loop:
```bash
ME=$(agents whoami)
agents send <original-sender> "[from: $ME] Done with the digest regeneration — committed as <sha>. Anything else?"
```

### Wake up an idle agent
```bash
ME=$(agents whoami)
agents send <peer> "[from: $ME] The user is wrapping up. Any open work on your end? Send a one-line status back when you've checked: agents send $ME \"<status>\"."
```

### Clear your own context and hand off a note to next-you
This is the trick `/nightly-cycle` uses to actually reset its context:
```bash
agents clear "Yesterday I finished the secrets editor; today: terminal-paste regressions."
```
Because `dtach -p` looks like real user input, the harness actually processes `/clear`. Writing `/clear` in your own response output does nothing — it has to come back in as user input. After the clear lands, the follow-up message is the first user message of the new context. (No `[from:]` prefix here — you're writing to yourself.)

## Things to know

- **No reply channel built into the protocol.** The convention above (sender name + callback line) IS the reply channel — without it the receiver has nowhere to send updates. Don't omit it.
- **Messages are user-prompts.** Whatever you write, the receiver will treat as a directive from the user. Don't broadcast something you wouldn't want acted on.
- **One-line summary first, details below.** The receiver sees the message as one chunk of user input. Lead with the ask so they understand the shape before reading the context.
- **Don't broadcast in tight loops.** Each delivery occupies the receiver's next turn. If you spam `broadcast`, you're spamming five users worth of work onto five agents.
- **Self-detection.** The CLI reads `$AGENT_NAME` (exported into each agent's harness environment) to identify the caller. Outside that context, it falls back to the unix username (`id -un`).

## Under the hood (for the curious)

The CLI (`/usr/bin/agents`, shipped by the box runtime) is a filesystem client — no central daemon. To deliver a message it writes to the receiving agent's PTY socket at `~<handle>/.dtach/<handle>.sock` via `dtach -p`; if that agent's session isn't live, it falls back to writing the message to the agent's inbox file (`~<handle>/.agents/inbox`), which gets drained when the session next starts. The message is wrapped in bracketed-paste markers and terminated with `\r` so claude's TUI treats it as a single paste followed by Enter — that matters for messages over a few hundred bytes, which claude's paste-detection would otherwise hold for a manual Enter.
