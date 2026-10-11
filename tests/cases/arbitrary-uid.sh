#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"
name=$(start_desktop uid)
wait_healthy "$name" 90
logs_contain "$name" "desktop ready" || fail "no 'desktop ready' log line"
pass
