FROM ruby:4.0.7-slim AS build

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential git libsqlite3-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV RAILS_ENV=production

COPY Gemfile Gemfile.lock ./
RUN bundle config set without 'development test' && bundle install --jobs 4

COPY . .
# SECRET_KEY_BASE_DUMMY lets Rails boot for precompile without the production
# master key, which is intentionally not available at build time (it is injected
# at runtime via env_file). Precompiling assets needs no real credentials.
RUN SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile

FROM ruby:4.0.7-slim

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    libsqlite3-0 curl ca-certificates unzip sqlite3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN groupadd --system --gid 1000 rails \
    && useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

# yt-dlp is the fallback transcript source for YouTube videos whose captions the
# page's own endpoint no longer serves without a PoToken (see YtdlpCli). Install
# the *static* yt-dlp binary, not pip: the runtime stage is ruby:slim and
# installing via pip would drag Python in just to unzip a self-contained build
# (glibc 2.17+, no interpreter needed). ffmpeg is deliberately absent — the
# fallback only downloads subtitles (`--skip-download --write-subs`), which needs
# no muxing, so adding ffmpeg would only balloon the image.
#
# Version and asset are pinned (never `latest`), and the binary is verified
# against a SHA-256 fixed HERE in the Dockerfile rather than the release's
# co-downloaded SHA2-256SUMS: whoever can serve the binary could also serve a
# matching sums file, so that only proves the download was not truncated. A
# pinned digest also fails the build on a substituted binary. When bumping
# YTDLP_VERSION, update both digests from that release's SHA2-256SUMS
# (`grep -E ' yt-dlp_linux(_aarch64)?$'`).
#
# The release ships one asset per architecture (`yt-dlp_linux` is x86-64,
# `yt-dlp_linux_aarch64` is arm64). The build picks the one matching TARGETARCH
# and asserts the downloaded ELF's machine id (bytes 18-19: 0x3e for AMD64,
# 0xb7 for AArch64), so a local arm64 build gets a binary it can run and
# production stays x86-64 instead of embedding a foreign-arch binary that only
# fails at runtime under emulation. `--version` runs only where the host can
# execute the binary.
ARG YTDLP_VERSION=2026.08.19
ARG TARGETARCH
ARG YTDLP_SHA256_AMD64=58162f9bfdc27458ea47bfcb311cf47028f17d8154a8bf7d689861d46399230a
ARG YTDLP_SHA256_ARM64=b16e4dab368a816cd05d477d698a605a6ae87ccee1c8ffd38fa21d7254141fcc
RUN set -eux; \
    base="https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VERSION}"; \
    case "${TARGETARCH}" in \
      amd64) asset="yt-dlp_linux";         sha="${YTDLP_SHA256_AMD64}"; machine="3e00" ;; \
      arm64) asset="yt-dlp_linux_aarch64"; sha="${YTDLP_SHA256_ARM64}"; machine="b700" ;; \
      *) echo "unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    curl -fsSL -o /tmp/yt-dlp "${base}/${asset}"; \
    echo "${sha}  /tmp/yt-dlp" | sha256sum -c -; \
    actual="$(od -An -tx1 -j18 -N2 /tmp/yt-dlp | tr -d ' ')"; \
    [ "${actual}" = "${machine}" ] \
      || { echo "${asset} is not a ${TARGETARCH} ELF (machine id ${actual})" >&2; exit 1; }; \
    chmod +x /tmp/yt-dlp; \
    mv /tmp/yt-dlp /usr/local/bin/yt-dlp; \
    if [ "$(uname -m)" = "x86_64" ] || [ "$(uname -m)" = "aarch64" ]; then \
      /usr/local/bin/yt-dlp --version; \
    fi

# Pre-create opencode's XDG directories — including the exact path the compose
# file mounts a named volume on — owned by `rails`. Docker only seeds a fresh
# named volume from the image (preserving ownership) when that path already
# exists there; a missing mount point gets created as root, and then the `rails`
# user cannot write auth.json into it.
RUN mkdir -p /home/rails/.local/share/opencode /home/rails/.local/state /home/rails/.config \
    && chown -R rails:rails /home/rails/.local /home/rails/.config

# Pre-create yt-dlp's cache dir for the same reason: YtdlpCli runs as `rails`, and
# a root-owned `~/.cache` (or a Docker-created one) would make yt-dlp warn and
# fail to cache. Not a named volume today, but the ownership is set here so the
# cache is writable from the first run.
RUN mkdir -p /home/rails/.cache/yt-dlp \
    && chown -R rails:rails /home/rails/.cache

COPY --chown=rails:rails --from=build /usr/local/bundle /usr/local/bundle
COPY --chown=rails:rails --from=build /app /app

ENV RAILS_ENV=production
ENV RAILS_LOG_TO_STDOUT=true
ENV RAILS_SERVE_STATIC_FILES=true

EXPOSE 3000

USER rails

# opencode CLI generates the AI summaries for clippings (see SummaryGenerator).
# Must be the v2 CLI: summaries rely on `opencode run --standalone` and the v2
# `permissions` config. Note https://opencode.ai/install serves v1, so use the
# /v2/install endpoint or the container silently gets an incompatible CLI.
# --no-modify-path because this is a non-interactive image; PATH is set explicitly.
RUN curl -fsSL https://opencode.ai/v2/install | bash -s -- --no-modify-path
ENV PATH="/home/rails/.opencode/bin:${PATH}"

ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
