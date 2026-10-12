# docker-remote-desktop

A rootless XFCE desktop served over RDP ([xrdp](https://www.xrdp.org) on Ubuntu 24.04). Audio and clipboard are redirected; drive redirection is disabled. There is no login password: the RDP connection opens the desktop session directly.

![Screenshot of XFCE desktop](screenshot_2.png)

## Security model

Access control is network reachability, not authentication.

- xrdp binds to `127.0.0.1` by default. Anyone who can reach the port gets a desktop.
- Local mode (`./start`) publishes the port on `127.0.0.1:3389` only. It is meant for single-user workstations.
- On OpenShift/Kubernetes, reach the pod through `kubectl port-forward`/`oc port-forward`. The `pods/portforward` RBAC permission is then the security boundary.
- The container runs as UID 1001 (group 0) with all capabilities dropped, `no-new-privileges` and a read-only root filesystem (the helper scripts set this up).

## Quick start

```bash
docker build -t docker-remote-desktop:local .
./start        # detached, reachable on 127.0.0.1:3389
# connect an RDP client to 127.0.0.1:3389, then:
./stop
```

`./run` opens an interactive shell in the image (command mode) with the same hardening. Both scripts use the image in `$IMAGE` (default `docker-remote-desktop:local`) and persist the home directory in the `remote-desktop-home` volume.

The RDP certificate is self-signed and generated at every start, so the client will ask you to accept it.

## Configuration

| Setting | Effect |
|---|---|
| `RDP_LISTEN_ADDRESS` | IPv4 address xrdp listens on. Default `127.0.0.1`; the port is always 3389. `./start` sets `0.0.0.0` inside the container because Docker publishes the port only on the host's `127.0.0.1`. |
| `TZ` | Time zone of the desktop session (for example `-e TZ=Europe/Zurich`). |
| `/etc/desktop/tls/tls.crt`, `tls.key` | Mount a certificate and key (for example a `kubernetes.io/tls` secret) to use them instead of the generated pair. Both files must be present and readable by the container user. |

Logs from xrdp and the desktop components go to the container log (stdout/stderr) and to `/run/desktop/log/`.

## Extending

Use the image as a base:

```dockerfile
FROM docker-remote-desktop:local
USER root
RUN apt-get update && apt-get install -y --no-install-recommends my-app && rm -rf /var/lib/apt/lists/*
USER 1001
```

- Do not override `ENTRYPOINT`. The entrypoint is `desktop`: without arguments it starts the desktop; with arguments it runs them as the desktop user (command mode); `desktop healthcheck` is the liveness/startup probe.
- Keep `USER 1001` (primary group 0). The image also works under an arbitrary UID in group 0, as OpenShift assigns.
- Write only to `/home/wineuser`, `/run/desktop` and `/tmp`; everything else is read-only at runtime. Make files you add to the image group-0 readable (and group-writable if they must be written).
- `/etc/xrdp` is a symlink to a per-start runtime directory built from `/usr/share/desktop/xrdp-etc`. Customise xrdp configuration (keymaps and so on) under `/usr/share/desktop/xrdp-etc`, not `/etc/xrdp`.

### Init hooks

Every `/etc/desktop/init.d/*.sh` is sourced, in glob order, in both desktop and command mode, after the runtime directories and user identity are set up and before the desktop starts or the command is executed.

- Hooks may use `log` and `die` and may export variables; exported variables reach the desktop and the command.
- Only the final exit status of a hook counts: `set -e` is not active inside hooks. Write `cmd || die "message"` for each step that must not fail. A failing hook stops the container.

```bash
# /etc/desktop/init.d/50-example.sh
mkdir -p "$HOME/.config/example" || die "cannot create config directory"
export EXAMPLE_MODE=1
log "example hook done"
```

## Testing

```bash
tests/run IMAGE [tests/cases/NAME.sh ...]
```

Runs the cases in `tests/cases/*.sh` against `IMAGE` (all 13 cases if none are named, for example `tests/run docker-remote-desktop:local tests/cases/lifecycle.sh tests/cases/tls.sh`). The `rdp-e2e` case builds an RDP client image from `tests/rdp-client` and therefore needs network access.

## Accepted risks

- There is no RDP password: anyone who can reach port 3389 gets the desktop. Keep the default `127.0.0.1` or restrict access with network policy.
- Local mode on shared hosts exposes the desktop to every local user who can reach the loopback port.
- The clipboard is a data channel between client and desktop, in both directions.
- Ubuntu security fixes arrive with the weekly snapshot bump pull request, not immediately.

## Dependency updates

Dependencies are kept current by Renovate, plus a weekly pull request that moves the pinned Ubuntu apt snapshot forward.

## Breaking changes from upstream

- The `ubuntu` user and its password are gone; there is no login prompt.
- Firefox is gone (along with the Mozilla PPA, `git`, `vim`, `sudo` and `xfce4-goodies`).
- The image runs as UID 1001 instead of root, with a read-only root filesystem supported.
- xrdp listens on `127.0.0.1` by default instead of all interfaces.
- The image is published on GHCR (`ghcr.io/kamphaus/docker-remote-desktop`) instead of Docker Hub.
- Only `linux/amd64` images are built and published; the `linux/arm64` and `linux/arm/v7` images are gone.
