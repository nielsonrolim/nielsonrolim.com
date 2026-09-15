# AGENTS.md

Personal site + private RSS→newsletter app. **Ruby 4.0.6 / Rails 8.1**, SQLite, no Node/npm (Tailwind and Hotwire run without a JS build step).

`README.md` is the detailed source of truth — read it before large changes. `docs/superpowers/specs/2026-09-13-personal-website-design.md` holds the original design intent.

## Commands

```sh
mise install && bundle install
cp .env.example .env        # required: /admin 403s without READER_USERNAME/PASSWORD
bin/rails db:prepare
bin/dev                     # Puma + Tailwind watch
bin/jobs start              # Solid Queue worker + recurring scheduler (needed for feeds/summaries/sends)
bin/rails test              # full suite; single file: bin/rails test test/models/clipping_test.rb
bin/rails test test/models/clipping_test.rb -n /pattern/
bin/rubocop                 # rails-omakase style
bin/ci                      # full local CI: setup, style, bundler-audit, brakeman, tests, seeds
```

## Gotchas

- **`.env` is loaded only in development** by `dotenv-rails`; `ENV` is read at boot, so restart after editing. The test suite deliberately does *not* load it — tests set credentials via `with_reader_credentials` / `reader_headers` in `test/test_helper.rb`.
- **Tests must stay offline and must never spawn `opencode`.** Production code exposes injectable seams (transport for `FeedFetcher`, CLI for `SummaryGenerator`, collaborators for jobs); fakes live in `test/support/fakes.rb`. Minitest 6 dropped `minitest/mock`/`Object#stub`, so add a seam + fake instead of stubbing.
- **All `/admin` routes require HTTP Basic Auth and fail closed (403) when `READER_USERNAME`/`READER_PASSWORD` are unset.** The Mission Control dashboard is mounted under it and inherits `Admin::BaseController`; never make it public.
- **All user-facing copy lives in `config/locales/`** (`pt-BR` default, `en-US`). No hardcoded view strings. Admin is not locale-scoped and always renders in the default locale. Locale comes from the URL segment (`/` redirects to `/pt-BR`).
- **Reader controllers use the `Reader::` namespace/helpers even though URLs are nested under `/admin`** (`/admin/reader/...`). Don't assume path == namespace.
- **Two SQLite databases**: app + a separate `queue` DB (`config/database.yml`, schema in `db/queue_schema.rb`). Solid Queue models are wired to it in `config/application.rb`.
- **Versioned data changes go in `db/data/`** (data_migrate), separate from schema migrations: `bin/rails data:migrate`. `db/seeds.rb` is idempotent starter data only.
- **Schema change**: edit `db/migrate/`, run `bin/rails db:prepare`. If Solid Queue changes, use its generator rather than editing `db/queue_schema.rb` by hand.
- Feed/article HTML is untrusted: sanitize on ingest, escape on render, and keep `opencode` runs on `config/opencode/summarizer.json` (all tools denied). Invoke it via argument arrays, never a shell string.
- `.env` is consumed by dotenv and docker compose, not a shell; values with spaces/`<>` break `source .env`.
