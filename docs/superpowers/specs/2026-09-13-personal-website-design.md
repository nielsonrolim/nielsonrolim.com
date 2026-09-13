# Personal Website (nielsonrolim.com) — Design Spec

## Purpose

A simple personal website for Nielson Rolim to establish an online presence: About, Experience, Jampa Ruby community involvement, Projects, Contact, and a monthly tech newsletter signup. Visual style: retro computer terminal, monospace (FiraCode Nerd Font).

## Content Scope

Single scrolling page (per locale) with these sections, in order:

1. **Header / prompt bar** — simulated terminal prompt, language switcher (`PT-BR` / `EN-US`)
2. **About** — short personal intro, role (Senior Software Engineer), stack (Ruby, Rails, Hotwire, React, TailwindCSS)
3. **Experience** — chronological list pulled from LinkedIn: Light Labs Inc, Fluxx, Shift, RD Station, enjoei (title, company, dates, short blurb)
4. **Jampa Ruby** — active member of Jampa Ruby, the Ruby developer community in Paraíba, Brazil; short blurb + link to the community
5. **Projects** — project cards, initially:
   - **IBAPE-PB — Sistema de Distribuição de Trabalhos**: fair-distribution system for professional engineering assessments (perícias/avaliações) for IBAPE-PB, via lottery (sorteio) and direct nomination (indicação), covering the full work lifecycle (creation → publication → draw → acceptance → completion) with reporting and email notifications. Tags: Ruby on Rails, PostgreSQL, Redis.
6. **Newsletter** — email capture form for a monthly tech newsletter
7. **Contact** — email / LinkedIn / GitHub links

Content strings live in `config/locales/pt-BR.yml` and `config/locales/en-US.yml` — no hardcoded copy in views.

## Architecture

Single Ruby on Rails application serves everything — pages and newsletter signup share one app, one database, one deployable unit. No separate frontend build step, no JS framework.

- **Ruby**: 4.0 (latest)
- **Rails**: 8.1.3
- **Database**: SQLite (production), file-based, persisted via a named Docker volume
- **Server**: Puma (Rails default), no bundled Nginx — the existing Nginx reverse proxy on the VPS routes to the container's exposed port
- **Assets**: Rails asset pipeline (Propshaft/Sprockets default for Rails 8) for CSS; minimal or no custom JS (blinking cursor can be pure CSS)
- **Fonts**: FiraCode Nerd Font shipped as a static asset (`app/assets/fonts` or `public/fonts`), loaded via `@font-face` — no external font CDN

## Routing & i18n

- `/` redirects to the default locale, `pt-BR`
- `/pt-BR` and `/en-US` render the same single-page template, `PagesController#home`, with `I18n.locale` set from the URL segment via a `before_action` and Rails' standard `scope "(:locale)"` routing pattern
- Locale files: `config/locales/pt-BR.yml`, `config/locales/en-US.yml` (default Rails locale strings can stay in `en.yml`/`pt-BR.yml` as needed by Rails conventions, but content copy is namespaced under a `pages.home` key)
- A locale switcher in the header links between `/pt-BR` and `/en-US`, preserving the anchor/section scroll position is not required (single page, no per-section routes)

## Data Model

### `Subscriber`

| Column        | Type      | Notes                                  |
|---------------|-----------|-----------------------------------------|
| `email`       | string    | required, validated format, unique (case-insensitive) |
| `created_at`  | datetime  | Rails default                          |

No `updated_at`-dependent behavior needed beyond Rails defaults. No admin UI — subscribers are inspected via `rails console` or `sqlite3` directly on the VPS. No email sending (no ActionMailer pipeline) — capture only, for now.

### Honeypot spam protection

The subscribe form includes an extra field (e.g. `nickname`) hidden from sighted users via CSS (not `display:none`/`type=hidden`, to avoid trivial bot detection — use off-screen positioning). It is **not** a database column; it's a virtual attribute on the form object. `SubscribersController#create`:

- If the honeypot field is non-blank, silently respond as if signup succeeded (redirect/flash success) without creating a `Subscriber` record.
- Otherwise, proceed with normal create + validation.

## Controllers

- `PagesController#home` — renders the single-page layout for the current locale; also serves as the mount point for the newsletter form (rendered inline as a partial)
- `SubscribersController#create` — handles the newsletter POST; honeypot check, then standard create; redirects back to the page with a flash message (success or validation error, e.g. duplicate email)

## Visual Design

- Dark terminal background, terminal-style foreground color (e.g. phosphor green or an adapted Nord/Dracula terminal palette — finalized during implementation)
- FiraCode Nerd Font throughout, monospace
- Each content section is framed as terminal "output" following a simulated prompt line, e.g. `nielson@nielsonrolim:~$ cat about.txt`
- A blinking cursor (pure CSS animation) at the end of the visible content
- Responsive: readable and usable on mobile (font-size and spacing adjust; no horizontal scroll)

## Deployment

- Multi-stage `Dockerfile` based on the official `ruby:4.0` image — build stage installs gems/precompiles assets, final stage is a slim runtime image
- `docker-compose.yml` defines a single `web` service (Rails + Puma) with:
  - A named volume persisting `db/production.sqlite3` outside the container
  - Environment variables from a `.env` file (e.g. `RAILS_MASTER_KEY`)
  - An exposed internal port only — no bundled Nginx/reverse proxy; the VPS's existing Nginx handles TLS and routing to this container

## Testing

Minitest (Rails default, no RSpec):

- **Model tests** (`SubscriberTest`): email required, format validated, uniqueness enforced (case-insensitive)
- **Request tests** (`SubscribersControllerTest` or request spec):
  - Valid email submission creates a `Subscriber` and responds successfully
  - Honeypot field filled in → no `Subscriber` created, response still looks like success
  - Duplicate email submission does not create a second record and surfaces a friendly error
- **Request tests** (`PagesControllerTest`): `GET /pt-BR` and `GET /en-US` both respond `200`

## Out of Scope (for this iteration)

- Actual newsletter sending (ActionMailer/ESP integration) — capture only
- Admin UI for managing subscribers
- Double opt-in / email confirmation
- CMS or database-backed content editing — all copy lives in locale YAML files
- Bundled Nginx/TLS termination inside the compose stack (handled by the existing VPS proxy)
