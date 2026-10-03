require "test_helper"

class YtdlpCliTest < ActiveSupport::TestCase
  setup do
    @captions = file_fixture("youtube_captions.json").read
  end

  def cli(runner)
    YtdlpCli.new(runner: runner)
  end

  # --- video id validation ----------------------------------------------------

  test "returns nil for a malformed video id without running the runner" do
    runner = FakeYtdlpRunner.new(subtitles: { "sub.pt.json3" => @captions })

    [ "short", "way-way-too-long-id", "abc def", "../../etc/passwd", "" ].each do |bad|
      assert_nil cli(runner).call(video_id: bad, languages: [ "pt" ]), "expected nil for #{bad.inspect}"
    end

    assert_empty runner.calls
  end

  test "accepts an 11-character URL-safe id" do
    runner = FakeYtdlpRunner.new(subtitles: { "sub.pt.json3" => @captions })

    assert_includes cli(runner).call(video_id: "xG-xACzIJQU", languages: [ "pt" ]), "hoje vamos falar"
  end

  # --- language sanitizing ----------------------------------------------------

  test "drops malformed and exclusion-shaped languages from --sub-langs" do
    runner = FakeYtdlpRunner.new(subtitles: { "sub.pt.json3" => @captions })

    cli(runner).call(video_id: "xG-xACzIJQU", languages: [ "pt", "en\r\nInjected", "-pt", "a*", "en" ])

    langs = runner.last_args.each_cons(2).find { |a, _| a == "--sub-langs" }&.last
    assert_equal "pt,en", langs
  end

  test "deduplicates languages preserving the preference order" do
    runner = FakeYtdlpRunner.new(subtitles: { "sub.en.json3" => @captions })

    cli(runner).call(video_id: "xG-xACzIJQU", languages: [ "pt-BR", "en", "pt", "pt-BR" ])

    langs = runner.last_args.each_cons(2).find { |a, _| a == "--sub-langs" }&.last
    assert_equal "pt-BR,en,pt", langs
  end

  test "caps the language list at eight" do
    runner = FakeYtdlpRunner.new(subtitles: { "sub.l1.json3" => @captions })
    many = (1..12).map { |n| "l#{n}" }

    cli(runner).call(video_id: "xG-xACzIJQU", languages: many)

    langs = runner.last_args.each_cons(2).find { |a, _| a == "--sub-langs" }&.last
    assert_equal many.first(8).join(","), langs
  end

  test "omits --sub-langs when the list is empty after sanitizing" do
    runner = FakeYtdlpRunner.new(subtitles: { "sub.pt.json3" => @captions })

    cli(runner).call(video_id: "xG-xACzIJQU", languages: [ "-pt", "\r\n", "a*" ])

    refute_includes runner.last_args, "--sub-langs"
  end

  # --- command shape ----------------------------------------------------------

  test "builds the yt-dlp argument array with a -- before the URL" do
    runner = FakeYtdlpRunner.new(subtitles: { "sub.pt.json3" => @captions })

    cli(runner).call(video_id: "xG-xACzIJQU", languages: [ "pt" ])

    args = runner.last_args
    assert_equal "--skip-download", args.first
    assert_includes args, "--write-subs"
    assert_includes args, "--write-auto-subs"
    assert_includes args, "--no-playlist"
    assert_equal "json3", args.each_cons(2).find { |a, _| a == "--sub-format" }&.last
    assert_equal "youtube:player_client=android_vr",
                 args.each_cons(2).find { |a, _| a == "--extractor-args" }&.last
    assert_equal "https://www.youtube.com/watch?v=xG-xACzIJQU", args.last
    assert_equal "--", args[-2]
  end

  test "honours YTDLP_PLAYER_CLIENT" do
    with_env("YTDLP_PLAYER_CLIENT" => "web") do
      runner = FakeYtdlpRunner.new(subtitles: { "sub.pt.json3" => @captions })

      cli(runner).call(video_id: "xG-xACzIJQU", languages: [ "pt" ])

      client = runner.last_args.each_cons(2).find { |a, _| a == "--extractor-args" }&.last
      assert_equal "youtube:player_client=web", client
    end
  end

  test "runs in a temp directory that exists during the call and is cleaned up" do
    runner = FakeYtdlpRunner.new(subtitles: { "sub.pt.json3" => @captions })
    existed_during_call = nil
    observed = Object.new.tap do |probe|
      probe.define_singleton_method(:call) do |args, chdir:|
        existed_during_call = Dir.exist?(chdir)
        runner.call(args, chdir: chdir)
      end
    end

    cli(observed).call(video_id: "xG-xACzIJQU", languages: [ "pt" ])

    assert existed_during_call, "the working directory should exist while yt-dlp runs"
    refute Dir.exist?(runner.last_chdir), "the temp directory should be removed afterwards"
  end

  # --- file selection ---------------------------------------------------------

  test "picks the exact language tag, not a prefix match" do
    first = JSON.generate({ "events" => [ { "segs" => [ { "utf8" => "ORIG" } ] } ] })
    other = JSON.generate({ "events" => [ { "segs" => [ { "utf8" => "EN" } ] } ] })
    runner = FakeYtdlpRunner.new(subtitles: { "sub.pt-orig.json3" => first, "sub.en.json3" => other })

    result = cli(runner).call(video_id: "xG-xACzIJQU", languages: [ "pt-orig", "en" ])

    assert_equal "ORIG", result
  end

  test "prefers the higher-ranked language when several files exist" do
    pt = JSON.generate({ "events" => [ { "segs" => [ { "utf8" => "PT" } ] } ] })
    en = JSON.generate({ "events" => [ { "segs" => [ { "utf8" => "EN" } ] } ] })
    runner = FakeYtdlpRunner.new(subtitles: { "sub.pt.json3" => pt, "sub.en.json3" => en })

    assert_equal "PT", cli(runner).call(video_id: "xG-xACzIJQU", languages: [ "pt", "en" ])
  end

  test "falls back to any json3 when no requested language matched" do
    en = JSON.generate({ "events" => [ { "segs" => [ { "utf8" => "EN" } ] } ] })
    runner = FakeYtdlpRunner.new(subtitles: { "sub.en.json3" => en })

    assert_equal "EN", cli(runner).call(video_id: "xG-xACzIJQU", languages: [ "pt" ])
  end

  test "takes the first file when no languages were requested" do
    pt = JSON.generate({ "events" => [ { "segs" => [ { "utf8" => "PT" } ] } ] })
    runner = FakeYtdlpRunner.new(subtitles: { "sub.pt.json3" => pt })

    assert_equal "PT", cli(runner).call(video_id: "xG-xACzIJQU", languages: [])
  end

  test "returns nil when only a non-json3 subtitle was written" do
    runner = FakeYtdlpRunner.new(subtitles: { "sub.pt.vtt" => "WEBVTT\n\n00:00.000 --> 00:01.000\nhi\n" })

    assert_nil cli(runner).call(video_id: "xG-xACzIJQU", languages: [ "pt" ])
  end

  test "returns nil for an empty events array" do
    runner = FakeYtdlpRunner.new(subtitles: { "sub.pt.json3" => '{"events":[]}' })

    assert_nil cli(runner).call(video_id: "xG-xACzIJQU", languages: [ "pt" ])
  end

  test "returns nil for malformed json" do
    runner = FakeYtdlpRunner.new(subtitles: { "sub.pt.json3" => "not json" })

    assert_nil cli(runner).call(video_id: "xG-xACzIJQU", languages: [ "pt" ])
  end

  # --- size cap ---------------------------------------------------------------

  test "reads at most the transport body cap, so a body past it is truncated and unparseable" do
    # A valid json3 body with a huge segment, past the 5 MB cap, is cut before
    # the closing brackets and therefore parses to nil instead of being
    # materialized whole.
    huge = JSON.generate({ "events" => [ { "segs" => [ { "utf8" => "A" * (HttpTransport::MAX_BODY_BYTES + 100) } ] } ] })
    runner = FakeYtdlpRunner.new(subtitles: { "sub.pt.json3" => huge })

    assert_nil cli(runner).call(video_id: "xG-xACzIJQU", languages: [ "pt" ])
  end

  # --- failure handling -------------------------------------------------------

  test "returns nil without raising when the runner exits non-zero" do
    runner = FakeYtdlpRunner.new(success: false, exitstatus: 1)

    assert_nil cli(runner).call(video_id: "xG-xACzIJQU", languages: [ "pt" ])
  end

  test "returns nil without raising on a timeout" do
    runner = FakeYtdlpRunner.new(error: YtdlpCli::TimeoutError.new("too slow"))

    assert_nil cli(runner).call(video_id: "xG-xACzIJQU", languages: [ "pt" ])
  end

  test "returns nil without raising when the binary is missing" do
    runner = FakeYtdlpRunner.new(error: Errno::ENOENT.new("yt-dlp"))

    assert_nil cli(runner).call(video_id: "xG-xACzIJQU", languages: [ "pt" ])
  end

  test "retries once after a 429 and returns the second run's transcript" do
    body = JSON.generate({ "events" => [ { "segs" => [ { "utf8" => "SECOND" } ] } ] })
    runner = FakeYtdlpRunner.new(
      subtitles: { "sub.pt.json3" => body },
      statuses: [ [ false, 1, "ERROR: HTTP Error 429: Too Many Requests" ], [ true, 0, "" ] ]
    )

    # The retry backoff is 3s; skip it in the test.
    result = with_retry_wait(0) do
      cli(runner).call(video_id: "xG-xACzIJQU", languages: [ "pt" ])
    end

    assert_equal "SECOND", result
    assert_equal 2, runner.calls.size
  end

  test "does not retry a non-429 failure" do
    runner = FakeYtdlpRunner.new(success: false, exitstatus: 1, stderr: "ERROR: unable to extract")

    assert_nil cli(runner).call(video_id: "xG-xACzIJQU", languages: [ "pt" ])
    assert_equal 1, runner.calls.size
  end

  test "does not swallow a programming error" do
    # Only expected failures (timeout, missing binary, non-zero exit) are
    # rescued; a bug in the runner must surface, not become "no transcript".
    runner = FakeYtdlpRunner.new(error: NoMethodError.new("undefined method 'foo'"))

    assert_raises(NoMethodError) do
      cli(runner).call(video_id: "xG-xACzIJQU", languages: [ "pt" ])
    end
  end

  # --- flatten_json3 (the shared parse contract) ------------------------------

  test "flatten_json3 collapses whitespace and joins segments" do
    body = JSON.generate({ "events" => [
      { "segs" => [ { "utf8" => "a\n" }, { "utf8" => "b " } ] },
      { "segs" => [ { "utf8" => "c" } ] }
    ] })

    assert_equal "a b c", YoutubeFetcher.flatten_json3(body)
  end

  test "flatten_json3 is nil for malformed or empty input" do
    assert_nil YoutubeFetcher.flatten_json3("nope")
    assert_nil YoutubeFetcher.flatten_json3(nil)
    assert_nil YoutubeFetcher.flatten_json3('{"events":[]}')
  end

  private

  def with_retry_wait(seconds)
    original = YtdlpCli::RETRY_WAIT
    YtdlpCli.send(:remove_const, :RETRY_WAIT)
    YtdlpCli.const_set(:RETRY_WAIT, seconds)
    yield
  ensure
    YtdlpCli.send(:remove_const, :RETRY_WAIT)
    YtdlpCli.const_set(:RETRY_WAIT, original)
  end

  def with_env(vars)
    original = vars.keys.to_h { |key| [ key, ENV[key] ] }
    vars.each { |key, value| ENV[key] = value }
    yield
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
