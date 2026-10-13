# shellcheck shell=bash
# Starts and supervises the desktop session components as the current (unprivileged) user.

DESKTOP_DISPLAY=10
# Must match xrdp-chansrv's hard-wired <socket root>/<uid> (Ubuntu's socket root is /run/xrdp/sockdir)
XRDP_SOCKET_DIR="/run/xrdp/sockdir/$(id -u)"
COMPONENT_PIDS=()

validate_config() {
    RDP_LISTEN_ADDRESS=${RDP_LISTEN_ADDRESS:-127.0.0.1}
    [[ "$RDP_LISTEN_ADDRESS" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] \
        || die "RDP_LISTEN_ADDRESS must be an IPv4 address (got '$RDP_LISTEN_ADDRESS')"
    export RDP_LISTEN_ADDRESS
}

# Leftovers from a previous run when /tmp or /run/desktop survive a container restart.
clean_stale_state() {
    rm -f "/tmp/.X${DESKTOP_DISPLAY}-lock" "/tmp/.X11-unix/X${DESKTOP_DISPLAY}" \
        "$DESKTOP_RUNTIME_DIR/xrdp/xrdp.pid" "$DESKTOP_RUNTIME_DIR/ready" "$XRDP_SOCKET_DIR"/*
    rm -rf "$XDG_RUNTIME_DIR/pulse"
    unset XRDP_SESMAN_MAX_IDLE_TIME XRDP_SESMAN_MAX_DISC_TIME XRDP_SESMAN_KILL_DISCONNECTED
}

# xrdp and chansrv read /etc/xrdp (compiled-in), and xrdp refuses to start without /etc/xrdp/rsakeys.ini even
# with security_layer=tls (the key is unused then). /etc/xrdp is a symlink to a per-start directory in the
# runtime dir: symlinks to the image's config plus a freshly generated key, so no key material is in the image.
setup_xrdp_config() {
    local dir="$DESKTOP_RUNTIME_DIR/xrdp-etc" f
    rm -rf "$dir"
    mkdir -p "$dir"
    for f in /usr/share/desktop/xrdp-etc/*; do ln -s "$f" "$dir/"; done
    xrdp-keygen xrdp "$dir/rsakeys.ini" >/dev/null 2>&1 || die "failed to generate $dir/rsakeys.ini"
}

start_component() {
    local name=$1
    shift
    log "starting $name"
    "$@" &
    COMPONENT_PIDS+=("$!")
}

wait_for() {
    local what=$1 timeout=$2 i
    shift 2
    for ((i = 0; i < timeout * 10; i++)); do
        "$@" 2>/dev/null && return 0
        sleep 0.1
    done
    die "timed out after ${timeout}s waiting for $what"
}

rdp_port_open() {
    local addr=$RDP_LISTEN_ADDRESS
    [ "$addr" != 0.0.0.0 ] || addr=127.0.0.1
    (exec 3<>"/dev/tcp/$addr/3389") 2>/dev/null
}

# True if a TCP socket is in LISTEN state on $RDP_LISTEN_ADDRESS:3389. Reads /proc instead of connecting, because
# every connection that sends no X.224 request makes xrdp log a burst of errors (probes run every few seconds).
rdp_port_listening() {
    local o1 o2 o3 o4 want
    IFS=. read -r o1 o2 o3 o4 <<<"$RDP_LISTEN_ADDRESS"
    printf -v want '%02X%02X%02X%02X:0D3D' $((10#$o4)) $((10#$o3)) $((10#$o2)) $((10#$o1))
    awk -v want="$want" '$4 == "0A" && toupper($2) == want {found = 1} END {exit !found}' /proc/net/tcp
}

start_xorg() {
    start_component Xorg env XRDP_SOCKET_PATH="$XRDP_SOCKET_DIR" /usr/lib/xorg/Xorg ":$DESKTOP_DISPLAY" \
        -config xrdp/xorg.conf -noreset -nolisten tcp -nolisten local -logfile "$DESKTOP_RUNTIME_DIR/log/Xorg.log"
    wait_for "the Xorg socket" 30 test -S "$XRDP_SOCKET_DIR/xrdp_display_$DESKTOP_DISPLAY"
    export DISPLAY=":$DESKTOP_DISPLAY"
}

start_chansrv() {
    start_component xrdp-chansrv env CHANSRV_LOG_PATH="$DESKTOP_RUNTIME_DIR/log" /usr/sbin/xrdp-chansrv
    wait_for "the chansrv socket" 30 test -S "$XRDP_SOCKET_DIR/xrdp_chansrv_socket_$DESKTOP_DISPLAY"
}

start_pulseaudio() {
    start_component pulseaudio env XRDP_SOCKET_PATH="$XRDP_SOCKET_DIR" pulseaudio -n \
        -F /etc/desktop/pulse/default.pa --daemonize=no --exit-idle-time=-1 --log-target=stderr
    wait_for "the PulseAudio socket" 30 test -S "$XDG_RUNTIME_DIR/pulse/native"
}

start_xfce() {
    start_component xfce dbus-launch --exit-with-session startxfce4
}

start_xrdp() {
    export DESKTOP_RUNTIME_DIR XRDP_SOCKET_DIR # envsubst only sees exported variables
    envsubst '${RDP_LISTEN_ADDRESS} ${TLS_CERT} ${TLS_KEY} ${DESKTOP_RUNTIME_DIR} ${XRDP_SOCKET_DIR}' \
        < /etc/desktop/xrdp.ini.tmpl > "$DESKTOP_RUNTIME_DIR/xrdp.ini"
    start_component xrdp /usr/sbin/xrdp --nodaemon --config "$DESKTOP_RUNTIME_DIR/xrdp.ini"
    wait_for "xrdp on $RDP_LISTEN_ADDRESS:3389" 30 rdp_port_open
}

stop_components() {
    local pid alive _
    for pid in "${COMPONENT_PIDS[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
    for _ in $(seq 100); do
        alive=0
        for pid in "${COMPONENT_PIDS[@]}"; do kill -0 "$pid" 2>/dev/null && alive=1; done
        [ "$alive" = 1 ] || return 0
        sleep 0.1
    done
    for pid in "${COMPONENT_PIDS[@]}"; do kill -KILL "$pid" 2>/dev/null || true; done
}

supervise() {
    trap 'log "termination requested"; stop_components; exit 0' TERM INT
    local rc=0
    wait -n "${COMPONENT_PIDS[@]}" || rc=$?
    log "a desktop component exited (status $rc); stopping the others"
    stop_components
    exit 1
}

healthcheck() {
    RDP_LISTEN_ADDRESS=${RDP_LISTEN_ADDRESS:-127.0.0.1}
    if ! [ -e "$DESKTOP_RUNTIME_DIR/ready" ]; then
        echo "unhealthy: desktop not ready yet" >&2
        return 1
    fi
    if ! [ -S "$XRDP_SOCKET_DIR/xrdp_display_$DESKTOP_DISPLAY" ]; then
        echo "unhealthy: Xorg socket missing" >&2
        return 1
    fi
    if ! rdp_port_listening; then
        echo "unhealthy: xrdp not accepting connections on port 3389" >&2
        return 1
    fi
}
