#!/usr/bin/env bash
# Xorg must not expose the display on abstract (access-control-free, network-namespace-wide) unix sockets.
source "$(dirname "$0")/../lib.sh"

d=$(start_desktop xorg-sockets)
wait_healthy "$d"
unix=$(exec_in "$d" cat /proc/net/unix)
! grep -q '@/tmp/.X11-unix/X10' <<<"$unix" || fail "Xorg listens on an abstract socket"
grep -q '/tmp/.X11-unix/X10' <<<"$unix" || fail "Xorg filesystem socket missing"
pass
