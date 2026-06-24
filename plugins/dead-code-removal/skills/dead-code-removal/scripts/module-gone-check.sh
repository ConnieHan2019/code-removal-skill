#!/usr/bin/env bash
# module-gone-check.sh — verify that a repo-relative directory no longer exists.
#
# Contract:
#   module-gone-check.sh <module-dir>
#   exit 0 = directory is gone, non-zero = still present (entries listed)

set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <module-dir>" >&2
  exit 2
fi

module_dir="$1"

echo "--- module-gone-check ---"
echo "module=$module_dir"

if [ -e "$module_dir" ]; then
  echo "status=present"
  echo "--- remaining entries ---"
  ls "$module_dir"
  exit 1
fi

echo "status=gone"
echo "DIRECTORY GONE"
