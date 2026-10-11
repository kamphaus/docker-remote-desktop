#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"
name=$(start_desktop uid)
wait_healthy "$name" 90
"$RUNTIME" logs "$name" 2>&1 | grep -q "desktop ready" || fail "no 'desktop ready' log line"
pass
