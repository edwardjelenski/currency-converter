# syntax=docker/dockerfile:1
#
# Currency Converter server: Vapor + SQLite.
# Stage 1 builds a release binary with the Swift toolchain; stage 2 runs it on
# plain Ubuntu. The Swift runtime (incl. Foundation) is linked statically, so the
# final image needs no toolchain — only CA certificates, time zone data and curl.

# ---------- build ----------
FROM swift:6.4-noble AS build

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q install -y libjemalloc-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Resolve dependencies first so this layer is cached until Package.* changes.
COPY Package.swift Package.resolved ./
RUN swift package resolve --force-resolved-versions

# SwiftPM validates every target path on load, so tests/server must exist even
# though only the App product is built.
COPY src/server ./src/server
COPY tests/server ./tests/server

RUN swift build -c release --product App --static-swift-stdlib -Xlinker -ljemalloc

WORKDIR /staging
RUN cp "$(swift build --package-path /build -c release --show-bin-path)/App" ./ \
    && cp /usr/libexec/swift/linux/swift-backtrace-static ./

# ---------- run ----------
FROM ubuntu:noble

# ca-certificates: HTTPS to the rates source
# tzdata: the schedule runs on Europe/Berlin time
# curl: Compose healthcheck
RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update \
    && apt-get -q install -y --no-install-recommends libjemalloc2 ca-certificates tzdata curl \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --user-group --create-home --system --skel /dev/null --home-dir /app vapor \
    && mkdir /data && chown vapor:vapor /data

WORKDIR /app
COPY --from=build --chown=vapor:vapor /staging /app

ENV HOST=0.0.0.0 \
    PORT=8080 \
    DATABASE_PATH=/data/rates.sqlite \
    LOG_LEVEL=info \
    SWIFT_BACKTRACE=enable=yes,sanitize=yes,threads=all,images=all,interactive=no,swift-backtrace=./swift-backtrace-static

USER vapor:vapor
VOLUME /data
EXPOSE 8080

ENTRYPOINT ["./App"]
CMD ["serve", "--env", "production"]
