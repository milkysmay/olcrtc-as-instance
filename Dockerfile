# syntax=docker/dockerfile:1
# ==============================================================================
# olcrtc — Automated Docker Build (Fedora, 4 stages)
# Stage 0 = builder | Stage 1 = scripts | Stage 2 = defaults | Stage 3 = runtime
# ==============================================================================

# ──────────────────────────────────────────────────────────────────────────────
# STAGE 0 — Installing & Building
# ──────────────────────────────────────────────────────────────────────────────
FROM fedora:42

RUN dnf update -y && dnf clean all

RUN dnf install -y \
        git gcc make openssl ca-certificates tar gzip which curl \
    && dnf clean all

ENV GO_VERSION=1.26.5
ENV GOROOT=/usr/local/go
ENV GOPATH=/root/go
ENV PATH="${GOROOT}/bin:${GOPATH}/bin:${PATH}"
ENV GOTOOLCHAIN=auto

RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" \
        -o /tmp/go.tar.gz \
    && tar -C /usr/local -xzf /tmp/go.tar.gz \
    && rm -f /tmp/go.tar.gz \
    && go version

RUN go install github.com/magefile/mage@latest && mage -version

WORKDIR /src
RUN git clone --recurse-submodules https://github.com/openlibrecommunity/olcrtc.git .
RUN mage build
RUN test -f build/olcrtc-linux-amd64 && echo "OK binary built"


# ──────────────────────────────────────────────────────────────────────────────
# STAGE 1 — Preparing & Validating Scripts
# ──────────────────────────────────────────────────────────────────────────────
FROM fedora:42

RUN dnf update -y && dnf install -y bash coreutils && dnf clean all

WORKDIR /opt/olcrtc/scripts

COPY scripts/entrypoint.sh          ./
COPY scripts/check-providers.sh     ./
COPY scripts/generate-config.sh     ./
COPY scripts/generate-room-name.sh  ./
COPY scripts/run-server.sh          ./

RUN chmod +x *.sh \
    && for f in *.sh; do bash -n "$f" && echo "OK $f"; done


# ──────────────────────────────────────────────────────────────────────────────
# STAGE 2 — Generating Defaults
# ──────────────────────────────────────────────────────────────────────────────
FROM fedora:42

RUN dnf update -y && dnf install -y openssl bash coreutils && dnf clean all

WORKDIR /opt/olcrtc/defaults

RUN openssl rand -hex 32 > crypto_key.default

RUN mkdir -p words
COPY scripts/generate-room-name.sh /tmp/gen-room.sh
RUN bash /tmp/gen-room.sh --dump-words > words/adjectives.txt 2>/dev/null || true


# ──────────────────────────────────────────────────────────────────────────────
# STAGE 3 — Runtime (final image)
# ──────────────────────────────────────────────────────────────────────────────
FROM fedora:42

RUN dnf update -y \
    && dnf install -y \
        bash coreutils openssl iputils curl ca-certificates \
        bind-utils hostname bc gawk python3 \
    && dnf clean all

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

COPY --from=0 /src/build/olcrtc-linux-amd64 /usr/local/bin/olcrtc
RUN chmod +x /usr/local/bin/olcrtc

COPY --from=1 /opt/olcrtc/scripts/ /opt/olcrtc/scripts/
COPY --from=2 /opt/olcrtc/defaults/ /opt/olcrtc/defaults/

WORKDIR /opt/olcrtc
RUN mkdir -p /opt/olcrtc/config /opt/olcrtc/logs

# ── Optional ENV ─────────────────────────────────────────────────────────────
ENV OLCRTC_PROVIDER=""
ENV OLCRTC_TRANSPORT=""
ENV OLCRTC_JITSI_INSTANCE=""
ENV OLCRTC_ROOM_ID=""
ENV OLCRTC_CRYPTO_KEY=""
ENV OLCRTC_DNS="8.8.8.8:53"
ENV OLCRTC_MODE="srv"
ENV OLCRTC_SOCKS_HOST="0.0.0.0"
ENV OLCRTC_SOCKS_PORT="1080"
ENV OLCRTC_SOCKS_USER=""
ENV OLCRTC_SOCKS_PASS=""
ENV OLCRTC_UPSTREAM_PROXY_ADDR=""
ENV OLCRTC_UPSTREAM_PROXY_PORT=""
ENV OLCRTC_UPSTREAM_PROXY_USER=""
ENV OLCRTC_UPSTREAM_PROXY_PASS=""
ENV OLCRTC_TEST_ALL_PROVIDERS="false"
ENV OLCRTC_DEBUG="true"

EXPOSE 1080

ENTRYPOINT ["/opt/olcrtc/scripts/entrypoint.sh"]
