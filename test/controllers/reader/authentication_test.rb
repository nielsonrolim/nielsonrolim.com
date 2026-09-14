require "test_helper"

class Reader::AuthenticationTest < ActionDispatch::IntegrationTest
  READER_PATHS = %w[/reader /reader/feeds /reader/clippings /reader/newsletters /reader/jobs].freeze

  test "asks for credentials when none are sent" do
    with_reader_credentials do
      get reader_entries_path

      assert_response :unauthorized
      assert_match(/Basic realm/, response.headers["WWW-Authenticate"].to_s)
    end
  end

  test "rejects the wrong password" do
    with_reader_credentials do
      get reader_entries_path, headers: reader_headers("reader", "wrong")

      assert_response :unauthorized
    end
  end

  test "rejects the wrong username" do
    with_reader_credentials do
      get reader_entries_path, headers: reader_headers("intruder", "s3cret")

      assert_response :unauthorized
    end
  end

  test "grants access with the right credentials" do
    with_reader_credentials do
      get reader_entries_path, headers: reader_headers

      assert_response :success
    end
  end

  test "every reader route is protected" do
    with_reader_credentials do
      READER_PATHS.each do |path|
        get path
        assert_response :unauthorized, "expected #{path} to require auth"
      end
    end
  end

  test "fails closed when credentials are not configured" do
    without_reader_credentials do
      get reader_entries_path, headers: reader_headers

      assert_response :forbidden
    end
  end

  test "the public site stays open" do
    without_reader_credentials do
      get "/pt-BR"

      assert_response :success
    end
  end
end
