#!/usr/bin/env bash
# Probes must not open real RDP connections (xrdp logs errors for every connection that sends no X.224 request).
source "$(dirname "$0")/../lib.sh"

d=$(start_desktop hc-quiet)
wait_healthy "$d"
before=$(exec_in "$d" grep -c ERROR /run/desktop/log/xrdp.log || true)
for _ in 1 2 3 4 5; do exec_in "$d" /usr/local/bin/desktop healthcheck || fail "healthcheck failed"; done
sleep 1
after=$(exec_in "$d" grep -c ERROR /run/desktop/log/xrdp.log || true)
[ "$before" = "$after" ] || fail "healthcheck added $((after - before)) ERROR lines to xrdp.log"

pass
