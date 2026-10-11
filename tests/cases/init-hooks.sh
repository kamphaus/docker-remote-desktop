#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"
dir=$(mktemp -d)
trap 'cleanup; rm -rf "$dir"' EXIT
mkdir "$dir/ok" "$dir/bad"
printf 'export HOOK_MARKER=from-hook\n' > "$dir/ok/10-marker.sh"
printf 'log "about to fail"\nfalse\n' > "$dir/bad/20-fail.sh"
chmod -R a+rX "$dir"

out=$(run_cmd -v "$dir/ok:/etc/desktop/init.d:ro" "$IMAGE" printenv HOOK_MARKER) || fail "hook run failed"
[ "$out" = from-hook ] || fail "exported variable not visible: '$out'"

if out=$(run_cmd -v "$dir/bad:/etc/desktop/init.d:ro" "$IMAGE" true 2>&1); then
    fail "failing hook did not abort startup"
fi
grep -q "init hook /etc/desktop/init.d/20-fail.sh failed" <<<"$out" || fail "unexpected output: $out"

mkdir "$dir/addr"
printf 'export RDP_LISTEN_ADDRESS=localhost\n' > "$dir/addr/10-addr.sh"
chmod -R a+rX "$dir"
c=$(start_desktop hook-addr -v "$dir/addr:/etc/desktop/init.d:ro")
wait_exit "$c" 30 >/dev/null
logs_contain "$c" "RDP_LISTEN_ADDRESS must be an IPv4 address" || fail "hook-exported bad RDP_LISTEN_ADDRESS not rejected"
pass
