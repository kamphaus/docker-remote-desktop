#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"

if out=$("$RUNTIME" run --rm --label "$TEST_LABEL" --user 123456:0 --read-only "$IMAGE" true 2>&1); then
    fail "started although /run/desktop is read-only"
fi
grep -q "/run/desktop is not writable" <<<"$out" || fail "unexpected output: $out"
pass
