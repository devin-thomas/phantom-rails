class DocsController < ActionController::API
  def openapi
    file_path = Rails.root.join("public", "openapi.json")
    if File.exist?(file_path)
      render json: File.read(file_path, encoding: "UTF-8")
    else
      render json: { error: { code: "not_found", message: "OpenAPI specification not found" } }, status: :not_found
    end
  end

  def index
    file_path = Rails.root.join("public", "docs.html")
    if File.exist?(file_path)
      render html: File.read(file_path, encoding: "UTF-8").html_safe, content_type: "text/html; charset=utf-8"
    else
      render plain: "Interactive documentation not found", status: :not_found
    end
  end
end
