#!/usr/bin/env bash
# Semantic invariant (the safety net): for every self-contained fixture,
# `hledger print` must be byte-identical before and after formatting. If it
# differs, the formatter changed meaning, not just whitespace.
#
# Usage: test/semantic.sh /path/to/hledger-fmt
set -euo pipefail

fmt="${1:?usage: semantic.sh PATH_TO_HLEDGER_FMT}"
here="$(cd "$(dirname "$0")" && pwd)"
data="$here/testdata"

if ! command -v hledger >/dev/null 2>&1; then
    echo "semantic.sh: hledger not on PATH; skipping" >&2
    exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

status=0
for in in "$data"/*.in.ledger; do
    name="$(basename "$in" .in.ledger)"
    # Only self-contained journals: skip fixtures that `include` other files.
    if grep -qE '^[[:space:]]*include[[:space:]]' "$in"; then
        echo "skip (include): $name"
        continue
    fi
    if ! hledger print -f "$in" >"$tmp/before" 2>/dev/null; then
        echo "skip (not a standalone journal): $name"
        continue
    fi
    "$fmt" <"$in" >"$tmp/after.ledger"
    hledger print -f "$tmp/after.ledger" >"$tmp/after"
    if diff -u "$tmp/before" "$tmp/after"; then
        echo "ok: $name"
    else
        echo "FAIL (print changed): $name" >&2
        status=1
    fi
done
exit "$status"
