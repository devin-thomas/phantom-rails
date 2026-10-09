class PlaygroundController < ActionController::API
  def index
    file_path = Rails.root.join("public", "playground.html")
    if File.exist?(file_path)
      render html: File.read(file_path, encoding: "UTF-8").html_safe, content_type: "text/html; charset=utf-8"
    else
      render plain: "Search playground not found", status: :not_found
    end
  end
end
