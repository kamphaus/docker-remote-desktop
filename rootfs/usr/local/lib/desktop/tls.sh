# shellcheck shell=bash
# TLS material for xrdp: a mounted kubernetes.io/tls pair, or a fresh self-signed pair per start.

setup_tls() {
    local mounted=/etc/desktop/tls generated="$DESKTOP_RUNTIME_DIR/tls"
    if [ -e "$mounted/tls.crt" ] || [ -e "$mounted/tls.key" ]; then
        [ -r "$mounted/tls.crt" ] && [ -r "$mounted/tls.key" ] \
            || die "$mounted must contain both tls.crt and tls.key, readable by uid $(id -u)"
        TLS_CERT="$mounted/tls.crt"
        TLS_KEY="$mounted/tls.key"
        log "using mounted TLS certificate $TLS_CERT"
    else
        TLS_CERT="$generated/tls.crt"
        TLS_KEY="$generated/tls.key"
        (umask 077 && openssl req -x509 -newkey rsa:3072 -nodes -days 825 \
            -subj "/CN=docker-remote-desktop" -keyout "$TLS_KEY" -out "$TLS_CERT" 2>/dev/null) \
            || die "failed to generate a TLS certificate in $generated"
        log "generated TLS certificate, $(openssl x509 -in "$TLS_CERT" -noout -fingerprint -sha256)"
    fi
    export TLS_CERT TLS_KEY
}
