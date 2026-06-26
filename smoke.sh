#!/usr/bin/env bash
# Smoke test for `nana`: provision a throwaway box, assert the runtime and the
# box-named agent came up, then destroy it. Exercises the unattended path
# (`nana new --no-login`) end to end — the one thing worth checking on a real
# box is that the upstream runtime boots a working agent on a fresh,
# non-operator host.
#
# Spends a few cents of Hetzner time and takes ~5-10 min. NOT a CI test.
# Requires: HCLOUD_TOKEN (or an hcloud context) and ssh.
#
#   HCLOUD_TOKEN=… ./smoke.sh
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
NANA="$HERE/nana"
NAME="nana-smoke-$$"
KEY="$HOME/.ssh/nana_ed25519"

cleanup() {
  echo "→ cleanup: deleting $NAME"
  "$NANA" delete -y "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "→ provisioning $NAME (small, --no-login)…"
"$NANA" new "$NAME" --size small --no-login

IP="$("$NANA" ip "$NAME")"
echo "→ box at $IP"
ssh_box() {
  ssh -i "$KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o LogLevel=ERROR -o ConnectTimeout=10 "root@$IP" "$@"
}

fail=0
check() {  # check <remote-test-cmd> <label>
  if ssh_box "$1" >/dev/null 2>&1; then
    echo "  ✓ $2"
  else
    echo "  ✗ $2"
    fail=1
  fi
}

echo "→ asserting runtime + agent…"
check "command -v agents"                                "agents CLI installed"
check "command -v claude"                                "claude installed"
check "command -v caddy"                                 "caddy installed"
check "id $NAME"                                          "unix user '$NAME' exists"
check "systemctl is-active --quiet nanabox-agent@$NAME"  "agent unit active"
check "test -S /home/$NAME/.dtach/$NAME.sock"            "agent dtach session live"

if [ "$fail" = 0 ]; then
  echo "SMOKE PASS"
else
  echo "SMOKE FAIL"
  exit 1
fi
