# syntax=docker/dockerfile:1@sha256:4edf897a3ffa55b89f906fc8cc78afdb3f1834cc9c7083565e611a8a7d5fe99e

# Ubuntu archive snapshot for every apt operation; bumped weekly by .github/workflows/snapshot-bump.yml
ARG UBUNTU_SNAPSHOT=20261001T000000Z

FROM ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55 AS base
ARG UBUNTU_SNAPSHOT
COPY --chmod=0755 build/apt-snapshot /usr/local/sbin/apt-snapshot
RUN apt-snapshot "${UBUNTU_SNAPSHOT}"

FROM base AS pulse-builder
# renovate: datasource=github-tags depName=neutrinolabs/pulseaudio-module-xrdp
ARG PULSE_XRDP_VERSION=v0.8
ARG PULSE_XRDP_COMMIT=f36911ee49a85dce19ecc3d53b0edaee624c9faa
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      autoconf build-essential dpkg-dev git libltdl-dev libpulse-dev libtool lsb-release sudo \
 && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch "${PULSE_XRDP_VERSION}" https://github.com/neutrinolabs/pulseaudio-module-xrdp.git /src \
 && test "$(git -C /src rev-parse HEAD)" = "${PULSE_XRDP_COMMIT}"
WORKDIR /src
RUN scripts/install_pulseaudio_sources_apt.sh \
 && ./bootstrap \
 && ./configure PULSE_DIR="${HOME}/pulseaudio.src" \
 && make \
 && make install DESTDIR=/tmp/install \
 && mkdir /out \
 && find /tmp/install -name 'module-xrdp-*.so' -exec cp {} /out/ \; \
 && test -f /out/module-xrdp-sink.so && test -f /out/module-xrdp-source.so

FROM base
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      dbus-x11 gettext-base libnss-wrapper locales openssl pavucontrol pulseaudio pulseaudio-utils tini tzdata \
      x11-xserver-utils xfce4 xfce4-pulseaudio-plugin xfce4-terminal xorgxrdp xrdp xubuntu-icon-theme \
 && rm -rf /var/lib/apt/lists/* \
 && locale-gen en_US.UTF-8
COPY --from=pulse-builder /out/ /tmp/pulse-modules/
RUN moddir="$(dirname "$(dpkg -L pulseaudio | grep -m1 '/modules/module-null-sink.so$')")" \
 && install -m 0644 /tmp/pulse-modules/module-xrdp-*.so "${moddir}/" \
 && rm -rf /tmp/pulse-modules
COPY rootfs/ /
RUN chmod 0755 /usr/local/bin/desktop \
 && chmod 0644 /usr/local/lib/desktop/*.sh \
 && userdel --remove ubuntu \
 && useradd --uid 1001 --gid 0 --home-dir /home/wineuser --no-create-home --shell /bin/bash wineuser \
 && rm -f /etc/xrdp/cert.pem /etc/xrdp/key.pem /etc/xrdp/rsakeys.ini \
          /etc/ssl/private/ssl-cert-snakeoil.key /etc/ssl/certs/ssl-cert-snakeoil.pem \
 && mkdir -p /usr/share/desktop && mv /etc/xrdp /usr/share/desktop/xrdp-etc \
 && ln -s /run/desktop/xrdp-etc /etc/xrdp \
 && rm -rf /run/xrdp && ln -s /run/desktop/xrdp /run/xrdp \
 && mkdir -p /home/wineuser /run/desktop /etc/desktop/init.d \
 && chgrp -R 0 /home/wineuser /run/desktop \
 && chmod -R g=u /home/wineuser /run/desktop \
 && find / -xdev -perm /6000 -type f -exec chmod a-s {} +
ENV LANG=en_US.UTF-8 HOME=/home/wineuser
LABEL org.opencontainers.image.source="https://github.com/kamphaus/docker-remote-desktop"

USER 1001
WORKDIR /home/wineuser
EXPOSE 3389/tcp
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/desktop"]
