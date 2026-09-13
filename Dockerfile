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
    libsqlite3-0 curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN groupadd --system --gid 1000 rails \
    && useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

COPY --chown=rails:rails --from=build /usr/local/bundle /usr/local/bundle
COPY --chown=rails:rails --from=build /app /app

ENV RAILS_ENV=production
ENV RAILS_LOG_TO_STDOUT=true
ENV RAILS_SERVE_STATIC_FILES=true

EXPOSE 3000

USER rails

ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
