# ──────────────────────────────────────────────────────────────────────────────
# STAGE 4 — Runtime
# ──────────────────────────────────────────────────────────────────────────────
FROM fedora:42 AS runtime

LABEL stage="4-runtime"
LABEL description="olcrtc automated server — jitsi/telemost/wbstream over WebRTC"

# 4a. Minimal runtime packages (added: hostname, bc, gawk)
RUN dnf update -y \
    && dnf install -y \
        bash \
        coreutils \
        openssl \
        iputils \
        curl \
        ca-certificates \
        bind-utils \
        hostname \
        bc \
        gawk \
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

# ── Optional ENV variables ───────────────────────────────────────────────────
# IMPORTANT: OLCRTC_TRANSPORT default is EMPTY so the auto-detection
# script's choice (datachannel / vp8channel) is NOT overridden.
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
ENV OLCRTC_DEBUG="true"
ENV OLCRTC_UPSTREAM_PROXY_ADDR=""
ENV OLCRTC_UPSTREAM_PROXY_PORT=""
ENV OLCRTC_UPSTREAM_PROXY_USER=""
ENV OLCRTC_UPSTREAM_PROXY_PASS=""

EXPOSE 1080

ENTRYPOINT ["/opt/olcrtc/scripts/entrypoint.sh"]
