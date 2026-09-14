# Renders a newsletter issue — the week's clippings — into the HTML and
# plain-text bodies that get emailed to subscribers.
class NewsletterComposer
  def self.subject_for(date, locale: I18n.default_locale)
    I18n.with_locale(locale) do
      I18n.t("newsletters.subject", date: I18n.l(date.to_date, format: :long))
    end
  end

  def initialize(clippings, date: Time.current, locale: I18n.default_locale)
    @clippings = clippings.to_a
    @date = date
    @locale = locale
  end

  attr_reader :clippings, :date, :locale

  def subject
    self.class.subject_for(date, locale: locale)
  end

  def to_html
    render(formats: [ :html ])
  end

  def to_text
    render(formats: [ :text ])
  end

  def empty?
    clippings.empty?
  end

  private

  def render(formats:)
    I18n.with_locale(locale) do
      ApplicationController.render(
        template: "newsletters/email_body",
        layout: false,
        formats: formats,
        assigns: { clippings: clippings, issue_date: date }
      )
    end
  end
end
