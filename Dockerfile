# syntax=docker/dockerfile:1

# Ubuntu archive snapshot for every apt operation; bumped weekly by .github/workflows/snapshot-bump.yml
ARG UBUNTU_SNAPSHOT=20261001T000000Z

FROM ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55 AS base
ARG UBUNTU_SNAPSHOT
COPY --chmod=0755 build/apt-snapshot /usr/local/sbin/apt-snapshot
RUN apt-snapshot "${UBUNTU_SNAPSHOT}"

FROM base
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      libnss-wrapper locales tini \
 && rm -rf /var/lib/apt/lists/* \
 && locale-gen en_US.UTF-8
COPY rootfs/ /
RUN chmod 0755 /usr/local/bin/desktop \
 && chmod 0644 /usr/local/lib/desktop/*.sh \
 && userdel --remove ubuntu \
 && useradd --uid 1001 --gid 0 --home-dir /home/wineuser --no-create-home --shell /bin/bash wineuser \
 && mkdir -p /home/wineuser /run/desktop /etc/desktop/init.d \
 && chgrp -R 0 /home/wineuser /run/desktop \
 && chmod -R g=u /home/wineuser /run/desktop \
 && find / -xdev -perm /6000 -type f -exec chmod a-s {} +
ENV LANG=en_US.UTF-8 HOME=/home/wineuser
USER 1001
WORKDIR /home/wineuser
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/desktop"]
