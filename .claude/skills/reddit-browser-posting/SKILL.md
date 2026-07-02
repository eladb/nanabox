---
name: reddit-browser-posting
description: Use when driving Reddit's post/comment composer (or any Shadow-DOM rich-text editor) via agent-browser on the shared box browser — e.g. submitting a post, replying in a megathread, or filling out a comment form on reddit.com. agent-browser's normal ref-based click/type silently fails on these editors; this documents the working coordinate-click technique and the verification step that catches accidental duplicate submissions.
---

# Reddit posting via agent-browser

Reddit's post/comment composer ("Join the conversation" box, the post-submit
form) is a Shadow-DOM rich-text editor (`shreddit-composer` > `reddit-rte`,
often nested in closed shadow roots). `agent-browser`'s accessibility
snapshot doesn't surface the actual editable node, and `click @ref` /
`fill @ref` on it silently no-ops — text you "type" afterward goes nowhere
and `document.activeElement` stays `BODY`.

## Working technique

1. Take a screenshot, find the composer box visually.
2. Get real pixel size vs CSS size: `agent-browser eval "({w:innerWidth,h:innerHeight,dpr:devicePixelRatio})"`.
   Screenshot pixel coords ÷ dpr = CSS coords for `mouse move`.
3. Click via **mouse coordinates**, not selectors:
   ```
   agent-browser mouse move <x> <y>
   agent-browser mouse down
   agent-browser mouse up
   ```
4. Screenshot again — a properly focused composer shows a blinking cursor
   and an expanded toolbar (Bold/Italic/Cancel/Post or Comment buttons). If
   it still looks collapsed, the click missed; recompute coordinates.
5. Once focused, `agent-browser keyboard type "<text>"` and `press Enter`
   work normally (real keystrokes go to whatever has OS-level focus,
   regardless of shadow DOM).
6. **Submitting also needs a coordinate click**, not `find text "Post"
   click` — that command matched the wrong element more than once in
   practice (submitted nothing, or worse, see below). Crop the screenshot
   around the button, compute its center, `mouse move`/`down`/`up`.

## Verify after every submit — don't trust the UI alone

After clicking Post/Comment, the composer collapsing back to placeholder
text is a good sign, but isn't proof. Confirm via the account's own
data instead of guessing:

```
agent-browser eval "fetch('/user/<username>/comments.json?limit=3').then(r=>r.json()).then(d=>d.data.children.map(c=>({sub:c.data.subreddit, body:c.data.body.slice(0,80), permalink:c.data.permalink})))"
```

(swap `comments.json` for `submitted.json` when checking posts). This has
caught two real problems on nanabox's launch day:

- An **accidental duplicate crosspost** — a stray click during
  post-submission UI navigation (likely a "share to more communities"
  nudge) silently created a second, unauthorized post on a different
  subreddit. Screenshotting immediately after every Post/Comment click,
  before doing anything else, would have caught it right away.
- A **silent automod removal** — a post can disappear from listings with
  no visible error in the compose flow; check `/user/<name>/submitted.json`
  or the modmail inbox (`fetch('/message/inbox.json')`) for the actual
  removal reason (karma gates, repo-age gates, megathread-only rules are
  common causes — see the `reference-subreddit-selfpromo-rules` memory).

## Flair

If a subreddit requires flair (red asterisk on "Add flair and tags"), the
picker itself is a normal (non-shadow) modal — `find text "<flair name>"
click` or filling its search box and clicking the matching `radio` ref
works fine there. It's specifically the composer body that needs the
coordinate-click workaround.
