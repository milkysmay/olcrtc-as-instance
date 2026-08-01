# ==============================================================================
# olcrtc — Automated Docker Build (Fedora, 4 stages)
# ==============================================================================
# Stage 1 (builder)   – update system, install deps, compile binary
# Stage 2 (scripts)   – prepare & validate helper shell scripts
# Stage 3 (defaults)  – generate default secrets / room-name seeds
# Stage 4 (runtime)   – minimal runtime image, entrypoint orchestrates
#                       Phase 2 → check providers
#                       Phase 3 → generate config
#                       Phase 4 → launch server & log olcrtc:// URI
# ==============================================================================

# ──────────────────────────────────────────────────────────────────────────────
# STAGE 1 — Installing & Building
# ──────────────────────────────────────────────────────────────────────────────
FROM fedora:42 AS builder

LABEL stage="1-installing"

# 1a. Update all system packages
RUN dnf update -y && dnf clean all

# 1b. Install build dependencies
RUN dnf install -y \
        git \
        golang \
        openssl \
        gcc \
        make \
        ca-certificates \
    && dnf clean all

# 1c. Install mage (Go build system)
ENV GOPATH=/root/go
ENV PATH="${GOPATH}/bin:/usr/local/go/bin:${PATH}"
RUN go install github.com/magefile/mage@latest

# 1d. Clone the repository (with submodules)
WORKDIR /src
RUN git clone --recurse-submodules https://github.com/openlibrecommunity/olcrtc.git .

# 1e. Build the binary
RUN mage build

# Verify the binary exists
RUN test -f build/olcrtc-linux-amd64 && echo "✓ Binary built successfully"


# ──────────────────────────────────────────────────────────────────────────────
# STAGE 2 — Preparing & Validating Scripts
# ──────────────────────────────────────────────────────────────────────────────
FROM fedora:42 AS scripts

LABEL stage="2-scripts"

RUN dnf update -y && dnf install -y bash coreutils && dnf clean all

WORKDIR /opt/olcrtc/scripts

# Copy helper scripts
COPY scripts/entrypoint.sh          ./
COPY scripts/check-providers.sh     ./
COPY scripts/generate-config.sh     ./
COPY scripts/generate-room-name.sh  ./
COPY scripts/run-server.sh          ./

# Make executable & validate syntax
RUN chmod +x *.sh \
    && for f in *.sh; do bash -n "$f" && echo "✓ $f syntax OK"; done


# ──────────────────────────────────────────────────────────────────────────────
# STAGE 3 — Generating Defaults (crypto key seed, room-name word lists)
# ──────────────────────────────────────────────────────────────────────────────
FROM fedora:42 AS defaults

LABEL stage="3-defaults"

RUN dnf update -y && dnf install -y openssl bash coreutils && dnf clean all

WORKDIR /opt/olcrtc/defaults

# Generate a default crypto key (can be overridden via ENV at runtime)
RUN openssl rand -hex 32 > crypto_key.default \
    && echo "✓ Default crypto key generated"

# Room-name word lists (no proxy/vpn/olcrtc/tunnel words)
RUN mkdir -p words
COPY scripts/generate-room-name.sh /tmp/gen-room.sh
RUN bash /tmp/gen-room.sh --dump-words > words/adjectives.txt 2>/dev/null || true


# ──────────────────────────────────────────────────────────────────────────────
# STAGE 4 — Runtime
# ──────────────────────────────────────────────────────────────────────────────
FROM fedora:42 AS runtime

LABEL stage="4-runtime"
LABEL maintainer="olcrtc-docker"
LABEL description="olcrtc automated server — jitsi/telemost/wbstream over WebRTC"

# 4a. Minimal runtime packages
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

# 4b. Copy binary from Stage 1
COPY --from=builder /src/build/olcrtc-linux-amd64 /usr/local/bin/olcrtc
RUN chmod +x /usr/local/bin/olcrtc

# 4c. Copy validated scripts from Stage 2
COPY --from=scripts /opt/olcrtc/scripts/ /opt/olcrtc/scripts/

# 4d. Copy defaults from Stage 3
COPY --from=defaults /opt/olcrtc/defaults/ /opt/olcrtc/defaults/

# 4e. Working directory & config path
WORKDIR /opt/olcrtc
RUN mkdir -p /opt/olcrtc/config /opt/olcrtc/logs

# ── Optional ENV variables (all have sane defaults) ──────────────────────────
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
