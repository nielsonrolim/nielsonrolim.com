# nielsonrolim.com

Personal website of **Nielson Rolim** — a single-page, terminal-styled site with a
short bio, work history, education, open-source projects, community involvement,
and a newsletter signup — plus a private **RSS reader** that turns hand-picked
articles into a weekly clipping newsletter with AI-written summaries.

## Features

- Single scrolling page: About, Experience (recent roles plus an expandable full
  history), Education, Jampa Ruby, Projects, Contact, and Newsletter.
- Bilingual: **pt-BR** (default) and **en-US**, with content in locale files only.
- Light/dark theme that follows the operating system by default and remembers the
  visitor's choice (`localStorage`).
- Small newsletter capture with honeypot spam protection and one-click unsubscribe.
- **Private admin area** (`/admin`) behind HTTP Basic Auth. Underneath it:
  - **RSS reader** (`/admin/reader`): subscribe to feeds, browse entries by feed
    and time window, and clip the ones worth sharing.
  - **Job dashboard** (`/admin/jobs`): Mission Control for Solid Queue — inspect
    queues, retry or discard failed jobs, watch workers and recurring tasks.
- **Weekly clipping newsletter**: every clipped article is summarized by a free
  LLM through the `opencode` CLI, then all clippings of the week go out as one
  HTML + plain-text email to every subscriber in their own language, Mondays at
  09:00.
- **Hotwire** (Turbo + Stimulus) through `importmap-rails`: clipping an entry
  updates just that entry and shows a toast, with no full-page reload. Still no
  Node.js build step.
- Tailwind CSS v4 through `tailwindcss-rails` — no Node.js required.

## Tech stack

| Layer      | Choice                                              |
| ---------- | --------------------------------------------------- |
| Language   | Ruby 4.0.6                                          |
| Framework  | Rails 8.1.3.1                                       |
| Database   | SQLite (file-based), separate DB for the queue       |
| Server     | Puma                                                |
| Jobs       | Solid Queue (workers + recurring schedule)           |
| Feeds      | `feedjira` (parsing) + `Net::HTTP` (transport)       |
| Email      | Action Mailer over SMTP                              |
| Summaries  | `opencode` CLI with a free model                     |
| Front-end  | Hotwire (Turbo + Stimulus) via `importmap-rails`     |
| Assets     | Propshaft + Tailwind CSS v4 (`tailwindcss-rails`)   |
| Type       | FiraCode Nerd Font                                  |
| Tests/Lint | Minitest, RuboCop (rails-omakase), Brakeman         |

## Requirements

- Ruby 4.0.6 (see `.ruby-version` / `mise.toml`)
- SQLite 3
- `opencode` CLI, authenticated (`opencode auth login`) — only needed to generate
  summaries. Installed automatically inside the Docker image.
- Docker + Docker Compose (only for deployment)

## Getting started

```sh
mise install          # or install Ruby 4.0.6 another way
bundle install
cp .env.example .env  # fill in READER_USERNAME / READER_PASSWORD, or /admin 403s
bin/rails db:prepare
bin/rails db:seed     # optional: the starter feeds
bin/dev               # starts Puma; Tailwind rebuilds automatically in dev
```

Open http://localhost:3000 — `/` redirects to `/pt-BR`. The admin area lives at
http://localhost:3000/admin (the reader at `/admin/reader`) and asks for the
`READER_*` credentials from `.env` (loaded by `dotenv-rails`; restart after
editing it).

Feed polling, summary generation and the weekly send all run through Solid Queue,
so start a worker in a second terminal:

```sh
bin/jobs start        # workers + the recurring scheduler
```

Without a worker, clippings stay in `pending` and feeds are never refreshed.

To send an issue by hand while developing, use the "send now" button on
`/admin/reader/newsletters` — the email opens in a browser tab via `letter_opener`.

To work on styles in a separate process instead:

```sh
bin/rails tailwindcss:watch
```

## Admin area, RSS reader and weekly clipping

`/admin` is the authenticated area (HTTP Basic Auth). Set `READER_USERNAME` and
`READER_PASSWORD`; **if either is missing the whole area returns 403** rather
than becoming public. The reader and the job dashboard live underneath it.

| Path                   | What it does                                                    |
| ---------------------- | --------------------------------------------------------------- |
| `/admin`               | Dashboard: totals and links into the sections                    |
| `/admin/reader`        | Entry stream: filter by feed, category and window; paginate; clip |
| `/admin/reader/feeds`  | Add/remove feeds, refresh one or all, see per-feed poll errors   |
| `/admin/reader/feeds/:id/edit` | Edit a feed: display title and categories                |
| `/admin/reader/clippings` | The queue for the next issue, with each summary's status      |
| `/admin/reader/newsletters` | Issue archive, live stats, and a manual "send now"          |
| `/admin/subscribers`   | Newsletter list: search, add, remove (single or bulk), export CSV, copy an unsubscribe link, resend an issue |
| `/admin/jobs`          | Mission Control dashboard: queues, pending/failed/scheduled jobs, workers, recurring tasks; retry or discard |

The layout has two navigation levels: the admin sections (`[painel] [leitor]
[inscritos] [jobs]`) and, inside the reader, its own sub-navigation (`[entradas]
[recortes] [fontes] [arquivo]`).

### Subscribers and languages

Each subscriber carries the `language` they signed up in, taken from the URL they
were reading (`pt-BR` or `en-US`) rather than from the form, so it cannot be
spoofed. It is editable on `/admin/subscribers`, where the list can be searched by
email, paginated 30 at a time, extended by hand, exported to CSV (the export
follows the current search), and pruned one by one or in bulk.

Subscribers can also change it themselves: every email carries a **"gerenciar
inscrição"** link to `/newsletter/preferences?token=…`, where they pick the
language and it applies from the next issue. The token is the same capability the
unsubscribe link uses, so no login is involved, and the page — like the
unsubscribe page — is rendered in the subscriber's own language. Changing an
address is deliberately not offered: that is an identity change and would need
confirmation; the page only touches the language. `List-Unsubscribe` keeps
pointing at the unsubscribe endpoint, since that is the one-click contract mail
clients rely on.

Removal is a **real delete**, not a soft unsubscribe: the subscriber asked to be
forgotten, so nothing about them is kept (LGPD). The older approach — the public
unsubscribe link — works the same way, deleting the row.

Because subscribers read different languages, an issue is rendered **once per
language it has to go out in** and stored on `newsletter_bodies` (one per locale,
with its own subject). `SendNewsletterJob` composes a body per subscribed
language and hands each subscriber the matching one; the mailer falls back to the
app's default language when the issue lacks theirs, and localises the transport
footer too. The archive at `/admin/reader/newsletters` shows the language tabs,
using an `issue_locale` param so it does not collide with the admin's own locale.

### Clippings, their language and translations

A clipping is a story, and every language it was published in is a **variant**
(`clipping_variants`): its own `title` and `summary`, keyed by `locale`, plus an
optional `url`. A story can therefore point each reader at the edition in their
own language — useful for sites like AkitaOnRails that publish the same article
at `/…` and `/en/…`. The clipping itself keeps only what identifies the story
(`entry_id`, `source_name`, `source_text`) and the summary status; the languages
live entirely on the variants, so there is no single "article language" to keep
in sync.

The **URL belongs to a published edition, not to a language**: most articles exist
in only one language, so only the variant of the language it was published in gets
a URL. The other language's variant is a translation with no page of its own and
stays without a URL — `url_for(locale)` then falls back to the URL of the edition
that exists, so an en-US subscriber of a pt-BR-only article reads the translated
title/summary and still lands on the pt-BR page. A story can have an edition in
only pt-BR, only en-US, or both; `languages` lists the ones actually published
(with a URL), which is what the queue badge shows — a translation without a page
of its own does not make the story be "in" that language.

While the article's language has not been detected yet, the source variant has no
`locale` (the partial unique index allows only one of those). The generation is a
single model call that reports the language, so it moves that source variant to the
detected language and creates the variant for the other one — **without writing any
URL**. `variant_for(locale)` is the lookup; `title_for` / `summary_for` /
`url_for(locale)` hand the right edition to each reader, falling back to the primary
edition when a language has no variant. The detection is not editable: it is what
places the model's summary, and the per-language content is what the reader edits.

A variant is either `generated` by the model or `manual` when the reader wrote or
corrected it. A manual edition is **never overwritten** by a later summary run, and
no generation ever touches a URL, so typing the real translated URL and title
(instead of the machine translation) is safe.

`/admin/reader/clippings` shows **both languages side by side**, labelled
`publicado` for an edition with a URL and `tradução` for one without, plus a badge
with the languages the story is published in (or "idioma não detectado" while it
has not run). Re-running the summary from there fills the other edition for older
clippings too. In the issue each clipping carries the languages it is published
in, and the title, summary and link go out in the subscriber's language (and to
that edition's URL, with the same fallback).

### Adding and editing a clipping by hand

A clipping does not have to come from a feed: the form at the top of the page
takes a URL and an optional title. `ArticleFetcher` fetches the page through the
same `HttpTransport` feeds use, and pulls out a title (`og:title` → `twitter:title`
→ `<title>` → `<h1>`) and the body text (dropping scripts, chrome and asides),
which becomes `source_text` — the text the summary is generated from.

When the fetch fails (blocked bot, paywall, JavaScript-only page) the clipping is
**still created**, marked `failed` with the reason and with the host as its title,
and the page sends you to `/admin/reader/clippings/:id/edit`. There you can paste
the article text and press **"gerar sumário e tradução"**, which runs the summary
and the translation on demand. The edit page exposes **one title, summary and
optional URL per language**, plus the source text — so a story published in more
than one language can be pointed at each edition by hand (fill the URL only for
the languages that have a published page), a bad translation can be corrected, and
the same button regenerates the machine-made editions. Leaving a language blank
drops its edition.

A clipping marked `failed` is **left out of the next issue** (see
`Clipping.shippable`); it stays in the queue until it is fixed or removed, which
is why the page counts what will actually go out and how many are stuck.

### Feeds, categories and titles

- **Categories are many-to-many.** `categories` + `feed_categories` (replacing
  the old single `feeds.category` string). A feed can carry several, a category
  groups many feeds, and matching names is case-insensitive, so typing `ruby`
  finds an existing `Ruby` instead of creating a near-duplicate.
- **`custom_title` is a display override** for the feed's own title. The feed
  title keeps being refreshed from the feed on every poll; `display_title`
  returns the override when set and the feed's title otherwise. Editing a title
  therefore never fights the fetcher, and clearing the field restores the
  original. Ordering follows the display title.
- **The URL is not editable.** Entries are matched by it, so changing it would
  orphan the history.
- **The entry filter is grouped**: feeds live behind a disclosure grouped by
  category (a feed with several categories shows under each), plus a category
  row. Every filter link carries the other active filters, so combining feed,
  category and window never silently drops one.

### Inspecting jobs

`/admin/jobs` is the [Mission Control](https://github.com/rails/mission_control-jobs)
dashboard (Solid Queue's official UI). It mounts inside the engine and its
controllers inherit `Admin::BaseController` — the gem's own HTTP Basic Auth is
switched off in favour of the one credential set — so **the dashboard exposes job
arguments, which include clipping prompts and subscriber addresses.** It is
therefore never public: without credentials it answers 401, and if `READER_*` is
unset it 403s like the rest of the admin area.

There you can browse queues and pending/failed/scheduled/finished jobs, inspect
arguments and backtraces, and retry or discard failures. Workers and recurring
tasks appear under the application-scoped routes
(`/admin/jobs/applications/default/...`).

Without the dashboard, from a shell:

```sh
bin/jobs check                        # validate the queue configuration
docker compose logs -f jobs           # what the worker is doing

bin/rails runner 'puts SolidQueue::Job.count'
bin/rails runner 'SolidQueue::Process.find_each { |p| puts "#{p.kind} #{p.hostname} #{p.last_heartbeat_at}" }'
bin/rails runner 'SolidQueue::FailedExecution.find_each { |f| puts "#{f.job.class_name}: #{f.error&.dig("message")}" }'
```

Note that a worker started with `bin/jobs start` registers itself in the database
of the environment it runs in, so `SolidQueue::Process` in development only lists
local workers — the Docker `jobs` container writes to the production queue.

### How a clipping flows

1. **Clip** an entry → a `Clipping` is created (unique per entry while unsent) and
   `GenerateSummaryJob` is enqueued.
2. **Summarize** — the job first makes sure it has the article text: a feed
   clipping arrives with only the RSS excerpt, so its page is fetched once and
   the text kept (a failed fetch falls back to the excerpt). It then shells out
   to
   `opencode run <prompt> --format json --model opencode/ling-3.0-flash-fin-free --standalone`
   and asks for a single JSON object: the article's language, its title
   translated into the other language, and a complete ~100–150 word summary in
   *both* languages. The detected language moves the source variant to that
   language; the title and the summary in the article's own language stay on it,
   and the other language's title and summary land on the generated variant
   beside it. A manual variant is left alone. Up to 3 attempts; a clipping whose
   summary keeps failing is marked `failed` and still ships, with its source
   title and no summary.
3. **Send** — every Monday at 09:00 `SendNewsletterJob` composes an issue from all
   unsent clippings, storing one rendered body (HTML *and* plain text, with its
   own subject) per subscribed language on `newsletter_bodies` — so the archive is
   exactly what went out — emails every subscriber the body for their language,
   and stamps the clippings with that issue.

If some summaries are still in flight the job postpones itself by 10 minutes, up
to 6 times, so a slow model delays the issue instead of truncating it. An empty
queue or an empty subscriber list means no issue is created at all.

### Security notes

- Feed content is **untrusted**. It is HTML-sanitized on ingest, escaped on
  render, and the `opencode` run is executed with
  `config/opencode/summarizer.json`, which blocks *every* tool (no shell, no file
  access, no web fetch) and skips the project's own opencode config. On opencode
  v2 the run also passes `--standalone`, so a private server loads that config
  instead of the shared background server, which would ignore it. A prompt
  injection hidden in an article therefore cannot reach the host. On opencode v2
  the free tier rejects configs that `deny` `read`/`shell`, so the locked config
  marks those two as `ask` instead: a non-interactive run declines every ask, so
  no tool ever runs and the free model is accepted.
- `opencode` is invoked through `Open3.popen3` with an argument array (never a
  shell string), in its own process group, and killed on timeout.
- Outbound fetches are limited to `http`/`https`, follow at most 5 redirects, and
  are capped at 5 MB.
- Unsubscribe uses a per-subscriber random token (`List-Unsubscribe` +
  `List-Unsubscribe-Post` for RFC 8058 one-click), never the bare email address.

### Email delivery

Set `SMTP_ADDRESS` (plus port/domain/credentials) to send for real. Delivery is
chosen per environment by `config/initializers/action_mailer.rb`:

| Environment | Default             | Notes                                                        |
| ----------- | ------------------- | ------------------------------------------------------------ |
| development | `letter_opener`     | Renders into `tmp/letter_opener` and opens a browser tab. Never sends. |
| test        | `test`              | Captured by `ActionMailer::TestHelper`.                       |
| production  | `smtp`              | Falls back to `tmp/mails` + a boot warning if `SMTP_ADDRESS` is blank, so a misconfigured box never silently loses an issue. |

`MAIL_DELIVERY=smtp|file|letter_opener` overrides the choice; an override that
cannot apply (e.g. `letter_opener` in production, or `smtp` with no
`SMTP_ADDRESS`) logs a warning and falls back.

Because `letter_opener` opens one tab per delivery, sending an issue to N
subscribers from development opens N tabs. Use `MAIL_DELIVERY=file` to review
them in `tmp/mails` instead.

`.env` is loaded in development by `dotenv-rails` (Rails does not read it on its
own). Restart `bin/dev` after editing it — `ENV` is read at boot.

## Tests and lint

```sh
bin/rails test
bin/rubocop
```

A full local CI run (setup, tests, style, security scans) is available via
`bin/ci`.

Tests never touch the network or spawn `opencode`: `FeedFetcher` takes an
injectable transport, `SummaryGenerator` an injectable CLI, and both jobs an
injectable collaborator. See `test/support/fakes.rb`.

## Configuration

Copy `.env.example` to `.env` and fill it in. In production, the following
environment variables are read:

| Variable                  | Purpose                                                                 |
| ------------------------- | ----------------------------------------------------------------------- |
| `RAILS_MASTER_KEY`        | Decrypts `config/credentials.yml.enc` (required).                       |
| `RAILS_HOSTS`             | Comma-separated allowed hosts (default `nielsonrolim.com,www.nielsonrolim.com`). |
| `WEB_PORT`                | Host port published by Docker Compose (default `3000`).                 |
| `RAILS_LOG_LEVEL`         | Optional; defaults to `info`.                                           |
| `READER_USERNAME`         | HTTP Basic user for `/admin`. Required, or the area 403s.               |
| `READER_PASSWORD`         | HTTP Basic password for `/admin`. Required.                             |
| `APP_HOST`, `APP_PROTOCOL`| Base URL used to build links inside emails.                             |
| `NEWSLETTER_FROM`         | `From:` header of the weekly clipping.                                  |
| `SMTP_ADDRESS`            | SMTP relay. Blank ⇒ mail is not delivered for real.                     |
| `MAIL_DELIVERY`           | `smtp` \| `file` \| `letter_opener`. Overrides the per-environment default. |
| `SMTP_PORT`, `SMTP_DOMAIN`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_AUTHENTICATION` | SMTP details.                                     |
| `OPENCODE_SUMMARY_MODEL`  | Model used for summaries (default `opencode/ling-3.0-flash-fin-free`).   |
| `OPENCODE_API_KEY`        | Container only: written to `auth.json` on boot by the entrypoint.       |
| `FEED_REFRESH_MINUTES`    | Minimum minutes between polls of the same feed (default `30`).          |
| `APP_TIME_ZONE`, `TZ`     | Time zone for the recurring schedule (default `Brasilia`).              |
| `JOB_CONCURRENCY`         | Solid Queue worker processes per container (default `1`).               |

## Internationalization

All copy lives in `config/locales/pt-BR.yml` and `config/locales/en-US.yml`.
There are no hardcoded strings in the views. The locale is taken from the URL
segment; `/` redirects to `/pt-BR`. The admin area itself is not locale-scoped and
always renders in the default locale. `rails-i18n` supplies the pt-BR
ActiveRecord error messages and date formats.

## Data migrations

Versioned data changes live in `db/data/` and are tracked in their own
`data_migrations` table, separately from schema migrations, by
[data_migrate](https://github.com/ilyakatz/data-migrate).

```sh
bin/rails data:migrate          # apply pending data migrations
bin/rails data:migrate:status   # what is pending / already applied
bin/rails data:rollback         # step back (only for reversible migrations)
bin/rails g data_migration my_change
```

A data migration runs against **the database of the environment you run it in** —
it cannot read another environment's data. So bringing data across (say, feeds
authored in development) means snapshotting it into the migration and running
`data:migrate` wherever it should land:

```ruby
# db/data/20260914122758_import_development_feeds.rb
def up
  FEEDS.each do |title, url, category|
    Feed.find_or_create_by!(url: url) do |feed|
      feed.title = title
      feed.category = category
    end
  end
end
```

That one is idempotent (matched by URL, never overwrites an existing row), so it
is a no-op in development and creates only what is missing elsewhere. Unlike
`db/seeds.rb` — idempotent starter data that keeps evolving — a data migration is
a point-in-time snapshot and must keep meaning the same thing forever, which is
why it embeds its data instead of reading the seed file.

`bin/docker-entrypoint` runs `bin/rails data:migrate` right after `db:prepare` on
the `web` container, so deployments apply them automatically. It is deliberately
non-fatal: a failing data migration logs loudly and is retried on the next boot
rather than taking the site down. To run it by hand:

```sh
docker compose exec web bin/rails data:migrate
```

## Deployment (Docker Compose)

Two containers share one SQLite volume: `web` (Rails + Puma) and `jobs`
(Solid Queue worker + scheduler).

```sh
cp .env.example .env   # set RAILS_MASTER_KEY, READER_*, SMTP_*, OPENCODE_API_KEY
docker compose up -d --build
```

- `web` is published on `127.0.0.1:${WEB_PORT}` (container port `3000`).
  `WEB_PORT` defaults to `3000`; set it in `.env` if the host port is taken. Put
  a TLS-terminating reverse proxy (e.g. Nginx) in front and forward `Host` and
  `X-Forwarded-Proto`.
- Both the app database and the queue database live in the `sqlite_data` volume
  mounted at `/app/storage`.
- `jobs` runs `bin/jobs start` and waits for `web` to pass its healthcheck, so it
  never boots against an unprepared database (`web`'s entrypoint runs
  `db:prepare`).
- The image installs the **v2** `opencode` CLI as the non-root `rails` user (via
  the `/v2/install` endpoint — the default `/install` serves v1, which lacks
  `--standalone`). Its data
  directory is the `opencode_data` volume, and `bin/docker-entrypoint` writes
  `auth.json` from `OPENCODE_API_KEY` on boot. Prefer that over baking the key in.
  Without `OPENCODE_API_KEY`, run `docker compose exec web opencode auth login`
  once — the volume keeps it.
- A `healthcheck` polls `/up`.
- The image runs as a non-root user and contains no secrets.

### Reaching the container from your machine

`config.hosts` is set from `RAILS_HOSTS` (default `nielsonrolim.com,www.nielsonrolim.com`)
to block DNS-rebinding attacks, so **`http://localhost:3001` returns 403 for every
path except `/up`** — including the public site. That is the host filter, not the
admin area's auth. Send the expected Host header instead:

```sh
curl -H "Host: nielsonrolim.com" http://127.0.0.1:3001/pt-BR      # 200
curl -H "Host: nielsonrolim.com" -u "$READER_USERNAME:$READER_PASSWORD" \
     http://127.0.0.1:3001/admin                                   # 200
```

Or add `localhost,127.0.0.1` to `RAILS_HOSTS` — convenient, but it does weaken
the rebinding protection, so prefer the header (or a real reverse proxy).

Note that `.env` is parsed by dotenv and docker compose, not by a shell: values
with `<`, `>` or spaces (e.g. `NEWSLETTER_FROM`) are fine there but will break
`source .env`. Read single keys with `grep ... | cut -d= -f2-`.

### If `auth.json` cannot be written

The `opencode_data` volume is mounted exactly on `/home/rails/.local/share/opencode`.
Docker only seeds a fresh named volume from the image — ownership included — when
that path already exists there, which is why the Dockerfile pre-creates it as
`rails`. A volume created by an older image is root-owned, and the entrypoint logs:

```
[docker-entrypoint] WARNING: cannot write /home/rails/.local/share/opencode/auth.json
```

It warns and keeps booting (the site works without summaries), so fix it with:

```sh
docker compose down
docker volume rm <project>_opencode_data   # keeps sqlite_data intact
docker compose up --build
```

## Project structure

```
app/
  assets/tailwind/application.css   Tailwind entrypoint and theme tokens
  assets/images/                    Photo and Jampa Ruby logo
  assets/fonts/                     FiraCode Nerd Font
  controllers/                      PagesController, SubscribersController,
                                    UnsubscribesController,
                                    Admin::BaseController (auth) + Admin::Dashboard,
                                    Admin::Subscribers, Reader::* (nested under /admin)
  jobs/                             RefreshFeedsJob, GenerateSummaryJob,
                                    SendNewsletterJob
  mailers/newsletter_mailer.rb      One issue → one subscriber
  models/                           Subscriber, Feed, Category, FeedCategory,
                                    Entry, Clipping, ClippingVariant, Newsletter,
                                    NewsletterBody
  services/
    feed_fetcher.rb                 HTTP transport + Feedjira parsing + ingest
    opencode_cli.rb                 Locked-down `opencode` process wrapper
    summary_generator.rb            Prompt building and response extraction
    newsletter_composer.rb          Issue HTML/text rendering
  views/layouts/admin.html.erb      Admin chrome + two-level navigation
  views/admin/dashboard/            Admin landing page
  views/reader/                     Reader screens (sub-navigation partial too)
  views/newsletters/email_body.*    Archived issue body (html + text)
  views/newsletter_mailer/issue.*   Per-recipient wrapper + unsubscribe footer
config/
  locales/                          All page copy (pt-BR, en-US)
  environments/production.rb        Hosts, SSL, logging
  queue.yml, recurring.yml          Solid Queue workers and weekly schedule
  opencode/summarizer.json          Denies every opencode tool (v2 `permissions` format)
  initializers/action_mailer.rb     SMTP / file / test delivery selection
db/
  migrate/                          App schema
  queue_schema.rb                   Solid Queue schema (separate database)
  seeds.rb                          The starter feeds
Dockerfile                          Multi-stage image with the opencode CLI
docker-compose.yml                  web + jobs services, shared volumes
```
