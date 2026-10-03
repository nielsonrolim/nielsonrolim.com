require "json"

# Fetches a YouTube video's own content: the title, the full description and,
# when YouTube offers one, the caption transcript.
#
# A watch page is a JavaScript app. Its static HTML has no article text at all,
# only chrome (a copyright footer), which is why the generic ArticleFetcher
# extraction was useless there: the model received a page footer and summarized
# the absence of content. The video's data does travel in the page, though, in
# `ytInitialPlayerResponse`, so this reads that directly.
#
# The transcript is best effort. YouTube serves captions from a signed URL that
# can be unavailable (region, bot checks, expired signature), so a failed or
# empty response falls back to the description alone instead of failing the
# fetch. The page lists every available track, and they are tried in order of
# preference — the original language first, then auto-generated captions ahead
# of human ones within it — until one yields text, so a broken first track no
# longer costs the video its transcript.
#
# `timedtext` now also requires a PoToken for many videos: it answers HTTP 200
# with an empty body, so a page that lists tracks can still yield no text. When
# that happens — and only when the page listed tracks at all — `YtdlpCli` is
# tried as a fallback, because yt-dlp reaches the captions through the
# `android_vr` player client without a PoToken provider. Its result goes through
# the same normalization and the same ceiling as the page's own tracks.
#
# Whatever is produced is kept within the same ceiling ArticleFetcher applies to
# an article, so the stored text is exactly what the model sees and a long
# transcript is cut at head and tail rather than losing its conclusion.
class YoutubeFetcher
  Error = Class.new(StandardError)

  WATCH_ENDPOINT = "https://www.youtube.com/watch"
  JSON_ACCEPT = "application/json"

  # Path prefixes that carry the video id in the segment right after them.
  ID_PREFIXES = %w[shorts embed live v].freeze

  # The full description lives inside the player response JSON embedded in the
  # page. Pulling the one string out, rather than parsing the whole blob, keeps
  # this robust against the rest of that object changing shape.
  SHORT_DESCRIPTION = /"shortDescription":"((?:[^"\\]|\\.)*)"/m

  # The caption track list and the audio track list are arrays inside the
  # player response, not guaranteed shapes, so only the fields needed are read
  # from each entry and any missing piece degrades to "no transcript".
  CAPTION_TRACKS_KEY = '"captionTracks"'
  AUDIO_TRACKS_KEY = '"audioTracks"'
  DEFAULT_AUDIO_TRACK_INDEX = /"defaultAudioTrackIndex":(\d+)/
  DEFAULT_AUDIO_LANGUAGE = /"defaultAudioLanguage":"([^"]+)"/m

  # A page can list dozens of tracks; the best one is almost always at the top
  # of the ranking, so only a few are ever tried. Without this cap a bad day
  # could mean a network request (with its own read timeout) per track.
  MAX_TRACK_ATTEMPTS = 3

  # The transcript is trimmed into the same budget ArticleFetcher gives an
  # article, because that is the ceiling SummaryGenerator reads (its
  # MAX_SOURCE_CHARS). Referenced, not redefined, so there is a single 40k.
  MAX_TEXT_CHARS = ArticleFetcher::MAX_TEXT_CHARS

  # Between the kept head and tail of a cut transcript, so the model (and the
  # tests) can see that the middle was dropped.
  TRANSCRIPT_GAP = "\n\n[... transcript truncated ...]\n\n"

  # A short function-word list per language (pt/en/es), used only to guess the
  # language of a description when the page names no original track. Kept tiny
  # and syntactic: those words are frequent and rarely appear in the other two,
  # and the guess is discarded on a tie.
  LANGUAGE_HINTS = {
    "pt" => %w[a o e de que nao não um uma para com se por do da em os as do dos das
               voce você isso essa este esta muito mais ja já aqui entao então],
    "en" => %w[the a an of to in and is are for with that this it you your we they
               on as be by at or from not have has],
    "es" => %w[el la los las de que no un una para con se por del en es son como
               tu usted esto esta muy mas ya aqui entonces]
  }.freeze

  # Below this many alphabetic words a description is too short to guess from.
  MIN_LANGUAGE_WORDS = 12

  # Fixed preference order for choosing a transcript when the video's own
  # language has no usable track. Base tags are matched so "pt" also covers
  # "pt-BR"/"pt-PT" by family; the explicit regional tags are listed to keep the
  # order the reader asked for. Any language the page lists but this list omits
  # comes after, in page order.
  PREFERRED_LANGUAGES = %w[pt pt-BR pt-PT en en-US es].freeze

  Result = Struct.new(:title, :text, keyword_init: true)

  # One caption track from the player response. `kind` is "asr" on
  # auto-generated captions and absent on human ones; `vss_id` (".en", "a.en")
  # is a second signal, since ASR ids are prefixed "a.". `index` is the
  # position in the page's list, kept as a stable tie-breaker.
  Track = Struct.new(:url, :language_code, :kind, :vss_id, :index, keyword_init: true) do
    def automatic?
      kind == "asr" || vss_id.to_s.start_with?("a.")
    end
  end

  # The video id in `url`, or nil when it is not a YouTube video URL. Covers
  # watch links, youtu.be short links and the /shorts, /embed, /live and /v
  # paths, on youtube.com and its subdomains.
  def self.video_id(url)
    uri = URI.parse(url.to_s)
    return nil unless uri.is_a?(URI::HTTP)

    host = uri.host.to_s.downcase
    if host == "youtu.be"
      first_segment(uri)
    elsif host == "youtube.com" || host.end_with?(".youtube.com")
      segments = uri.path.to_s.split("/").reject(&:empty?)

      if segments.first == "watch"
        query_value(uri, "v")
      elsif ID_PREFIXES.include?(segments.first)
        segments[1].presence
      end
    end
  rescue URI::InvalidURIError
    nil
  end

  def self.first_segment(uri)
    uri.path.to_s.split("/").reject(&:empty?).first.presence
  end
  private_class_method :first_segment

  def self.query_value(uri, key)
    URI.decode_www_form(uri.query.to_s).to_h[key].presence
  rescue ArgumentError
    nil
  end
  private_class_method :query_value

  def initialize(transport: HttpTransport.default, transcript_cli: nil)
    @transport = transport
    @transcript_cli = transcript_cli
  end

  attr_reader :transport

  # The transcript fallback, or a `YtdlpCli` when none was injected. The CLI is
  # a subprocess and a separate seam from the transport (which only speaks
  # HTTP), so it is injectable for the same reason: tests never spawn it.
  def transcript_cli
    @transcript_cli ||= YtdlpCli.new
  end

  def call(url)
    id = self.class.video_id(url)
    raise Error, "not a YouTube video URL: #{url}" if id.blank?

    html = transport.get("#{WATCH_ENDPOINT}?v=#{id}", accept: HttpTransport::HTML_ACCEPT)
    description = description_from(html)
    transcript = transcript_from(html, original_language(html, description), id)
    # Only a video with neither captions nor a description has nothing to
    # summarize; a transcript alone is enough even when there is no description.
    raise Error, "no description or transcript found for YouTube video #{id}" if description.blank? && transcript.blank?

    title = title_from(html).presence || "YouTube video #{id}"
    Result.new(title: title, text: compose(description, transcript))
  rescue HttpTransport::Error => e
    raise Error, e.message
  end

  private

  # Prefer the player response: the <meta> description is truncated to about
  # 160 characters, while `shortDescription` holds the whole thing.
  def description_from(html)
    from_short_description(html).presence || meta_content(html, "og:description")
  end

  def from_short_description(html)
    match = html[SHORT_DESCRIPTION, 1]
    return nil if match.blank?

    JSON.parse(%("#{match}"))
  rescue JSON::ParserError
    nil
  end

  def title_from(html)
    meta_content(html, "og:title")
  end

  def meta_content(html, property)
    document = Nokogiri::HTML(html)
    document.at_css(%(meta[property="#{property}"]))&.[]("content").presence ||
      document.at_css(%(meta[name="#{property}"]))&.[]("content").presence
  end

  # Tries the tracks best-first and keeps the first transcript that has text.
  # Each track can fail (network, expired signature, empty body) without
  # affecting the others or the fetch: the worst case is the description alone.
  #
  # When every track comes back empty but the page *did* list tracks, YouTube is
  # almost certainly insisting on a PoToken for `timedtext` (the response is a
  # 200 with no body). yt-dlp is tried as a fallback in that one case; if the
  # page listed no tracks at all there is nothing to fall back to, so no
  # subprocess is spawned.
  def transcript_from(html, video_language, id)
    tracks = ordered_tracks(html, video_language)

    text = tracks.first(MAX_TRACK_ATTEMPTS).lazy.map { |track| transcript_for(track) }.find(&:present?)
    return text if text.present?
    return nil if tracks.empty?

    fallback_transcript(id, tracks, video_language)
  end

  # yt-dlp is a subprocess: a crash, a timeout or a missing binary must never
  # take the fetch down, so this rescues broadly around the one call and only
  # ever yields text or nil. `YtdlpCli` already rescues its own expected
  # failures; this is the belt to that pair of braces.
  #
  # The language list is built in `fallback_languages`: the video's own language
  # first, then the fixed preference list, then anything else the page lists.
  def fallback_transcript(id, tracks, video_language)
    transcript_cli.call(video_id: id, languages: fallback_languages(tracks, video_language))
  rescue StandardError => e
    Rails.logger.warn("yt-dlp transcript fallback failed for #{id}: #{e.class}: #{e.message}")
    nil
  end

  # The tag list to ask yt-dlp for, in priority order:
  #   1. the video's own language,
  #   2. the fixed preference list (pt, pt-BR, pt-PT, en, en-US, es),
  #   3. any other language the page lists, in page order.
  # Within a language the `<lang>-orig` track (yt-dlp's tag for the original) is
  # offered before the plain tag, because the plain tag asks for a *translation*,
  # which can fail while the original is available.
  #
  # The list is built from languages, not from the raw track tags: the page may
  # omit the video's language entirely (an English video whose list holds only
  # translations), and iterating the tracks would then never ask for English.
  # `YtdlpCli` sanitizes and caps the list again.
  def fallback_languages(tracks, video_language)
    page_languages = tracks.map { |track| track.language_code.to_s }
    ordered = [ video_language, *PREFERRED_LANGUAGES, *page_languages ]

    codes = ordered.flat_map do |language|
      base = base_language(language)
      [ "#{base}-orig", language, base ]
    end

    codes.filter_map do |code|
      tag = code.to_s[/\A[\w-]+\z/]
      next if tag.nil? || tag.start_with?("-")
      next if tag.length > YtdlpCli::MAX_LANGUAGE_LENGTH

      tag
    end.uniq
  end

  # One track: a transport error, an empty body or a shape change all just mean
  # "no text from this track", never an exception that escapes. YouTube's
  # caption endpoint is friendlier to a browser-like request, so a browser UA
  # and the track's own language are sent. The language is reduced to a safe
  # token first: it comes from the page, and a malformed value must not reach
  # the header (or raise out of the fetch).
  def transcript_for(track)
    headers = {}
    language = track.language_code.to_s[/\A[\w-]+\z/]
    headers["Accept-Language"] = language if language

    body = transport.get(unescape(track.url) + "&fmt=json3", accept: JSON_ACCEPT,
                         user_agent: HttpTransport::BROWSER_USER_AGENT, headers: headers)
    self.class.flatten_json3(body)
  rescue HttpTransport::Error, JSON::ParserError, TypeError
    nil
  end

  # The single place json3 is turned into text: joins every caption segment,
  # collapses the whitespace between cues and returns nil when there is nothing.
  # Shared by the live captions path and the yt-dlp fallback so both normalize
  # identically. A malformed body is "no transcript", never an exception.
  def self.flatten_json3(body)
    events = JSON.parse(body.to_s)["events"]
    return if events.blank?

    Array(events).flat_map { |event| Array(event["segs"]).map { |seg| seg["utf8"] } }
                 .join.gsub(/[[:space:]]+/, " ").strip.presence
  rescue JSON::ParserError, TypeError
    nil
  end

  # Deterministic order: the original language always wins, then auto-generated
  # captions ahead of human ones within it, with the page's own order as the
  # final tie-breaker. An auto-generated track in the original language
  # therefore comes before a human one in another language.
  def ordered_tracks(html, original_language)
    tracks_from(html).sort_by do |track|
      [ original_language?(track, original_language) ? 0 : 1,
        track.automatic? ? 0 : 1,
        track.index ]
    end
  end

  def original_language?(track, original_language)
    return false if original_language.blank?

    base_language(track.language_code) == base_language(original_language)
  end

  # Compares language codes by their base tag so "pt-BR" and "pt" match.
  def base_language(code)
    code.to_s.downcase.split("-").first.presence
  end

  # Each entry of `captionTracks` becomes a Track; one without a URL is dropped.
  def tracks_from(html)
    Array(array_field(html, CAPTION_TRACKS_KEY)).filter_map.with_index do |raw, index|
      next if raw["baseUrl"].blank?

      Track.new(url: raw["baseUrl"], language_code: raw["languageCode"],
                kind: raw["kind"], vss_id: raw["vssId"], index: index)
    end
  end

  # The original language, from the most explicit signal to the weakest: the
  # declared audio language, then the track the page marks as default, then the
  # language of the description (a video's description is nearly always written
  # in the video's own language), and finally the first auto-generated track.
  #
  # The description hint sits above the ASR fallback because the ASR list is a
  # translation set whose order is unrelated to the original: a video in English
  # can list only translated tracks (de, ar, …), and "the first ASR" then names
  # the wrong language. The description is a real signal where the track list is
  # not.
  def original_language(html, description = nil)
    html[DEFAULT_AUDIO_LANGUAGE, 1].presence ||
      default_audio_track_language(html) ||
      description_language(description) ||
      first_asr_language(html)
  end

  # A tiny offline guess at a text's language using function words, enough to
  # tell pt/en/es apart when choosing a track tag. Not a general detector: it
  # returns nil when nothing scores, and the caller then falls back. Using a
  # gem here would be a new dependency for one hint.
  def description_language(text)
    words = text.to_s.downcase.scan(/[[:alpha:]]+/)
    return nil if words.length < MIN_LANGUAGE_WORDS

    scores = LANGUAGE_HINTS.transform_values { |hints| words.count { |word| hints.include?(word) } }
    best, score = scores.max_by { |_, value| value }
    # Ambiguous when nothing matched, or two languages tie, so give no answer.
    return nil if score.zero?

    scores.values.count(score) > 1 ? nil : best
  end

  def default_audio_track_language(html)
    index = html[DEFAULT_AUDIO_TRACK_INDEX, 1]
    return nil if index.blank?

    audio = Array(array_field(html, AUDIO_TRACKS_KEY))[index.to_i]
    audio&.dig("audioTrackId")&.split(".")&.first.presence
  end

  def first_asr_language(html)
    tracks_from(html).find(&:automatic?)&.language_code
  end

  # The value of `"key":` when it is a JSON array, taken by matching brackets
  # with string awareness so a `]` inside a string cannot close it early. Only
  # the array is parsed, never the whole player response.
  def array_field(html, key)
    start = html.index("#{key}:")
    return [] unless start

    open = html.index("[", start)
    return [] unless open

    close = matching_bracket(html, open)
    return [] unless close

    JSON.parse(html[open..close])
  rescue JSON::ParserError, TypeError
    []
  end

  def matching_bracket(text, open)
    depth = 0
    in_string = false
    escaped = false

    index = open
    while index < text.length
      char = text[index]
      if in_string
        if escaped
          escaped = false
        elsif char == "\\"
          escaped = true
        elsif char == '"'
          in_string = false
        end
      else
        case char
        when '"' then in_string = true
        when "[" then depth += 1
        when "]"
          depth -= 1
          return index if depth.zero?
        end
      end
      index += 1
    end

    nil
  end

  # The caption URL is embedded as a JSON string, so `&` arrives as `\u0026`.
  def unescape(value)
    JSON.parse(%("#{value}"))
  rescue JSON::ParserError
    value
  end

  # The text to summarize: the transcript alone when one was obtained, the
  # description only when it was not. The description is a promotional blurb
  # (call-to-action, sponsor, links), not the video's content, so mixing it in
  # would let the model summarize the ad rather than the talk; the description
  # is the fallback for a video with no usable captions.
  #
  # Either way the result is trimmed into MAX_TEXT_CHARS. A long transcript is
  # cut head and tail — the opening carries the thesis and the end carries the
  # conclusion — rather than losing the end.
  def compose(description, transcript)
    source = transcript.presence || description.to_s
    source = source.to_s.strip
    return source if source.length <= MAX_TEXT_CHARS

    head = (MAX_TEXT_CHARS * 0.6).floor
    tail = MAX_TEXT_CHARS - head - TRANSCRIPT_GAP.length
    "#{source[0, head]}#{TRANSCRIPT_GAP}#{source[-tail, tail]}"
  end
end
