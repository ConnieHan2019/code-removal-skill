#!/usr/bin/env bash
# tidy-check.sh — prune unused dependencies (go mod tidy) and print the resulting
# dependency-manifest diff, so dependency cleanup stays behind one entrypoint
# instead of ad-hoc shell.
#
# Contract:
#   tidy-check.sh
#   exit 0 = tidy succeeded (diff printed), non-zero = tidy failed
#
# This script imposes no cache/proxy defaults. Override via env if needed, e.g.:
#   GOPROXY=https://proxy.golang.org,direct ./scripts/tidy-check.sh

set -euo pipefail

log_dir="./.tmp/code-removal"
log_file="$log_dir/tidy-check.log"

mkdir -p "$log_dir"

echo "--- tidy-check ---"
echo "log=$log_file"

echo "--- go mod tidy ---"
if go mod tidy >"$log_file" 2>&1; then
  echo "status=pass"
else
  echo "status=fail"
  echo "--- last 40 lines ---"
  tail -40 "$log_file" || true
  exit 1
fi

echo "--- diff stat ---"
git diff --stat go.mod go.sum

echo "--- removed go.sum lines ---"
git diff go.sum | grep -c '^-' || true
