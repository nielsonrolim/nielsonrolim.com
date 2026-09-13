# nielsonrolim.com

Personal website of **Nielson Rolim** — a single-page, terminal-styled site with a
short bio, work history, education, open-source projects, community involvement,
and a newsletter signup.

## Features

- Single scrolling page: About, Experience (recent roles plus an expandable full
  history), Education, Jampa Ruby, Projects, Contact, and Newsletter.
- Bilingual: **pt-BR** (default) and **en-US**, with content in locale files only.
- Light/dark theme that follows the operating system by default and remembers the
  visitor's choice (`localStorage`).
- Small newsletter capture with honeypot spam protection.
- No JavaScript framework; a tiny inline script handles the theme.
- Tailwind CSS v4 through `tailwindcss-rails` — no Node.js required.

## Tech stack

| Layer      | Choice                                              |
| ---------- | --------------------------------------------------- |
| Language   | Ruby 4.0.6                                          |
| Framework  | Rails 8.1.3                                         |
| Database   | SQLite (file-based)                                 |
| Server     | Puma                                                |
| Assets     | Propshaft + Tailwind CSS v4 (`tailwindcss-rails`)   |
| Type       | FiraCode Nerd Font                                  |
| Tests/Lint | Minitest, RuboCop (rails-omakase), Brakeman         |

## Requirements

- Ruby 4.0.6 (see `.ruby-version` / `mise.toml`)
- SQLite 3
- Docker + Docker Compose (only for deployment)

## Getting started

```sh
mise install          # or install Ruby 4.0.6 another way
bundle install
bin/rails db:prepare
bin/dev               # starts Puma; Tailwind rebuilds automatically in dev
```

Open http://localhost:3000 — `/` redirects to `/pt-BR`.

To work on styles in a separate process instead:

```sh
bin/rails tailwindcss:watch
```

## Tests and lint

```sh
bin/rails test
bin/rubocop
```

A full local CI run (setup, tests, style, security scans) is available via
`bin/ci`.

## Configuration

Copy `.env.example` to `.env` and fill it in. In production, the following
environment variables are read:

| Variable           | Purpose                                                                 |
| ------------------ | ----------------------------------------------------------------------- |
| `RAILS_MASTER_KEY` | Decrypts `config/credentials.yml.enc` (required).                       |
| `RAILS_HOSTS`      | Comma-separated allowed hosts (default `nielsonrolim.com,www.nielsonrolim.com`). |
| `RAILS_LOG_LEVEL`  | Optional; defaults to `info`.                                           |

## Internationalization

All copy lives in `config/locales/pt-BR.yml` and `config/locales/en-US.yml`.
There are no hardcoded strings in the views. The locale is taken from the URL
segment; `/` redirects to `/pt-BR`.

## Deployment (Docker Compose)

The app ships as a single container (Rails + Puma) with a persistent SQLite
database.

```sh
cp .env.example .env   # set RAILS_MASTER_KEY (and RAILS_HOSTS if needed)
docker compose up -d --build
```

- The container listens on `127.0.0.1:3000`; put a TLS-terminating reverse proxy
  (e.g. Nginx) in front of it and forward `Host` and `X-Forwarded-Proto`.
- SQLite is persisted in the `sqlite_data` volume mounted at `/app/storage`.
- `bin/docker-entrypoint` runs `db:prepare` before booting the server.
- A `healthcheck` polls `/up`.
- The image runs as a non-root user and does not contain any secrets.

## Project structure

```
app/
  assets/tailwind/application.css   Tailwind entrypoint and theme tokens
  assets/images/                    Photo and Jampa Ruby logo
  assets/fonts/                     FiraCode Nerd Font
  controllers/                      PagesController, SubscribersController
  models/subscriber.rb              Newsletter subscriber
  views/pages/home.html.erb         The single page
  views/pages/_job.html.erb         One experience entry
config/
  locales/                          All page copy (pt-BR, en-US)
  environments/production.rb        Hosts, SSL, logging
Dockerfile                          Multi-stage production image
docker-compose.yml                  Web service, volume, healthcheck
```
