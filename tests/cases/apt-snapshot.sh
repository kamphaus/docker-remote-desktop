#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"

out=$("$RUNTIME" run --rm --entrypoint grep "$IMAGE" -c '^Snapshot: [0-9]\{8\}T[0-9]\{6\}Z$' /etc/apt/sources.list.d/ubuntu.sources) \
    || fail "no Snapshot: lines in ubuntu.sources"
[ "$out" -ge 2 ] || fail "expected a Snapshot: line per stanza, found $out"

if out=$("$RUNTIME" run --rm --user 0 --entrypoint /usr/local/sbin/apt-snapshot "$IMAGE" 2026-10-01 2>&1); then
    fail "apt-snapshot accepted an invalid id"
fi
grep -q "invalid snapshot id" <<<"$out" || fail "unexpected output: $out"
pass
