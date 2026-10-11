#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"

# SIGTERM stops cleanly and quickly
s=$(start_desktop stop)
wait_healthy "$s"
start=$SECONDS
"$RUNTIME" stop -t 20 "$s" >/dev/null
[ $((SECONDS - start)) -lt 15 ] || fail "docker stop took $((SECONDS - start))s"
[ "$("$RUNTIME" inspect -f '{{.State.ExitCode}}' "$s")" = 0 ] || fail "non-zero exit after SIGTERM"

# A crashed component stops the container with a non-zero status
c=$(start_desktop crash)
wait_healthy "$c"
exec_in "$c" sh -c 'for p in /proc/[0-9]*; do [ "$(cat "$p/comm" 2>/dev/null)" = Xorg ] && kill "${p#/proc/}"; done; true'
code=$(wait_exit "$c" 30)
[ "$code" != 0 ] || fail "container exited 0 after Xorg crashed"

# Restart without tmpfs keeps /tmp and /run/desktop in the container layer: must recover
r="dt-$$-restart"
"$RUNTIME" run -d --label "$TEST_LABEL" --name "$r" --user 123456:0 --shm-size 1g "$IMAGE" >/dev/null
wait_healthy "$r"
"$RUNTIME" restart -t 20 "$r" >/dev/null
wait_healthy "$r" 90
pass
