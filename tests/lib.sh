# shellcheck shell=bash
# Helpers shared by tests/cases/*.sh. Each case runs in its own bash process.
set -euo pipefail

IMAGE=${IMAGE:?IMAGE must be set (run cases through tests/run IMAGE)}
RUNTIME=${RUNTIME:-docker}
TEST_LABEL="desktop-test=$$"
TEST_NAME=$(basename "$0" .sh)
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Same restrictions as run-local and OpenShift restricted-v2.
HARDENED=(--user 123456:0 --read-only --cap-drop ALL --security-opt no-new-privileges
    --tmpfs /tmp:mode=1777 --tmpfs /run/desktop:mode=0770 --tmpfs /home/wineuser:mode=0770
    --shm-size 1g)

cleanup() {
    local ids
    ids=$("$RUNTIME" ps -aq --filter "label=$TEST_LABEL")
    [ -z "$ids" ] || "$RUNTIME" rm -f $ids >/dev/null
    ids=$("$RUNTIME" volume ls -q --filter "label=$TEST_LABEL")
    [ -z "$ids" ] || "$RUNTIME" volume rm -f $ids >/dev/null
}
trap cleanup EXIT

fail() { echo "FAIL [$TEST_NAME]: $*" >&2; exit 1; }
pass() { echo "PASS [$TEST_NAME]${1:+: $1}"; }

start_desktop() {
    local name="dt-$$-$1"
    shift
    "$RUNTIME" run -d --label "$TEST_LABEL" --name "$name" "${HARDENED[@]}" "$@" "$IMAGE" >/dev/null
    echo "$name"
}

run_cmd() { "$RUNTIME" run --rm --label "$TEST_LABEL" "${HARDENED[@]}" "$@"; }

exec_in() {
    local name=$1
    shift
    "$RUNTIME" exec "$name" "$@"
}

poll() {
    local timeout=$1 what=$2
    shift 2
    local deadline=$((SECONDS + timeout))
    until "$@" >/dev/null 2>&1; do
        [ "$SECONDS" -lt "$deadline" ] || fail "timed out after ${timeout}s waiting for $what"
        sleep 1
    done
}

wait_healthy() {
    local name=$1 timeout=${2:-90}
    local deadline=$((SECONDS + timeout))
    until exec_in "$name" /usr/local/bin/desktop healthcheck >/dev/null 2>&1; do
        if [ "$SECONDS" -ge "$deadline" ]; then
            "$RUNTIME" logs "$name" >&2 || true
            fail "$name not healthy after ${timeout}s"
        fi
        sleep 1
    done
}

# logs_contain NAME PATTERN: capture first, then grep (grep -q on a pipe makes `docker logs` die of SIGPIPE under pipefail)
logs_contain() {
    local out
    out=$("$RUNTIME" logs "$1" 2>&1)
    grep -q -- "$2" <<<"$out"
}

wait_exit() {
    local name=$1 timeout=$2
    timeout "$timeout" "$RUNTIME" wait "$name" || fail "$name still running after ${timeout}s"
}

# listening_on NAME 0100007F:0D3D -> true if a TCP socket is in LISTEN state on that address
listening_on() {
    exec_in "$1" awk -v want="$2" '$4 == "0A" && toupper($2) == want {found = 1} END {exit !found}' /proc/net/tcp
}

build_rdp_client() {
    "$RUNTIME" build -q -t desktop-test-rdp-client -f "$REPO_ROOT/tests/rdp-client/Dockerfile" "$REPO_ROOT" >/dev/null
    echo desktop-test-rdp-client
}
