require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  setup { set_reader_credentials! }
  teardown { restore_reader_credentials! }

  test "requires credentials" do
    get admin_root_path

    assert_response :unauthorized
  end

  test "shows the totals" do
    get admin_root_path, headers: reader_headers

    assert_response :success
    assert_select "dt", /fontes/
    assert_select "dt", /entradas/
    assert_select "dt", /na fila/
    assert_select "dt", /assinantes/

    assert_select "dd", count: 4
    assert_select "dd", Feed.count.to_s
    assert_select "dd", Entry.count.to_s
    assert_select "dd", Clipping.unsent.count.to_s
    assert_select "dd", Subscriber.count.to_s
  end

  test "shows the top-level navigation with the section links" do
    get admin_root_path, headers: reader_headers

    assert_response :success
    assert_select "nav a[href=?]", admin_root_path
    assert_select "nav a[href=?]", reader_root_path
    assert_select "nav a[href=?]", admin_subscribers_path
    assert_select "nav a[href=?]", admin_mission_control_jobs_path
    assert_select "nav", /\[painel\]/
    assert_select "nav", /\[leitor\]/
    assert_select "nav", /\[inscritos\]/
    assert_select "nav", /\[jobs\]/
  end

  test "does not render the reader sub-navigation outside the reader" do
    get admin_root_path, headers: reader_headers

    assert_select "nav", text: /\[entradas\]/, count: 0
  end

  test "summarises the latest issue" do
    get admin_root_path, headers: reader_headers

    assert_response :success
    assert_select "body", /Última edição: #{Regexp.escape(newsletters(:last_week).subject)}/
  end

  test "says so when no issue has been sent" do
    Newsletter.destroy_all

    get admin_root_path, headers: reader_headers

    assert_response :success
    assert_select "body", /Nenhuma edição enviada ainda/
  end
end
