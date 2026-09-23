require "test_helper"

class Admin::JobsDashboardTest < ActionDispatch::IntegrationTest
  setup { sign_in_as_admin }
  teardown { sign_out }

  test "renders for an authenticated user" do
    get admin_mission_control_jobs_path

    assert_response :success
    assert_select "title", /Mission control/
    # The engine's own layout and navigation rendered.
    assert_select "body", /Queues/
    assert_select "body", /Failed jobs/
    assert_select "body", /Recurring tasks/
  end

  test "renders the queues tab" do
    get "#{admin_mission_control_jobs_path}/queues"

    assert_response :success
    assert_select "body", /Queue/
  end

  test "renders a job status tab" do
    get "#{admin_mission_control_jobs_path}/finished/jobs"

    assert_response :success
  end
end
