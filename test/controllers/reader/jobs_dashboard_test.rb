require "test_helper"

class Reader::JobsDashboardTest < ActionDispatch::IntegrationTest
  setup { set_reader_credentials! }
  teardown { restore_reader_credentials! }

  test "requires credentials" do
    get reader_mission_control_jobs_path

    assert_response :unauthorized
  end

  test "renders for an authenticated user" do
    get reader_mission_control_jobs_path, headers: reader_headers

    assert_response :success
    assert_select "title", /Mission control/
    # The engine's own layout and navigation rendered.
    assert_select "body", /Queues/
    assert_select "body", /Failed jobs/
    assert_select "body", /Recurring tasks/
  end

  test "renders the queues tab" do
    get "#{reader_mission_control_jobs_path}/queues", headers: reader_headers

    assert_response :success
    assert_select "body", /Queue/
  end

  test "renders a job status tab" do
    get "#{reader_mission_control_jobs_path}/finished/jobs", headers: reader_headers

    assert_response :success
  end
end
