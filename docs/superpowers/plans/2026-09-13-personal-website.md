# Personal Website (nielsonrolim.com) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single-page, terminal-styled personal website for Nielson Rolim (About, Experience, Jampa Ruby, Projects, Newsletter, Contact) in pt-BR and en-US, backed by a Rails 8.1.3 app with a SQLite-backed newsletter signup, deployable via Docker Compose behind an existing VPS Nginx proxy.

**Architecture:** One Rails app serves everything — ERB views render a single scrolling page styled as a terminal session, content sourced from locale YAML files (pt-BR default, en-US alternate) via URL-prefixed routes. A `Subscriber` model (SQLite) captures newsletter emails through a honeypot-protected form. No JS framework, no build step, no bundled web server beyond Puma.

**Tech Stack:** Ruby 4.0.6, Rails 8.1.3, SQLite, Minitest, Propshaft (asset pipeline), plain CSS, Docker + Docker Compose.

**Spec:** `docs/superpowers/specs/2026-09-13-personal-website-design.md`

## Global Constraints

- Ruby version: 4.0.6, pinned via project-local `mise.toml` (already created in this directory).
- Rails version: 8.1.3 exactly (`gem "rails", "8.1.3"` in the Gemfile).
- Database: SQLite in all environments (development, test, production).
- No JS framework and no frontend build step — plain CSS only; skip Hotwire/importmap at generation time.
- No external font CDN — FiraCode Nerd Font files are copied into the app as static assets.
- No external image CDN — the Jampa Ruby logo (SVG) is copied into the app as a static asset.
- Locales: `pt-BR` (default) and `en-US` only. All copy lives in `config/locales/*.yml` — no hardcoded strings in views.
- Newsletter is capture-only: no ActionMailer, no admin UI. Subscribers are inspected via `bin/rails console` / `sqlite3` on the VPS.
- Testing: Minitest only (Rails default) — no RSpec, no system tests.
- Docker Compose runs a single `web` service (Rails/Puma) — no bundled Nginx; the VPS's existing Nginx reverse-proxies to the container.

---

### Task 1: Application skeleton

**Files:**
- Create: entire Rails app skeleton under the repo root (`rails new .`)
- Verify: `mise.toml` (already present, pins `ruby = "4.0.6"`)

**Interfaces:**
- Produces: a bootable Rails 8.1.3 app at the repo root, with `bin/rails`, `Gemfile` (`rails` at `8.1.3`), SQLite configured for all environments, and a working Minitest harness (`bin/rails test`).

- [ ] **Step 1: Confirm the Ruby toolchain**

```bash
cd /home/nielsonrolim/Projects/bitmine/nielsonrolim.com
cat mise.toml   # expect: ruby = "4.0.6"
ruby -v         # expect: ruby 4.0.6 ...
gem list -i "^rails$" -v 8.1.3   # expect: true
```

If `gem list` prints `false`, install it first: `gem install rails -v 8.1.3 --no-document`.

- [ ] **Step 2: Generate the app in place**

```bash
rails _8.1.3_ new . \
  --database=sqlite3 \
  --skip-action-mailer \
  --skip-action-mailbox \
  --skip-action-text \
  --skip-active-storage \
  --skip-active-job \
  --skip-action-cable \
  --skip-solid \
  --skip-javascript \
  --skip-hotwire \
  --skip-jbuilder \
  --skip-system-test \
  --skip-kamal \
  --skip-thruster \
  --skip-ci \
  --skip-docker \
  --skip-devcontainer \
  --force
```

Answer "y" if prompted to overwrite `.gitignore` (the generator merges sensibly). This runs in a directory that already has `.git`, `docs/`, and `mise.toml` — none of those are touched by the generator.

- [ ] **Step 3: Verify the Gemfile pinned the exact Rails version**

Open `Gemfile` and confirm the line reads exactly:

```ruby
gem "rails", "8.1.3"
```

(The generator pins the exact version automatically when invoked as `rails _8.1.3_ new`; only edit it if it doesn't match.)

- [ ] **Step 4: Install gems**

```bash
bundle install
```

- [ ] **Step 5: Verify the app boots and the test harness runs**

```bash
bin/rails db:prepare
bin/rails runner "puts Rails.version"   # expect: 8.1.3
bin/rails test                          # expect: 0 runs, 0 assertions, 0 failures, 0 errors
```

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Generate Rails 8.1.3 app skeleton"
```

---

### Task 2: Routing, i18n, and the home page shell

**Files:**
- Modify: `config/application.rb`
- Modify: `config/routes.rb`
- Modify: `app/controllers/application_controller.rb`
- Create: `app/controllers/pages_controller.rb`
- Create: `app/views/pages/home.html.erb`
- Create: `config/locales/pt-BR.yml`
- Create: `config/locales/en-US.yml`
- Test: `test/controllers/pages_controller_test.rb`

**Interfaces:**
- Produces: `home_path` route helper (locale-aware), `PagesController#home`, `ApplicationController#switch_locale` (an `around_action` every later controller inherits), and the `pages.home.title` i18n key later tasks add sections under.

- [ ] **Step 1: Write the failing request test**

```ruby
# test/controllers/pages_controller_test.rb
require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "root redirects to the default locale" do
    get "/"
    assert_redirected_to "/pt-BR"
  end

  test "home responds successfully in pt-BR" do
    get "/pt-BR"
    assert_response :success
    assert_select "h1", "Nielson Rolim"
  end

  test "home responds successfully in en-US" do
    get "/en-US"
    assert_response :success
    assert_select "h1", "Nielson Rolim"
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
bin/rails test test/controllers/pages_controller_test.rb
```

Expected: errors like `No route matches [GET] "/pt-BR"` (route doesn't exist yet).

- [ ] **Step 3: Configure available locales**

```ruby
# config/application.rb — inside class Application < Rails::Application
config.i18n.default_locale = :"pt-BR"
config.i18n.available_locales = [:"pt-BR", :"en-US"]
```

- [ ] **Step 4: Add the routes**

```ruby
# config/routes.rb
Rails.application.routes.draw do
  root to: redirect("/pt-BR")

  scope "(:locale)", locale: /pt-BR|en-US/ do
    get "/", to: "pages#home", as: :home
  end

  resources :subscribers, only: [:create]
end
```

- [ ] **Step 5: Set the locale from the URL in `ApplicationController`**

```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::Base
  around_action :switch_locale

  private

  def switch_locale(&action)
    locale = params[:locale].presence_in(I18n.available_locales.map(&:to_s)) || I18n.default_locale
    I18n.with_locale(locale, &action)
  end

  def default_url_options
    { locale: I18n.locale }
  end
end
```

- [ ] **Step 6: Add `PagesController`**

```ruby
# app/controllers/pages_controller.rb
class PagesController < ApplicationController
  def home
  end
end
```

- [ ] **Step 7: Add the minimal view**

```erb
<%# app/views/pages/home.html.erb %>
<h1><%= t(".title") %></h1>
```

- [ ] **Step 8: Add the locale files**

```yaml
# config/locales/pt-BR.yml
pt-BR:
  pages:
    home:
      title: "Nielson Rolim"
```

```yaml
# config/locales/en-US.yml
en-US:
  pages:
    home:
      title: "Nielson Rolim"
```

- [ ] **Step 9: Run the test again to confirm it passes**

```bash
bin/rails test test/controllers/pages_controller_test.rb
```

Expected: `3 runs, 3 assertions, 0 failures, 0 errors`.

- [ ] **Step 10: Commit**

```bash
git add config/application.rb config/routes.rb config/locales app/controllers app/views/pages test/controllers/pages_controller_test.rb
git commit -m "Add locale-aware routing and home page shell"
```

---

### Task 3: Terminal layout, font, and base styling

**Files:**
- Modify: `app/views/layouts/application.html.erb`
- Create: `app/assets/fonts/FiraCodeNerdFont-Regular.ttf` (copied)
- Create: `app/assets/fonts/FiraCodeNerdFont-Bold.ttf` (copied)
- Modify: `app/assets/stylesheets/application.css` → renamed to `app/assets/stylesheets/application.css.erb`
- Test: `test/controllers/pages_controller_test.rb` (extend)

**Interfaces:**
- Consumes: `home_path` and the `pages.home.title` key from Task 2.
- Produces: `.terminal`, `.terminal__prompt`, `.terminal__output` CSS classes and a `.locale-switch` block in the layout that every later content task renders its sections/prompts inside of.

- [ ] **Step 1: Copy the font files into the app**

```bash
mkdir -p app/assets/fonts
cp /usr/share/fonts/TTF/FiraCodeNerdFont-Regular.ttf app/assets/fonts/
cp /usr/share/fonts/TTF/FiraCodeNerdFont-Bold.ttf app/assets/fonts/
```

- [ ] **Step 2: Write the failing test for the terminal chrome**

Add to `test/controllers/pages_controller_test.rb`:

```ruby
  test "home renders the terminal prompt and locale switcher" do
    get "/pt-BR"
    assert_select ".terminal__prompt", minimum: 1
    assert_select "a.locale-switch__link[href=?]", "/en-US"
  end
```

- [ ] **Step 3: Run it to confirm it fails**

```bash
bin/rails test test/controllers/pages_controller_test.rb
```

Expected: failures — no `.terminal__prompt` or `.locale-switch__link` elements exist yet.

- [ ] **Step 4: Rename the stylesheet to allow ERB (for `asset_path` in `@font-face`)**

```bash
git mv app/assets/stylesheets/application.css app/assets/stylesheets/application.css.erb
```

- [ ] **Step 5: Write the terminal stylesheet**

Replace the contents of `app/assets/stylesheets/application.css.erb` with:

```css
@font-face {
  font-family: "FiraCode Nerd Font";
  src: url("<%= asset_path 'FiraCodeNerdFont-Regular.ttf' %>") format("truetype");
  font-weight: 400;
  font-style: normal;
}

@font-face {
  font-family: "FiraCode Nerd Font";
  src: url("<%= asset_path 'FiraCodeNerdFont-Bold.ttf' %>") format("truetype");
  font-weight: 700;
  font-style: normal;
}

:root {
  --bg: #0a0f0a;
  --fg: #39ff14;
  --fg-dim: #1f8a13;
  --accent: #f5c451;
  --error: #ff6b6b;
}

* {
  box-sizing: border-box;
}

body {
  margin: 0;
  background: var(--bg);
  color: var(--fg);
  font-family: "FiraCode Nerd Font", monospace;
  font-size: 16px;
  line-height: 1.5;
  padding: 1.5rem;
}

a {
  color: var(--accent);
}

.terminal {
  max-width: 860px;
  margin: 0 auto;
}

.locale-switch {
  margin-bottom: 2rem;
  color: var(--fg-dim);
}

.locale-switch__link {
  text-decoration: none;
}

.locale-switch__link[aria-current="true"] {
  color: var(--fg);
  text-decoration: underline;
}

.terminal__prompt {
  color: var(--fg-dim);
  margin: 2rem 0 0.5rem;
}

.terminal__prompt::before {
  content: "nielson@nielsonrolim:~$ ";
}

.terminal__output {
  margin: 0 0 1rem;
  white-space: pre-wrap;
}

.cursor {
  display: inline-block;
  width: 0.6em;
  height: 1em;
  background: var(--fg);
  animation: blink 1s steps(1) infinite;
  vertical-align: text-bottom;
}

@keyframes blink {
  50% { opacity: 0; }
}

@media (max-width: 480px) {
  body {
    font-size: 14px;
    padding: 1rem;
  }
}

.flash {
  padding: 0.5rem 0.75rem;
  border: 1px solid currentColor;
  margin-bottom: 1rem;
}

.flash--alert {
  color: var(--error);
}
```

- [ ] **Step 6: Write the layout**

```erb
<%# app/views/layouts/application.html.erb %>
<!DOCTYPE html>
<html>
  <head>
    <title>Nielson Rolim</title>
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <%= csrf_meta_tags %>
    <%= csp_meta_tag %>
    <%= stylesheet_link_tag "application" %>
  </head>

  <body>
    <div class="terminal">
      <nav class="locale-switch">
        <%= link_to "PT-BR", home_path(locale: "pt-BR"), class: "locale-switch__link", aria: { current: I18n.locale == :"pt-BR" } %>
        /
        <%= link_to "EN-US", home_path(locale: "en-US"), class: "locale-switch__link", aria: { current: I18n.locale == :"en-US" } %>
      </nav>

      <% flash.each do |type, message| %>
        <p class="flash flash--<%= type %>"><%= message %></p>
      <% end %>

      <%= yield %>

      <span class="cursor" aria-hidden="true"></span>
    </div>
  </body>
</html>
```

- [ ] **Step 7: Add the prompt line to the home view**

```erb
<%# app/views/pages/home.html.erb %>
<h1><%= t(".title") %></h1>
<p class="terminal__prompt">cat about.txt</p>
```

- [ ] **Step 8: Run the test again to confirm it passes**

```bash
bin/rails test test/controllers/pages_controller_test.rb
```

Expected: `4 runs, 5 assertions, 0 failures, 0 errors`.

- [ ] **Step 9: Commit**

```bash
git add app/assets app/views/layouts app/views/pages test/controllers/pages_controller_test.rb
git commit -m "Add terminal layout, FiraCode Nerd Font, and base styling"
```

---

### Task 4: About and Experience sections

**Files:**
- Modify: `config/locales/pt-BR.yml`
- Modify: `config/locales/en-US.yml`
- Modify: `app/views/pages/home.html.erb`
- Test: `test/controllers/pages_controller_test.rb` (extend)

**Interfaces:**
- Consumes: `.terminal__prompt` / `.terminal__output` classes from Task 3.
- Produces: `pages.home.about` and `pages.home.experience` locale keys later tasks don't depend on, but must not collide with (`jampa_ruby`, `projects`, `contact`, `newsletter` keys added in later tasks).

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/pages_controller_test.rb`:

```ruby
  test "home lists work experience in pt-BR" do
    get "/pt-BR"
    assert_select "body", /Light Labs Inc/
    assert_select "body", /Fluxx/
  end

  test "home lists work experience in en-US" do
    get "/en-US"
    assert_select "body", /Light Labs Inc/
    assert_select "body", /Fluxx/
  end
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
bin/rails test test/controllers/pages_controller_test.rb
```

Expected: failures — "Light Labs Inc" not present yet.

- [ ] **Step 3: Add the About and Experience content to the locale files**

```yaml
# config/locales/pt-BR.yml
pt-BR:
  pages:
    home:
      title: "Nielson Rolim"
      about:
        prompt: "cat about.txt"
        body: "Sou Nielson Rolim, Engenheiro de Software Sênior em João Pessoa, Paraíba. Trabalho principalmente com Ruby on Rails, Hotwire, React e TailwindCSS, e sou um entusiasta de Linux."
      experience:
        prompt: "cat experience.log"
        jobs:
          - title: "Senior Software Engineer"
            company: "Light Labs Inc"
            period: "Mar 2025 – atual"
          - title: "Software Engineer"
            company: "Fluxx"
            period: "Out 2023 – Fev 2025"
          - title: "Senior Software Engineer"
            company: "Shift"
            period: "Ago 2021 – Out 2023"
          - title: "Software Engineer"
            company: "RD Station"
            period: "Abr 2021 – Ago 2021"
          - title: "Backend Developer"
            company: "enjoei"
            period: "Out 2020 – Mar 2021"
```

```yaml
# config/locales/en-US.yml
en-US:
  pages:
    home:
      title: "Nielson Rolim"
      about:
        prompt: "cat about.txt"
        body: "I'm Nielson Rolim, a Senior Software Engineer based in João Pessoa, Paraíba, Brazil. I mainly work with Ruby on Rails, Hotwire, React, and TailwindCSS, and I'm a Linux enthusiast."
      experience:
        prompt: "cat experience.log"
        jobs:
          - title: "Senior Software Engineer"
            company: "Light Labs Inc"
            period: "Mar 2025 – present"
          - title: "Software Engineer"
            company: "Fluxx"
            period: "Oct 2023 – Feb 2025"
          - title: "Senior Software Engineer"
            company: "Shift"
            period: "Aug 2021 – Oct 2023"
          - title: "Software Engineer"
            company: "RD Station"
            period: "Apr 2021 – Aug 2021"
          - title: "Backend Developer"
            company: "enjoei"
            period: "Oct 2020 – Mar 2021"
```

- [ ] **Step 4: Render About and Experience in the view**

Replace `app/views/pages/home.html.erb` with:

```erb
<%# app/views/pages/home.html.erb %>
<h1><%= t(".title") %></h1>

<p class="terminal__prompt"><%= t(".about.prompt") %></p>
<p class="terminal__output"><%= t(".about.body") %></p>

<p class="terminal__prompt"><%= t(".experience.prompt") %></p>
<ul class="terminal__output">
  <% t(".experience.jobs").each do |job| %>
    <li><%= job[:title] %> — <%= job[:company] %> (<%= job[:period] %>)</li>
  <% end %>
</ul>
```

- [ ] **Step 5: Run the test again to confirm it passes**

```bash
bin/rails test test/controllers/pages_controller_test.rb
```

Expected: `6 runs, 9 assertions, 0 failures, 0 errors`.

- [ ] **Step 6: Commit**

```bash
git add config/locales app/views/pages test/controllers/pages_controller_test.rb
git commit -m "Add About and Experience sections"
```

---

### Task 5: Jampa Ruby section

**Files:**
- Create: `app/assets/images/jamparuby.svg` (copied)
- Modify: `config/locales/pt-BR.yml`
- Modify: `config/locales/en-US.yml`
- Modify: `app/views/pages/home.html.erb`
- Test: `test/controllers/pages_controller_test.rb` (extend)

**Interfaces:**
- Consumes: `.terminal__prompt` / `.terminal__output` from Task 3.
- Produces: `pages.home.jampa_ruby` locale key.

- [ ] **Step 1: Copy the logo into the app**

```bash
mkdir -p app/assets/images
cp ~/pCloudDrive/JampaRuby/Artes/jamparuby.svg app/assets/images/
```

- [ ] **Step 2: Write the failing test**

Add to `test/controllers/pages_controller_test.rb`:

```ruby
  test "home shows the Jampa Ruby section with logo and links" do
    get "/pt-BR"
    assert_select "img[src*=?]", "jamparuby"
    assert_select "a[href=?]", "https://chat.whatsapp.com/Kan05TwASEtDItNK0ClCJT"
    assert_select "a[href=?]", "https://crudpb.org/"
  end
```

- [ ] **Step 3: Run it to confirm it fails**

```bash
bin/rails test test/controllers/pages_controller_test.rb
```

Expected: failures — no `img` or matching links yet.

- [ ] **Step 4: Add the Jampa Ruby content to the locale files**

```yaml
# config/locales/pt-BR.yml — nested under pages.home, alongside experience:
      jampa_ruby:
        prompt: "cat jamparuby.txt"
        body_html: "Sou membro ativo da <a href=\"https://chat.whatsapp.com/Kan05TwASEtDItNK0ClCJT\">Jampa Ruby</a>, a comunidade de desenvolvedores Ruby da Paraíba, Brasil — parte da <a href=\"https://crudpb.org/\">CRUDPB</a>. Entre no grupo do WhatsApp e participe."
```

```yaml
# config/locales/en-US.yml — nested under pages.home, alongside experience:
      jampa_ruby:
        prompt: "cat jamparuby.txt"
        body_html: "I'm an active member of <a href=\"https://chat.whatsapp.com/Kan05TwASEtDItNK0ClCJT\">Jampa Ruby</a>, the Ruby developer community of Paraíba, Brazil — part of <a href=\"https://crudpb.org/\">CRUDPB</a>. Join the WhatsApp group and take part."
```

- [ ] **Step 5: Render the section**

Append to `app/views/pages/home.html.erb`, after the Experience block:

```erb
<p class="terminal__prompt"><%= t(".jampa_ruby.prompt") %></p>
<p class="terminal__output">
  <%= image_tag "jamparuby.svg", alt: "Jampa Ruby", width: 96 %>
  <%= t(".jampa_ruby.body_html") %>
</p>
```

- [ ] **Step 6: Run the test again to confirm it passes**

```bash
bin/rails test test/controllers/pages_controller_test.rb
```

Expected: `7 runs, 12 assertions, 0 failures, 0 errors`.

- [ ] **Step 7: Commit**

```bash
git add app/assets/images config/locales app/views/pages test/controllers/pages_controller_test.rb
git commit -m "Add Jampa Ruby section with logo and community links"
```

---

### Task 6: Projects and Contact sections

**Files:**
- Modify: `config/locales/pt-BR.yml`
- Modify: `config/locales/en-US.yml`
- Modify: `app/views/pages/home.html.erb`
- Test: `test/controllers/pages_controller_test.rb` (extend)

**Interfaces:**
- Consumes: `.terminal__prompt` / `.terminal__output` from Task 3.
- Produces: `pages.home.projects` and `pages.home.contact` locale keys.

- [ ] **Step 1: Write the failing test**

Add to `test/controllers/pages_controller_test.rb`:

```ruby
  test "home lists projects and contact links" do
    get "/pt-BR"
    assert_select "body", /Lavanderia 60 Minutos/
    assert_select "body", /IBAPE-PB/
    assert_select "a[href=?]", "mailto:contato@nielsonrolim.com"
    assert_select "a[href=?]", "https://github.com/nielsonrolim"
    assert_select "a[href=?]", "https://www.linkedin.com/in/nielsonrolim/"
  end
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
bin/rails test test/controllers/pages_controller_test.rb
```

Expected: failures — none of that content exists yet.

- [ ] **Step 3: Add Projects and Contact content to the locale files**

```yaml
# config/locales/pt-BR.yml — nested under pages.home, alongside jampa_ruby:
      projects:
        prompt: "cat projects.md"
        items:
          - name: "Lavanderia 60 Minutos"
            description: "Projetei a arquitetura de software de uma rede de lavanderias self-service 100% automatizadas, com mais de 400 lojas no Brasil. Desenvolvi o sistema de gestão e a API que comunica com os terminais das lojas, além da primeira versão do terminal do atendente, rodando em um Raspberry Pi com touchscreen, sincronizado com o sistema central e capaz de operar offline."
            tags: "Ruby on Rails, Node.js, PostgreSQL, Sidekiq, Redis, Raspberry Pi"
          - name: "IBAPE-PB — Sistema de Distribuição de Trabalhos"
            description: "Sistema de distribuição justa de trabalhos (perícias e avaliações) para associados do IBAPE-PB, via sorteio e indicação, cobrindo todo o ciclo de vida do trabalho (criação, publicação, sorteio, aceite, conclusão) com relatórios e notificações por e-mail."
            tags: "Ruby on Rails, PostgreSQL, Redis"
      contact:
        prompt: "cat contact.txt"
        email_label: "E-mail"
        github_label: "GitHub"
        linkedin_label: "LinkedIn"
```

```yaml
# config/locales/en-US.yml — nested under pages.home, alongside jampa_ruby:
      projects:
        prompt: "cat projects.md"
        items:
          - name: "Lavanderia 60 Minutos"
            description: "Designed the software architecture for a fully automated self-service laundry chain with 400+ stores across Brazil. Built the management system and the API communicating with in-store attendant terminals, plus the first version of the attendant terminal itself, running on a Raspberry Pi with a touchscreen, kept in sync with the central system while able to operate offline."
            tags: "Ruby on Rails, Node.js, PostgreSQL, Sidekiq, Redis, Raspberry Pi"
          - name: "IBAPE-PB — Work Distribution System"
            description: "Fair-distribution system for professional engineering assessments for IBAPE-PB, via lottery and direct nomination, covering the full work lifecycle (creation, publication, draw, acceptance, completion) with reporting and email notifications."
            tags: "Ruby on Rails, PostgreSQL, Redis"
      contact:
        prompt: "cat contact.txt"
        email_label: "Email"
        github_label: "GitHub"
        linkedin_label: "LinkedIn"
```

- [ ] **Step 4: Render both sections**

Append to `app/views/pages/home.html.erb`, after the Jampa Ruby block:

```erb
<p class="terminal__prompt"><%= t(".projects.prompt") %></p>
<% t(".projects.items").each do |project| %>
  <div class="terminal__output">
    <strong><%= project[:name] %></strong><br>
    <%= project[:description] %><br>
    <em><%= project[:tags] %></em>
  </div>
<% end %>

<p class="terminal__prompt"><%= t(".contact.prompt") %></p>
<ul class="terminal__output">
  <li><%= t(".contact.email_label") %>: <%= link_to "contato@nielsonrolim.com", "mailto:contato@nielsonrolim.com" %></li>
  <li><%= t(".contact.github_label") %>: <%= link_to "github.com/nielsonrolim", "https://github.com/nielsonrolim" %></li>
  <li><%= t(".contact.linkedin_label") %>: <%= link_to "linkedin.com/in/nielsonrolim", "https://www.linkedin.com/in/nielsonrolim/" %></li>
</ul>
```

- [ ] **Step 5: Run the test again to confirm it passes**

```bash
bin/rails test test/controllers/pages_controller_test.rb
```

Expected: `8 runs, 17 assertions, 0 failures, 0 errors`.

- [ ] **Step 6: Commit**

```bash
git add config/locales app/views/pages test/controllers/pages_controller_test.rb
git commit -m "Add Projects and Contact sections"
```

---

### Task 7: Subscriber model

**Files:**
- Create: `db/migrate/<timestamp>_create_subscribers.rb`
- Create: `app/models/subscriber.rb`
- Create: `test/fixtures/subscribers.yml`
- Test: `test/models/subscriber_test.rb`

**Interfaces:**
- Produces: `Subscriber` (columns: `email:string`, `created_at`, `updated_at`; virtual attribute `nickname` used only as an in-memory honeypot field, never persisted), validated for presence, email format, and case-insensitive uniqueness of `email`. Task 8 consumes this exact class and its `nickname` attribute.

- [ ] **Step 1: Generate and edit the migration**

```bash
bin/rails generate migration CreateSubscribers
```

Replace the generated file's contents with:

```ruby
class CreateSubscribers < ActiveRecord::Migration[8.1]
  def change
    create_table :subscribers do |t|
      t.string :email, null: false
      t.timestamps
    end
    add_index :subscribers, "lower(email)", unique: true, name: "index_subscribers_on_lower_email"
  end
end
```

- [ ] **Step 2: Run the migration**

```bash
bin/rails db:migrate
```

- [ ] **Step 3: Add an empty fixtures file** (avoids the default generator's placeholder rows colliding with the uniqueness index)

```yaml
# test/fixtures/subscribers.yml
```

- [ ] **Step 4: Write the failing model test**

```ruby
# test/models/subscriber_test.rb
require "test_helper"

class SubscriberTest < ActiveSupport::TestCase
  test "valid with a proper email" do
    subscriber = Subscriber.new(email: "reader@example.com")
    assert subscriber.valid?
  end

  test "invalid without an email" do
    subscriber = Subscriber.new(email: nil)
    assert_not subscriber.valid?
  end

  test "invalid with a malformed email" do
    subscriber = Subscriber.new(email: "not-an-email")
    assert_not subscriber.valid?
  end

  test "invalid with a duplicate email regardless of case" do
    Subscriber.create!(email: "reader@example.com")
    duplicate = Subscriber.new(email: "READER@example.com")
    assert_not duplicate.valid?
  end
end
```

- [ ] **Step 5: Run it to confirm it fails**

```bash
bin/rails test test/models/subscriber_test.rb
```

Expected: failures on the presence/format/duplicate tests (no validations exist yet), plus a `NameError` if `app/models/subscriber.rb` doesn't exist yet either.

- [ ] **Step 6: Write the model**

```ruby
# app/models/subscriber.rb
class Subscriber < ApplicationRecord
  attr_accessor :nickname

  validates :email, presence: true,
                     format: { with: URI::MailTo::EMAIL_REGEXP },
                     uniqueness: { case_sensitive: false }
end
```

- [ ] **Step 7: Run the test again to confirm it passes**

```bash
bin/rails test test/models/subscriber_test.rb
```

Expected: `4 runs, 4 assertions, 0 failures, 0 errors`.

- [ ] **Step 8: Commit**

```bash
git add db app/models test/fixtures/subscribers.yml test/models/subscriber_test.rb
git commit -m "Add Subscriber model with honeypot attribute"
```

---

### Task 8: Newsletter signup form and controller

**Files:**
- Create: `app/controllers/subscribers_controller.rb`
- Modify: `config/locales/pt-BR.yml`
- Modify: `config/locales/en-US.yml`
- Modify: `app/views/pages/home.html.erb`
- Test: `test/controllers/subscribers_controller_test.rb`

**Interfaces:**
- Consumes: `Subscriber` model and its `nickname` honeypot attribute from Task 7; `home_path` route helper from Task 2.
- Produces: `POST /subscribers` (route already defined in Task 2 as `resources :subscribers, only: [:create]`).

- [ ] **Step 1: Write the failing controller tests**

```ruby
# test/controllers/subscribers_controller_test.rb
require "test_helper"

class SubscribersControllerTest < ActionDispatch::IntegrationTest
  test "valid signup creates a subscriber and redirects with a notice" do
    assert_difference("Subscriber.count", 1) do
      post "/subscribers", params: { subscriber: { email: "reader@example.com", nickname: "" } }
    end
    assert_redirected_to "/pt-BR"
    follow_redirect!
    assert_select ".flash--notice"
  end

  test "duplicate email does not create a second subscriber" do
    Subscriber.create!(email: "reader@example.com")

    assert_no_difference("Subscriber.count") do
      post "/subscribers", params: { subscriber: { email: "reader@example.com", nickname: "" } }
    end
    assert_redirected_to "/pt-BR"
    follow_redirect!
    assert_select ".flash--alert"
  end

  test "filled honeypot silently skips creation but still looks successful" do
    assert_no_difference("Subscriber.count") do
      post "/subscribers", params: { subscriber: { email: "bot@example.com", nickname: "i-am-a-bot" } }
    end
    assert_redirected_to "/pt-BR"
    follow_redirect!
    assert_select ".flash--notice"
  end
end
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
bin/rails test test/controllers/subscribers_controller_test.rb
```

Expected: `AbstractController::ActionNotFound` or routing errors — `SubscribersController` doesn't exist yet.

- [ ] **Step 3: Add the newsletter locale strings**

```yaml
# config/locales/pt-BR.yml — nested under pages.home, alongside contact:
      newsletter:
        prompt: "./subscribe.sh"
        body: "Receba uma newsletter mensal sobre tecnologia."
        email_placeholder: "seu@email.com"
        submit: "Inscrever-se"
        nickname_label: "Deixe em branco"
subscribers:
  create:
    success: "Inscrição confirmada! Obrigado por assinar."
    invalid: "Não foi possível concluir a inscrição. Verifique o e-mail informado."
```

```yaml
# config/locales/en-US.yml — nested under pages.home, alongside contact:
      newsletter:
        prompt: "./subscribe.sh"
        body: "Get a monthly newsletter about tech."
        email_placeholder: "you@email.com"
        submit: "Subscribe"
        nickname_label: "Leave blank"
subscribers:
  create:
    success: "You're subscribed! Thanks for joining."
    invalid: "We couldn't complete your signup. Please check the email address."
```

- [ ] **Step 4: Add the controller**

```ruby
# app/controllers/subscribers_controller.rb
class SubscribersController < ApplicationController
  def create
    @subscriber = Subscriber.new(subscriber_params)

    if @subscriber.nickname.present?
      redirect_to home_path, notice: t("subscribers.create.success")
      return
    end

    if @subscriber.save
      redirect_to home_path, notice: t("subscribers.create.success")
    else
      redirect_to home_path, alert: t("subscribers.create.invalid")
    end
  end

  private

  def subscriber_params
    params.require(:subscriber).permit(:email, :nickname)
  end
end
```

- [ ] **Step 5: Add the form to the home view**

Append to `app/views/pages/home.html.erb`, after the Contact block:

```erb
<p class="terminal__prompt"><%= t(".newsletter.prompt") %></p>
<div class="terminal__output">
  <p><%= t(".newsletter.body") %></p>
  <%= form_with url: subscribers_path, method: :post do |form| %>
    <%= form.label :email, t(".newsletter.email_placeholder"), style: "display:none" %>
    <%= form.email_field :email, placeholder: t(".newsletter.email_placeholder"), required: true %>

    <span aria-hidden="true" style="position:absolute; left:-9999px;">
      <%= form.label :nickname, t(".newsletter.nickname_label") %>
      <%= form.text_field :nickname, tabindex: -1, autocomplete: "off" %>
    </span>

    <%= form.submit t(".newsletter.submit") %>
  <% end %>
</div>
```

- [ ] **Step 6: Run the tests again to confirm they pass**

```bash
bin/rails test test/controllers/subscribers_controller_test.rb test/controllers/pages_controller_test.rb
```

Expected: all tests green.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/subscribers_controller.rb config/locales app/views/pages test/controllers/subscribers_controller_test.rb
git commit -m "Add newsletter signup form with honeypot spam protection"
```

---

### Task 9: Docker Compose deployment

**Files:**
- Create: `Dockerfile`
- Create: `docker-compose.yml`
- Create: `.dockerignore`
- Create: `.env.example`

**Interfaces:**
- Produces: a `web` service image runnable via `docker compose up`, listening on an internal port for the VPS's existing Nginx to proxy to, with `db/production.sqlite3` persisted in a named volume.

- [ ] **Step 1: Write the Dockerfile**

```dockerfile
# Dockerfile
FROM ruby:4.0-slim AS build

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential git libsqlite3-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set without 'development test' && bundle install --jobs 4

COPY . .
RUN bin/rails assets:precompile

FROM ruby:4.0-slim

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    libsqlite3-0 curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /app /app

ENV RAILS_ENV=production
ENV RAILS_LOG_TO_STDOUT=true
ENV RAILS_SERVE_STATIC_FILES=true

EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
```

- [ ] **Step 2: Write `.dockerignore`**

```
.git
log/*
tmp/*
db/*.sqlite3
db/*.sqlite3-*
docs/
```

- [ ] **Step 3: Write `docker-compose.yml`**

```yaml
services:
  web:
    build: .
    restart: unless-stopped
    env_file: .env
    volumes:
      - sqlite_data:/app/db
    ports:
      - "127.0.0.1:3000:3000"

volumes:
  sqlite_data:
```

Binding to `127.0.0.1:3000` keeps the port off the public interface — the VPS's existing Nginx reverse-proxies to it locally.

- [ ] **Step 4: Write `.env.example`**

```
RAILS_MASTER_KEY=replace_with_the_contents_of_config_master_key
```

- [ ] **Step 5: Build the image locally as a smoke test**

```bash
docker compose build
```

Expected: the build completes without errors (asset precompilation and bundle install both succeed).

- [ ] **Step 6: Boot it locally with a real master key and verify it serves the home page**

```bash
cp .env.example .env
sed -i "s/replace_with_the_contents_of_config_master_key/$(cat config/master.key)/" .env
docker compose up -d
curl -sSf -o /dev/null -w "%{http_code}\n" http://127.0.0.1:3000/pt-BR
docker compose down
```

Expected output: `200`.

- [ ] **Step 7: Commit**

```bash
git add Dockerfile docker-compose.yml .dockerignore .env.example
git commit -m "Add Docker Compose deployment for the VPS"
```

Note: `.env` itself must stay untracked (Rails' default `.gitignore` from Task 1 already ignores it) — only `.env.example` is committed. On the VPS, create the real `.env` from `.env.example` with the actual `config/master.key` contents before running `docker compose up -d`.
