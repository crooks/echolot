# Echolot pinger for yamn remailers, in two variants:
#
#   hostmail    no MTA inside; the host's mail server delivers the pinger's
#               mail into the volume, outgoing mail goes out through msmtp
#   standalone  with Postfix inside (port 25); needs only Docker or Podman
#
# Build from the root of this repository:
#   docker build -f contrib/yamn/docker/Dockerfile --target standalone -t echolot-yamn:standalone .
#   docker build -f contrib/yamn/docker/Dockerfile --target hostmail   -t echolot-yamn:hostmail .
# See contrib/yamn/docker/README.md.

# yamn, as published by its author.  Override to build another version or
# a fork, e.g. --build-arg YAMN_REPO=https://github.com/go-while/yamn
# --build-arg YAMN_REF=master
ARG YAMN_REPO=https://github.com/crooks/yamn
ARG YAMN_REF=f917ace

FROM golang:1.27-trixie AS yamn
ARG YAMN_REPO
ARG YAMN_REF
RUN git clone "$YAMN_REPO" /src/yamn \
 && cd /src/yamn \
 && git checkout --detach "$YAMN_REF" \
 && CGO_ENABLED=0 go build -trimpath -o /yamn . \
 && /yamn --version

FROM debian:trixie-slim AS base
ARG PINGER_UID=10000
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      perl libgnupg-interface-perl libhtml-template-perl gnupg \
      tini ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY --from=yamn /yamn /usr/local/bin/yamn
COPY . /opt/echolot
RUN useradd --uid "$PINGER_UID" --home-dir /var/lib/echolot --no-create-home \
      --shell /usr/sbin/nologin pinger \
 && mkdir -p /var/lib/echolot && chown pinger:pinger /var/lib/echolot \
 && install -m 755 /opt/echolot/contrib/yamn/docker/entrypoint.sh /usr/local/bin/echolot-entrypoint \
 && printf '#!/bin/sh\n# Run pingd as the pinger user, e.g. "docker exec <container> pingd add <address>".\nif [ "$(id -u)" = 0 ]; then exec runuser -u pinger -- /opt/echolot/pingd "$@"; fi\nexec /opt/echolot/pingd "$@"\n' > /usr/local/bin/pingd \
 && chmod 755 /usr/local/bin/pingd
ENV ECHOLOT_HOME=/var/lib/echolot \
    YAMN=/usr/local/bin/yamn
VOLUME /var/lib/echolot
# check-pinger reports stale results or pings that stopped coming back.
# New pingers need a while before the first ping returns.
HEALTHCHECK --interval=30m --timeout=1m --start-period=3h \
  CMD runuser -u pinger -- /opt/echolot/contrib/yamn/check-pinger /var/lib/echolot
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/echolot-entrypoint"]
CMD ["run"]

FROM base AS hostmail
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends msmtp-mta \
 && rm -rf /var/lib/apt/lists/*
ENV PINGER_MAIL=hostmail

FROM base AS standalone
RUN echo "postfix postfix/main_mailer_type select No configuration" | debconf-set-selections \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends postfix openssl \
 && rm -rf /var/lib/apt/lists/* \
 && cp /usr/share/postfix/main.cf.debian /etc/postfix/main.cf
ENV PINGER_MAIL=postfix
VOLUME /var/spool/postfix
EXPOSE 25
