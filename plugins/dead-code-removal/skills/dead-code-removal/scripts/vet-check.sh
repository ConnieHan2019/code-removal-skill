#!/usr/bin/env bash
# vet-check.sh — run static analysis (go vet), log to a stable file, print status.
#
# Contract:
#   vet-check.sh [package-pattern]   # default pattern: ./...
#   exit 0 = no findings, non-zero = findings (inspect the log)
#
# This script imposes no cache/proxy defaults; export GOCACHE/GOMODCACHE/GOPROXY
# yourself if your environment requires fixed locations.

set -euo pipefail

package_pattern="${1:-./...}"
log_dir="./.tmp/code-removal"
log_file="$log_dir/vet-check.log"

mkdir -p "$log_dir"

echo "--- vet-check ---"
echo "pattern=$package_pattern"
echo "log=$log_file"

if go vet "$package_pattern" >"$log_file" 2>&1; then
  echo "status=pass"
  exit 0
fi

echo "status=fail"
echo "--- last 40 lines ---"
tail -40 "$log_file" || true
exit 1
