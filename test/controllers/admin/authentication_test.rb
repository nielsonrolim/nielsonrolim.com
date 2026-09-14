require "test_helper"

class Admin::AuthenticationTest < ActionDispatch::IntegrationTest
  # Every route under /admin: the dashboard, the job dashboard, and the reader
  # that is nested underneath it.
  ADMIN_PATHS = %w[
    /admin
    /admin/jobs
    /admin/reader
    /admin/reader/feeds
    /admin/reader/entries
    /admin/reader/clippings
    /admin/reader/newsletters
  ].freeze

  test "asks for credentials when none are sent" do
    with_reader_credentials do
      get admin_root_path

      assert_response :unauthorized
      assert_match(/Basic realm/, response.headers["WWW-Authenticate"].to_s)
    end
  end

  test "rejects the wrong password" do
    with_reader_credentials do
      get admin_root_path, headers: reader_headers("reader", "wrong")

      assert_response :unauthorized
    end
  end

  test "rejects the wrong username" do
    with_reader_credentials do
      get admin_root_path, headers: reader_headers("intruder", "s3cret")

      assert_response :unauthorized
    end
  end

  test "grants access with the right credentials" do
    with_reader_credentials do
      get admin_root_path, headers: reader_headers

      assert_response :success
    end
  end

  test "every admin route is protected, including the nested reader" do
    with_reader_credentials do
      ADMIN_PATHS.each do |path|
        get path
        assert_response :unauthorized, "expected #{path} to require auth"
      end
    end
  end

  test "fails closed when credentials are not configured" do
    without_reader_credentials do
      ADMIN_PATHS.each do |path|
        get path, headers: reader_headers
        assert_response :forbidden, "expected #{path} to be closed when unconfigured"
      end
    end
  end

  test "the public site stays open" do
    without_reader_credentials do
      get "/pt-BR"

      assert_response :success
    end
  end
end
