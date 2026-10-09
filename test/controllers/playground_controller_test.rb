require "test_helper"

class PlaygroundControllerTest < ActionDispatch::IntegrationTest
  test "GET /playground serves accessible search playground without external CDN dependencies" do
    get "/playground"

    assert_response :success
    assert_equal "text/html", response.media_type

    body = response.body
    assert body.include?("Phantom Rails Search Playground")
    assert body.include?("Keywords (q)")
    assert body.include?("Remote Type")
    assert body.include?("Provenance Inspection")

    # Verify accessibility features
    assert body.include?('aria-live="polite"'), "Must include live region for screen readers"
    assert body.include?("prefers-reduced-motion"), "Must support reduced motion preference"
    assert body.include?("viewport"), "Must include responsive viewport meta"

    # Verify zero external dependencies
    refute body.include?("https://cdn.jsdelivr.net"), "Must not rely on external CDNs"
    refute body.include?("https://unpkg.com"), "Must not rely on unpkg"
    refute body.include?("https://cdnjs.cloudflare.com"), "Must not rely on cdnjs"
    refute body.include?("https://fonts.googleapis.com"), "Must not rely on google fonts"
  end
end
