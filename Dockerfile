# ==============================================================================
# olcrtc — Automated Docker Build (Fedora, 4 stages)
# ==============================================================================
# Stage 1 (builder)   – update system, install Go 1.26.5, compile binary
# Stage 2 (scripts)   – prepare & validate helper shell scripts
# Stage 3 (defaults)  – generate default secrets / room-name seeds
# Stage 4 (runtime)   – minimal runtime image, entrypoint orchestrates
#                       Phase 2 → check providers (ping)
#                       Phase 3 → generate config + crypto key
#                       Phase 4 → launch server & log olcrtc:// URI
# ==============================================================================

# ──────────────────────────────────────────────────────────────────────────────
# STAGE 1 — Installing & Building
# ──────────────────────────────────────────────────────────────────────────────
FROM fedora:42 AS builder

LABEL stage="1-installing"

RUN dnf update -y && dnf clean all

RUN dnf install -y \
        git \
        gcc \
        make \
        openssl \
        ca-certificates \
        tar \
        gzip \
        which \
        curl \
    && dnf clean all

# Go 1.26.5 (project requires >= 1.26.3; Fedora 42 dnf ships only 1.25.x)
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

RUN go install github.com/magefile/mage@latest \
    && mage -version

WORKDIR /src
RUN git clone --recurse-submodules https://github.com/openlibrecommunity/olcrtc.git .

RUN mage build

RUN test -f build/olcrtc-linux-amd64 && echo "✓ Binary built successfully"


# ──────────────────────────────────────────────────────────────────────────────
# STAGE 2 — Preparing & Validating Scripts
# ──────────────────────────────────────────────────────────────────────────────
FROM fedora:42 AS scripts

LABEL stage="2-scripts"

RUN dnf update -y && dnf install -y bash coreutils && dnf clean all

WORKDIR /opt/olcrtc/scripts

COPY scripts/entrypoint.sh          ./
COPY scripts/check-providers.sh     ./
COPY scripts/generate-config.sh     ./
COPY scripts/generate-room-name.sh  ./
COPY scripts/run-server.sh          ./

RUN chmod +x *.sh \
    && for f in *.sh; do bash -n "$f" && echo "✓ $f syntax OK"; done


# ──────────────────────────────────────────────────────────────────────────────
# STAGE 3 — Generating Defaults
# ──────────────────────────────────────────────────────────────────────────────
FROM fedora:42 AS defaults

LABEL stage="3-defaults"

RUN dnf update -y && dnf install -y openssl bash coreutils && dnf clean all

WORKDIR /opt/olcrtc/defaults

RUN openssl rand -hex 32 > crypto_key.default \
    && echo "✓ Default crypto key generated"

RUN mkdir -p words
COPY scripts/generate-room-name.sh /tmp/gen-room.sh
RUN bash /tmp/gen-room.sh --dump-words > words/adjectives.txt 2>/dev/null || true


# ──────────────────────────────────────────────────────────────────────────────
# STAGE 4 — Runtime
# ──────────────────────────────────────────────────────────────────────────────
FROM fedora:42 AS runtime

LABEL stage="4-runtime"
LABEL description="olcrtc automated server — jitsi/telemost/wbstream over WebRTC"

RUN dnf update -y \
    && dnf install -y \
        bash \
        coreutils \
        openssl \
        iputils \
        curl \
        ca-certificates \
        bind-utils \
    && dnf clean all

COPY --from=builder /src/build/olcrtc-linux-amd64 /usr/local/bin/olcrtc
RUN chmod +x /usr/local/bin/olcrtc

COPY --from=scripts /opt/olcrtc/scripts/ /opt/olcrtc/scripts/
COPY --from=defaults /opt/olcrtc/defaults/ /opt/olcrtc/defaults/

WORKDIR /opt/olcrtc
RUN mkdir -p /opt/olcrtc/config /opt/olcrtc/logs

# ── Optional ENV variables ───────────────────────────────────────────────────
ENV OLCRTC_PROVIDER=""
ENV OLCRTC_TRANSPORT="datachannel"
ENV OLCRTC_JITSI_INSTANCE=""
ENV OLCRTC_ROOM_ID=""
ENV OLCRTC_CRYPTO_KEY=""
ENV OLCRTC_DNS="8.8.8.8:53"
ENV OLCRTC_MODE="srv"
ENV OLCRTC_SOCKS_HOST="0.0.0.0"
ENV OLCRTC_SOCKS_PORT="1080"
ENV OLCRTC_SOCKS_USER=""
ENV OLCRTC_SOCKS_PASS=""
ENV OLCRTC_DEBUG="true"
ENV OLCRTC_UPSTREAM_PROXY_ADDR=""
ENV OLCRTC_UPSTREAM_PROXY_PORT=""
ENV OLCRTC_UPSTREAM_PROXY_USER=""
ENV OLCRTC_UPSTREAM_PROXY_PASS=""

EXPOSE 1080

ENTRYPOINT ["/opt/olcrtc/scripts/entrypoint.sh"]
