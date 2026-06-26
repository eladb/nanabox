#!/usr/bin/env bash
# Build the nanabox runtime .deb with nfpm. Run from the repo root:
#   NANABOX_DEB_VERSION=0.1.0 ./scripts/build-runtime.sh
# Produces ./nanabox-runtime_<version>_all.deb. Requires nfpm on PATH
# (https://github.com/goreleaser/nfpm) — a build-time tool only, never a box dep.
set -euo pipefail
cd "$(dirname "$0")/.."
: "${NANABOX_DEB_VERSION:?set NANABOX_DEB_VERSION (e.g. 0.1.0, no leading v)}"
command -v nfpm >/dev/null || { echo "nfpm not found on PATH" >&2; exit 1; }
out="nanabox-runtime_${NANABOX_DEB_VERSION}_all.deb"
nfpm pkg --packager deb -f runtime/packaging/nfpm.yaml -t "$out"
echo "built $out"
