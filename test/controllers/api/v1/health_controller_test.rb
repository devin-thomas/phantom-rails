require "test_helper"

class Api::V1::HealthControllerTest < ActionDispatch::IntegrationTest
  test "GET /api/v1/health returns 200 ok when database is available" do
    get api_v1_health_url
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal "ok", json["status"]
    assert_equal "connected", json["database"]
    assert_includes [true, false], json["approved_release"]

    # Verify no sensitive data is leaked
    assert_nil json["password"]
    assert_nil json["database_url"]
    assert_nil json["host"]
    assert_nil json["username"]
    assert_nil json["secret_key_base"]
  end

  test "GET /api/v1/health returns 503 service unavailable when database fails" do
    Api::V1::HealthController.any_instance.stubs(:check_database_connection).returns(false) rescue nil

    # Test failure mode directly by simulating database disconnection
    original_method = Api::V1::HealthController.instance_method(:check_database_connection)
    begin
      Api::V1::HealthController.define_method(:check_database_connection) { false }
      get api_v1_health_url
      assert_response :service_unavailable

      json = JSON.parse(response.body)
      assert_equal "degraded", json["status"]
      assert_equal "unavailable", json["database"]
    ensure
      Api::V1::HealthController.define_method(:check_database_connection, original_method)
    end
  end
end
