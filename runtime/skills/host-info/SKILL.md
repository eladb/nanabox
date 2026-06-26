---
name: host-info
description: Report basic facts about this nanabox (handle, hostname, uptime, disk, memory, public IP, runtime version). Use when the user asks about the box's current state or wants a quick health snapshot.
---

# host-info

Print a concise snapshot of this box. Useful for a quick health check or when the user asks "how's the box doing?".

Run:

```bash
echo "handle:  $(cat /etc/nanabox/handle 2>/dev/null || echo unknown)"
echo "host:    $(hostname)"
echo "uptime: $(uptime -p)"
echo "disk:   $(df -h / | awk 'NR==2 {print $3" used / "$2" ("$5")"}')"
echo "mem:    $(free -h | awk '/^Mem:/ {print $3" used / "$2}')"
echo "ip:     $(curl -fsS --max-time 3 https://api.ipify.org || echo unknown)"
echo "agents:  $(getent group agents | cut -d: -f4 | tr ',' '\n' | grep -c .)"
echo "updates: $(systemctl is-active nanabox-auto-update.timer 2>/dev/null || echo unknown)"
installed=$(dpkg-query -W -f='${Version}' nanabox-runtime 2>/dev/null || echo unknown)
latest=$(curl -fsSL --max-time 3 https://github.com/eladb/nanabox/releases/latest/download/latest.json 2>/dev/null | grep -oE '"version" *: *"[^"]*"' | head -1 | sed -E 's/.*: *"v?([^"]*)".*/\1/')
echo "runtime: ${installed} (latest: ${latest:-unknown})"
```

The `handle` is this box's local name. The box itself is reached over Claude Remote Control (outbound only) — there is no persistent public domain; to expose a port an agent opens an ephemeral `cloudflared tunnel --url http://localhost:PORT` quick tunnel. The `runtime` line shows the installed `nanabox-runtime` package version next to the latest published on the GitHub Releases channel; the box auto-updates on a timer, so the two should converge once an update has rolled out. The `updates` line is that timer's state — anything other than `active` means the box has stopped patching itself and needs attention. `agents` is how many agents share this box.
