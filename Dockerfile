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
# the *static* `yt-dlp_linux` binary, not pip: the runtime stage is ruby:slim and
# installing via pip would drag Python in just to unzip a self-contained build
# (glibc 2.17+, no interpreter needed). ffmpeg is deliberately absent — the
# fallback only downloads subtitles (`--skip-download --write-subs`), which needs
# no muxing, so adding ffmpeg would only balloon the image.
#
# Version and asset URL are pinned (never `latest`), and the binary is verified
# against a SHA-256 fixed HERE in the Dockerfile rather than against the release's
# co-downloaded SHA2-256SUMS: whoever can serve the binary could also serve a
# matching sums file, so checking the sums only proves the download was not
# truncated. Pinning the expected digest means a substituted or tampered binary
# fails the build, not just a corrupt one. When bumping YTDLP_VERSION, update
# YTDLP_SHA256 from that release's SHA2-256SUMS (`grep ' yt-dlp_linux$'`).
# The binary lives alone in /usr/local/bin; the temp artifact is removed here.
#
# `yt-dlp_linux` is an x86-64 asset; the production host is amd64. The image is
# built from any arch though (an Apple Silicon laptop is arm64), so the binary is
# also inspected to confirm it really is an x86-64 ELF — bytes 18-19 of the ELF
# header are the machine id, 0x3e for AMD64 — instead of trusting the filename.
# Running `--version` only happens where the host can execute it, so an arm64
# build does not fail on a valid amd64 binary it simply cannot run.
ARG YTDLP_VERSION=2026.08.19
ARG YTDLP_SHA256=58162f9bfdc27458ea47bfcb311cf47028f17d8154a8bf7d689861d46399230a
RUN set -eux; \
    base="https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VERSION}"; \
    curl -fsSL -o /tmp/yt-dlp_linux "${base}/yt-dlp_linux"; \
    echo "${YTDLP_SHA256}  /tmp/yt-dlp_linux" | sha256sum -c -; \
    [ "$(od -An -tx1 -j18 -N2 /tmp/yt-dlp_linux | tr -d ' ')" = "3e00" ] \
      || { echo "yt-dlp_linux is not an x86-64 ELF" >&2; exit 1; }; \
    chmod +x /tmp/yt-dlp_linux; \
    mv /tmp/yt-dlp_linux /usr/local/bin/yt-dlp; \
    if [ "$(uname -m)" = "x86_64" ]; then /usr/local/bin/yt-dlp --version; fi

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
