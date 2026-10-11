# syntax=docker/dockerfile:1

# Ubuntu archive snapshot for every apt operation; bumped weekly by .github/workflows/snapshot-bump.yml
ARG UBUNTU_SNAPSHOT=20261001T000000Z

FROM ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55 AS base
ARG UBUNTU_SNAPSHOT
COPY --chmod=0755 build/apt-snapshot /usr/local/sbin/apt-snapshot
RUN apt-snapshot "${UBUNTU_SNAPSHOT}"

FROM base
