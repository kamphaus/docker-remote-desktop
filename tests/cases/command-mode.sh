#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"

out=$(run_cmd "$IMAGE" id -un) || fail "id -un failed under an arbitrary uid"
[ "$out" = wineuser ] || fail "arbitrary uid maps to '$out', expected wineuser"

out=$(run_cmd "$IMAGE" bash -c 'echo "$HOME"')
[ "$out" = /home/wineuser ] || fail "HOME is '$out'"

out=$("$RUNTIME" run --rm --label "$TEST_LABEL" "$IMAGE" id -un)
[ "$out" = wineuser ] || fail "default uid 1001 maps to '$out'"
pass
