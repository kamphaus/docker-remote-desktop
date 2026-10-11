#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"
name=$(start_desktop noroot)
wait_healthy "$name" 90
uids=$(exec_in "$name" sh -c 'cat /proc/[0-9]*/status 2>/dev/null | awk "/^Uid:/ {print \$2}" | sort -u')
[ "$uids" = 123456 ] || fail "unexpected process uids: $(echo $uids)"
pass
