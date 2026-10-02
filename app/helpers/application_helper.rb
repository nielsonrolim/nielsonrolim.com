module ApplicationHelper
  # A third-party URL turned into something safe to put in an `href`. Feed and
  # clipping URLs come from external content, so only real http(s) links are
  # rendered; anything else (javascript:, data:, malformed) degrades to "#".
  def safe_url(url)
    SafeUrl.safe(url) || "#"
  end

  # The full unsubscribe URL for a subscriber, built from the same host and
  # protocol the emails use, so what the admin copies is exactly what a mail
  # client would call. Admin pages do not carry url options of their own.
  def unsubscribe_link_for(subscriber)
    unsubscribe_url({ token: subscriber.unsubscribe_token }
                      .merge(ActionMailer::Base.default_url_options))
  end
end
