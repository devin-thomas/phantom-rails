require "test_helper"

class DocsControllerTest < ActionDispatch::IntegrationTest
  test "GET /openapi.json returns valid OpenAPI 3.1 specification" do
    get "/openapi.json"

    assert_response :success
    assert_equal "application/json", response.media_type
    spec = JSON.parse(response.body)

    assert_equal "3.1.0", spec["openapi"]
    assert spec["info"].present?
    assert_equal "Phantom Rails Job Search & Provenance API", spec.dig("info", "title")
    assert spec["paths"].present?

    # Verify that each path in the spec corresponds to a real route in Rails
    spec["paths"].each do |path, methods|
      # Verify only GET is advertised
      assert_equal ["get"], methods.keys, "Public API spec must only advertise GET routes: #{path}"

      # Verify the path is mapped in Rails routes
      route_pattern = path.gsub(/\{([^}]+)\}/, ':\1') # e.g. /api/v1/postings/{id} -> /api/v1/postings/:id
      matched = Rails.application.routes.routes.any? do |r|
        r.path.spec.to_s.start_with?(route_pattern)
      end
      assert matched, "OpenAPI path #{path} must exist in Rails routes"
    end

    # Verify components and schemas
    assert spec.dig("components", "schemas", "Posting").present?
    assert spec.dig("components", "schemas", "PostingListResponse").present?
    assert spec.dig("components", "schemas", "ProvenanceResponse").present?
    assert spec.dig("components", "schemas", "ErrorResponse").present?
  end

  test "GET /docs serves interactive documentation without external CDN dependencies" do
    get "/docs"

    assert_response :success
    assert response.body.include?("Phantom Rails API")
    assert response.body.include?("Live Request Console")

    # Verify no external CDN or font tracking links exist
    refute response.body.include?("https://cdn.jsdelivr.net"), "Must not rely on external CDNs"
    refute response.body.include?("https://unpkg.com"), "Must not rely on unpkg"
    refute response.body.include?("https://cdnjs.cloudflare.com"), "Must not rely on cdnjs"
    refute response.body.include?("https://fonts.googleapis.com"), "Must not rely on google fonts"
  end
end
