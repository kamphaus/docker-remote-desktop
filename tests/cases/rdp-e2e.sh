#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"

client_image=$(build_rdp_client)
name=$(start_desktop e2e)
wait_healthy "$name" 90

connect() {
    "$RUNTIME" run -d -i --init --label "$TEST_LABEL" --name "$name-client-$1" --network "container:$name" "$client_image" \
        xvfb-run -a xfreerdp /v:127.0.0.1:3389 /cert:ignore /sec:tls /u:wineuser /p:unused \
        /sound:sys:fake /drive:tmp,/tmp +clipboard >/dev/null
}
connections() { exec_in "$name" grep -c 'connected to Xorg_pid' /run/desktop/log/xrdp.log || true; }
xorg_pid() { exec_in "$name" sh -c 'for p in /proc/[0-9]*; do [ "$(cat "$p/comm" 2>/dev/null)" = Xorg ] && echo "${p#/proc/}"; done; true'; }

# Negotiated rdpsnd shows up as one "sound_process_training" line per connection in the chansrv log.
poll_sound() { poll 30 "$1" sh -c "[ \"\$($RUNTIME exec $name grep -c sound_process_training /run/desktop/log/xrdp-chansrv.10.log)\" -ge $2 ]"; }

before=$(xorg_pid)
[ -n "$before" ] || fail "no Xorg process found"
connect 1
poll 30 "first RDP session" sh -c "[ \"\$($RUNTIME exec $name grep -c 'connected to Xorg_pid' /run/desktop/log/xrdp.log)\" -ge 1 ]"
# xrdp 0.10 chansrv always uses a per-uid directory below its compiled-in socket root
poll 30 "audio channel" exec_in "$name" sh -c 'test -S "/run/xrdp/sockdir/$(id -u)/xrdp_chansrv_audio_out_socket_10"'
poll_sound "rdpsnd negotiation (first session)" 1
sinks=$(exec_in "$name" env XDG_RUNTIME_DIR=/run/desktop/xdg pactl list short sinks)
grep -q xrdp-sink <<<"$sinks" || fail "xrdp-sink not present in PulseAudio"

"$RUNTIME" rm -f "$name-client-1" >/dev/null
connect 2
poll 30 "reconnection" sh -c "[ \"\$($RUNTIME exec $name grep -c 'connected to Xorg_pid' /run/desktop/log/xrdp.log)\" -ge 2 ]"
poll_sound "rdpsnd negotiation (reconnect)" 2
[ "$(xorg_pid)" = "$before" ] || fail "reconnect started a new Xorg (session not resumed)"
exec_in "$name" /usr/local/bin/desktop healthcheck >/dev/null || fail "unhealthy after reconnect"
chansrv_log=$(exec_in "$name" cat /run/desktop/log/xrdp-chansrv.10.log)
if grep -q 'Detected remote drive' <<<"$chansrv_log"; then fail "drive redirection was negotiated"; fi
pass "connected=$(connections)"
