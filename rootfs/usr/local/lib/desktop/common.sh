# shellcheck shell=bash
# Shared helpers for /usr/local/bin/desktop and the init hooks in /etc/desktop/init.d.

DESKTOP_RUNTIME_DIR=${DESKTOP_RUNTIME_DIR:-/run/desktop}
DESKTOP_USER=wineuser

log() { printf '%s desktop: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

is_true() { [[ "${1,,}" =~ ^(1|true|yes|on)$ ]]; }

require_writable() {
    local dir
    for dir in "$@"; do
        if ! [ -d "$dir" ] || ! [ -w "$dir" ]; then
            die "$dir is not writable by uid $(id -u) gid $(id -g); mount a writable volume or tmpfs there"
        fi
    done
}

setup_runtime_dirs() {
    require_writable "$DESKTOP_RUNTIME_DIR" "$HOME" /tmp
    # xrdp 0.10 puts its sockets in a per-uid directory below the compiled-in root /run/xrdp/sockdir
    mkdir -p "$DESKTOP_RUNTIME_DIR"/{log,tls,nss,xdg} "$DESKTOP_RUNTIME_DIR/xrdp/sockdir/$(id -u)"
    chmod 0700 "$DESKTOP_RUNTIME_DIR/xdg"
    export XDG_RUNTIME_DIR="$DESKTOP_RUNTIME_DIR/xdg"
}

# Give arbitrary UIDs (OpenShift restricted-v2) the stable name $DESKTOP_USER via nss_wrapper.
setup_identity() {
    local uid gid nss="$DESKTOP_RUNTIME_DIR/nss"
    uid=$(id -u)
    gid=$(id -g)
    export USER="$DESKTOP_USER" LOGNAME="$DESKTOP_USER"
    if [ "$(getent passwd "$uid" | cut -d: -f1)" = "$DESKTOP_USER" ]; then
        return 0
    fi
    grep -v "^${DESKTOP_USER}:" /etc/passwd > "$nss/passwd"
    printf '%s:x:%s:%s::%s:/bin/bash\n' "$DESKTOP_USER" "$uid" "$gid" "$HOME" >> "$nss/passwd"
    cp /etc/group "$nss/group"
    getent group "$gid" >/dev/null || printf '%s:x:%s:\n' "$DESKTOP_USER" "$gid" >> "$nss/group"
    export NSS_WRAPPER_PASSWD="$nss/passwd" NSS_WRAPPER_GROUP="$nss/group"
    export LD_PRELOAD="libnss_wrapper.so${LD_PRELOAD:+:$LD_PRELOAD}"
}

run_init_hooks() {
    local hook
    for hook in /etc/desktop/init.d/*.sh; do
        [ -e "$hook" ] || continue
        log "running init hook $hook"
        # shellcheck source=/dev/null
        source "$hook" || die "init hook $hook failed"
    done
}
