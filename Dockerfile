FROM ruby:4.0.6-slim AS build

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential git libsqlite3-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV RAILS_ENV=production

COPY Gemfile Gemfile.lock ./
RUN bundle config set without 'development test' && bundle install --jobs 4

COPY . .
RUN bin/rails assets:precompile

FROM ruby:4.0.6-slim

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    libsqlite3-0 curl ca-certificates unzip sqlite3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN groupadd --system --gid 1000 rails \
    && useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

# Pre-create opencode's XDG directories — including the exact path the compose
# file mounts a named volume on — owned by `rails`. Docker only seeds a fresh
# named volume from the image (preserving ownership) when that path already
# exists there; a missing mount point gets created as root, and then the `rails`
# user cannot write auth.json into it.
RUN mkdir -p /home/rails/.local/share/opencode /home/rails/.local/state /home/rails/.config \
    && chown -R rails:rails /home/rails/.local /home/rails/.config

COPY --chown=rails:rails --from=build /usr/local/bundle /usr/local/bundle
COPY --chown=rails:rails --from=build /app /app

ENV RAILS_ENV=production
ENV RAILS_LOG_TO_STDOUT=true
ENV RAILS_SERVE_STATIC_FILES=true

EXPOSE 3000

USER rails

# opencode CLI generates the AI summaries for clippings (see SummaryGenerator).
# --no-modify-path because this is a non-interactive image; PATH is set explicitly.
RUN curl -fsSL https://opencode.ai/install | bash -s -- --no-modify-path
ENV PATH="/home/rails/.opencode/bin:${PATH}"

ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
