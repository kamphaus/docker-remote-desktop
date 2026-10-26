# syntax=docker/dockerfile:1
# RDP client used by tests/cases/rdp-e2e.sh (FreeRDP under Xvfb).
# Stays on Ubuntu 24.04 although the image is on 26.04: 26.04 has no freerdp2-x11 (only freerdp3-x11),
# and the test client's base does not affect the image under test.
ARG UBUNTU_SNAPSHOT=20261026T000000Z
FROM ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55
ARG UBUNTU_SNAPSHOT
COPY --chmod=0755 build/apt-snapshot /usr/local/sbin/apt-snapshot
RUN apt-snapshot "${UBUNTU_SNAPSHOT}" \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends freerdp2-x11 xauth xvfb \
 && rm -rf /var/lib/apt/lists/*
