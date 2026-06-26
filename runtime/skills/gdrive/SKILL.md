---
name: gdrive
description: Read from and write to a Google Drive via rclone, IF this box has an rclone remote configured. Use when the user asks to fetch a file from Drive, upload something, list a folder, search, sync a tree, or mount Drive — and the box operator has set up the Drive credentials. The remote is box-wide, shared by every agent on this box.
---

# gdrive

`rclone` is installed on this box. Whether it can reach a Google Drive depends on the **box operator** having configured a remote — there's no pre-authorized account built in. The operator wires Drive credentials through the box-local shared store (`/etc/nanabox/shared/`); the harness exports `RCLONE_CONFIG` from there at session launch, so if a config has been provisioned, `rclone` picks it up automatically with no login flow.

**Check first** whether a remote exists and what it's called:

```bash
rclone listremotes        # e.g. "gdrive:" — empty output means none configured
```

If `listremotes` is empty, the operator hasn't set up Drive on this box. Tell the user that Drive isn't configured here and that the operator can add an rclone remote via the shared store — don't try to run the OAuth flow yourself.

The examples below assume the remote is named `gdrive:`. Substitute whatever `rclone listremotes` actually shows.

The remote is **box-wide** — shared by every agent on this box. Treat it like any other shared resource: list before writing, don't delete things you didn't create, and don't dump large temporary files into it.

## Quick reference

```bash
rclone lsd  gdrive:                    # top-level folders
rclone ls   gdrive:"Folder/Path"       # files (recursive) with sizes
rclone tree gdrive:"Folder/Path"       # tree view, easier to read
rclone about gdrive:                   # quota / used / free
```

## Reading files

```bash
# Stream a file to stdout (good for piping into jq, ffmpeg, etc.)
rclone cat gdrive:"path/to/file.json"

# Copy a file to local disk (downloads). Note: trailing slash on dest = into-dir.
rclone copy gdrive:"path/to/file.mp4" /tmp/

# Copy a whole folder (recursive)
rclone copy gdrive:"path/to/folder" /tmp/folder/

# Search by filename
rclone lsf gdrive: --recursive --include "*birthday*"
```

`rclone copy` is incremental — re-running only transfers what changed. Use `sync` (carefully!) if you also want to delete remote files that don't exist locally.

## Writing files

```bash
# Upload a single file into a Drive folder
rclone copy ./localfile.png gdrive:"Folder/Subfolder/"

# Upload a directory tree
rclone copy ./builddir gdrive:"Some Folder/" --progress

# Pipe stdin into a Drive file (note: needs `rcat`)
echo "hello" | rclone rcat gdrive:"path/to/notes.txt"
```

Drive does not have real "overwrite" semantics — uploading a file with the same name creates a second copy unless you use `--update`. When updating an existing file, use:

```bash
rclone copy ./new.txt gdrive:"path/to/" --update
```

## Sharing-link / direct URL

```bash
rclone link gdrive:"path/to/file.png"      # creates a publicly viewable share link
```

This grants `reader` access to "anyone with the link". Ask the user before turning on sharing for anything that might be sensitive.

## Bigger jobs

For copy/sync of many files, add `--progress`, and consider:

- `--transfers 8 --checkers 16` to parallelize
- `--drive-acknowledge-abuse` if Drive refuses to download a flagged file you own
- `--dry-run` first, especially before any `sync` or `delete`

## What NOT to do

- **Don't `rclone sync` from local → gdrive: at the root.** That can mass-delete remote files outside your scope. Always sync into a specific subfolder.
- **Don't store working artifacts in arbitrary top-level Drive folders.** Stash project files under a folder named after your agent / project to keep the Drive tidy.
- **Don't `rclone mount` for long-lived workflows from inside an agent session.** It needs FUSE and a backgrounded process; if you need a mount, ask the user first.

## When the auth breaks

If a command returns `oauth2: cannot fetch token` or `invalid_grant`, the refresh token in the box's rclone config has been revoked (e.g. a password change on the Google account). Re-running the OAuth flow is the operator's job (it lives in the shared store, which you can't write). Tell the user the Drive auth needs to be redone by the operator; don't try to fix it silently.
