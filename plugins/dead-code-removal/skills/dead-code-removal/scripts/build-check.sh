#!/usr/bin/env bash
# build-check.sh — compile the project, log to a stable file, print a one-line status.
#
# Contract (kept stable so the SKILL workflow can reference it by name):
#   build-check.sh [package-pattern]   # default pattern: ./...
#   exit 0 = build passed, non-zero = build failed
#
# Cache / proxy behaviour: this script does NOT impose any cache or proxy
# defaults. If your environment needs fixed locations (e.g. a sandbox), export
# them yourself before calling:
#   GOCACHE=... GOMODCACHE=... GOPROXY=... ./scripts/build-check.sh

set -euo pipefail

package_pattern="${1:-./...}"
log_dir="./.tmp/code-removal"
log_file="$log_dir/build-check.log"

mkdir -p "$log_dir"

echo "--- build-check ---"
echo "pattern=$package_pattern"
echo "log=$log_file"

if go build "$package_pattern" >"$log_file" 2>&1; then
  echo "status=pass"
  exit 0
fi

echo "status=fail"
echo "--- last 40 lines ---"
tail -40 "$log_file" || true
exit 1
