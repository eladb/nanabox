---
name: gmail
description: Read and send mail from a Gmail account via a `gmail` CLI, IF this box has Gmail tooling and credentials configured. Use when the user asks to check inbox, search mail, read a message, send an email, or list labels — and the box operator has set up the Gmail integration. Works against whatever Google account the operator configured.
---

# gmail

A `gmail` CLI can drive a Gmail account from this box, but **only if the box operator has installed the tooling and provisioned credentials**. There's no Gmail account wired in by default — the runtime doesn't ship the `gmail` CLI, and the OAuth credentials (if any) live in the box-local shared store (`/etc/nanabox/shared/`), which the operator manages.

**Check first** whether it's available:

```bash
command -v gmail        # empty output → the CLI isn't installed on this box
```

If `gmail` isn't on `PATH`, this box doesn't have the integration. Tell the user that Gmail isn't set up here and that the operator can install the tooling and credentials — don't try to run an OAuth flow yourself.

If it IS installed, it operates as whatever Google account the operator configured. The sections below describe the usual interface; confirm the exact behavior with `gmail --help` on the box.

## Quick reference

```bash
gmail list                              # 10 most recent messages
gmail list -q 'is:unread' -n 20         # filter + count
gmail search 'from:foo subject:trip'    # alias for `list -q QUERY`
gmail read <msg-id>                     # headers + plain-text body
gmail read <msg-id> --raw               # full RFC822 source
gmail read <msg-id> --json              # structured for piping into jq
gmail labels                            # id  name (tab-separated)
```

`list` / `search` output is `<id>  <from>  <subject>`, one per line — easy to grep, awk, or hand to `read`. Add `--json` on any read-style command to get structured output.

## Searching

The `-q` / `search` argument takes a [Gmail search query](https://support.google.com/mail/answer/7190) verbatim. Common shapes:

```bash
gmail search 'is:unread'
gmail search 'from:noreply@github.com newer_than:7d'
gmail search 'subject:"weekly report" has:attachment'
gmail search 'label:work before:2026/01/01'
```

If the query needs spaces, quote the whole thing.

## Reading

```bash
gmail read 19e597ee04a2118f
# From: ...
# Subject: ...
# (blank line)
# decoded text/plain body (falls back to text/html if no plain part)
```

Pipe into `--json` when you need to extract fields:

```bash
gmail read 19e597ee04a2118f --json | jq -r .body
```

## Sending

Body comes from `--body`, `--body-file`, or `--stdin` (pick one):

```bash
gmail send --to user@example.com --subject "Hello" --body "Plain text body"

cat report.md | gmail send --to me@... --subject "Daily report" --stdin

gmail send --to a@x --cc b@x --bcc c@x \
  --subject "Status" --body-file /tmp/status.txt
```

Returns the new message id on stdout. **Sends from the configured account** — don't send mail without an explicit user ask, and prefer sending to the user / themselves over outside recipients unless instructed.

## House rules

- The configured mailbox is the user's. Treat reading as you would `cat`ing their files — fine when relevant, but don't browse for fun.
- Never echo OAuth tokens or credential-file contents into chat.
- Don't send mail to third parties unless the user explicitly asked for that recipient. Sending to themselves to test is fine.
- For anything the CLI doesn't cover (drafts, threads, attachments, label management), reach for the Gmail REST API directly if the CLI exposes a bearer-token helper — check `gmail --help` for what's available on this box.
