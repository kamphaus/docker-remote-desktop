#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"

client_image=$(build_rdp_client)
name=$(start_desktop e2e)
wait_healthy "$name" 90

connect() {
    "$RUNTIME" run -d -i --init --label "$TEST_LABEL" --name "$name-client-$1" --network "container:$name" "$client_image" \
        xvfb-run -a xfreerdp /v:127.0.0.1:3389 /cert:ignore /sec:tls /u:wineuser /p:unused \
        /sound:sys:fake +clipboard >/dev/null
}
connections() { exec_in "$name" grep -c 'connected to X11rdp_pid' /run/desktop/log/xrdp.log || true; }
xorg_pid() { exec_in "$name" sh -c 'for p in /proc/[0-9]*; do [ "$(cat "$p/comm" 2>/dev/null)" = Xorg ] && echo "${p#/proc/}"; done; true'; }

before=$(xorg_pid)
connect 1
poll 30 "first RDP session" sh -c "[ \"\$($RUNTIME exec $name grep -c 'connected to X11rdp_pid' /run/desktop/log/xrdp.log)\" -ge 1 ]"
poll 30 "audio channel" exec_in "$name" test -S /run/xrdp/sockdir/xrdp_chansrv_audio_out_socket_10
sinks=$(exec_in "$name" env XDG_RUNTIME_DIR=/run/desktop/xdg pactl list short sinks)
grep -q xrdp-sink <<<"$sinks" || fail "xrdp-sink not present in PulseAudio"

"$RUNTIME" rm -f "$name-client-1" >/dev/null
connect 2
poll 30 "reconnection" sh -c "[ \"\$($RUNTIME exec $name grep -c 'connected to X11rdp_pid' /run/desktop/log/xrdp.log)\" -ge 2 ]"
[ "$(xorg_pid)" = "$before" ] || fail "reconnect started a new Xorg (session not resumed)"
exec_in "$name" /usr/local/bin/desktop healthcheck >/dev/null || fail "unhealthy after reconnect"
pass "connected=$(connections)"
