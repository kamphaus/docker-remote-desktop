#!/usr/bin/env bash
source "$(dirname "$0")/../lib.sh"
dir=$(mktemp -d)
trap 'cleanup; rm -rf "$dir"' EXIT

fp() { exec_in "$1" openssl x509 -in /run/desktop/tls/tls.crt -noout -fingerprint -sha256; }
a=$(start_desktop tls-a)
b=$(start_desktop tls-b)
wait_healthy "$a"
wait_healthy "$b"
[ "$(fp "$a")" != "$(fp "$b")" ] || fail "two containers share a TLS certificate"

mkdir "$dir/full" "$dir/partial"
"$RUNTIME" run --rm --user "$(id -u):$(id -g)" -v "$dir/full:/out" --entrypoint openssl "$IMAGE" \
    req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=mounted -keyout /out/tls.key -out /out/tls.crt 2>/dev/null
cp "$dir/full/tls.crt" "$dir/partial/tls.crt"
chmod -R a+rX "$dir"

m=$(start_desktop tls-mounted -v "$dir/full:/etc/desktop/tls:ro")
wait_healthy "$m"
"$RUNTIME" logs "$m" 2>&1 | grep -q "using mounted TLS certificate /etc/desktop/tls/tls.crt" || fail "mounted cert not used"

p=$(start_desktop tls-partial -v "$dir/partial:/etc/desktop/tls:ro")
code=$(wait_exit "$p" 60)
[ "$code" != 0 ] || fail "started with only tls.crt mounted"
"$RUNTIME" logs "$p" 2>&1 | grep -q "both tls.crt and tls.key" || fail "unclear error for partial TLS mount"
pass
