#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"

out=$("$RUNTIME" run --rm --user 0 --entrypoint find "$IMAGE" / -xdev -perm /6000 -type f)
[ -z "$out" ] || fail "setuid/setgid files present: $out"

out=$("$RUNTIME" run --rm --user 0 --entrypoint bash "$IMAGE" -c \
    'ls /etc/xrdp/cert.pem /etc/xrdp/key.pem /etc/xrdp/rsakeys.ini /etc/ssl/private/ssl-cert-snakeoil.key /etc/ssl/certs/ssl-cert-snakeoil.pem 2>/dev/null; true')
[ -z "$out" ] || fail "key material baked into image: $out"

out=$("$RUNTIME" run --rm --entrypoint bash "$IMAGE" -c \
    'for b in xfce4-screensaver light-locker xscreensaver gnome-screensaver sudo firefox git vim; do command -v "$b"; done; true')
[ -z "$out" ] || fail "forbidden binaries present: $out"

out=$("$RUNTIME" run --rm --entrypoint bash "$IMAGE" -c \
    "grep -l \$'\\r' /usr/local/bin/desktop /usr/local/lib/desktop/*.sh /usr/local/sbin/apt-snapshot; true")
[ -z "$out" ] || fail "CRLF line endings in: $out"
pass
