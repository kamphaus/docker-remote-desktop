#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"

d=$(start_desktop listen-default)
wait_healthy "$d"
listening_on "$d" 0100007F:0D3D || fail "not listening on 127.0.0.1:3389"
! listening_on "$d" 00000000:0D3D || fail "listening on 0.0.0.0:3389 by default"

w=$(start_desktop listen-any -e RDP_LISTEN_ADDRESS=0.0.0.0)
wait_healthy "$w"
listening_on "$w" 00000000:0D3D || fail "RDP_LISTEN_ADDRESS=0.0.0.0 not honoured"

i=$(start_desktop listen-bad -e RDP_LISTEN_ADDRESS=localhost)
code=$(wait_exit "$i" 30)
[ "$code" != 0 ] || fail "accepted RDP_LISTEN_ADDRESS=localhost"
logs_contain "$i" "RDP_LISTEN_ADDRESS must be an IPv4 address" || fail "unclear error for bad address"
pass
