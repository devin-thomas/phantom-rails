class ApplicationController < ActionController::API
  rescue_from ActiveRecord::RecordNotFound, with: :render_not_found
  rescue_from ActionController::ParameterMissing, with: :render_bad_request
  rescue_from PG::ConnectionBad, with: :render_service_unavailable
  rescue_from ActiveRecord::ConnectionNotEstablished, with: :render_service_unavailable

  def method_not_allowed
    render json: {
      error: {
        code: "method_not_allowed",
        message: "HTTP #{request.method} is not allowed on this read-only API endpoint",
        request_id: request.request_id
      }
    }, status: :method_not_allowed
  end

  def route_not_found
    render json: {
      error: {
        code: "not_found",
        message: "Requested endpoint was not found",
        request_id: request.request_id
      }
    }, status: :not_found
  end

  private

  def render_not_found(_exception = nil)
    render json: {
      error: {
        code: "not_found",
        message: "Requested resource was not found in the active approved corpus",
        request_id: request.request_id
      }
    }, status: :not_found
  end

  def render_bad_request(exception)
    render json: {
      error: {
        code: "invalid_parameter",
        message: exception.message,
        request_id: request.request_id
      }
    }, status: :bad_request
  end

  def render_invalid_param(message)
    render json: {
      error: {
        code: "invalid_parameter",
        message: message,
        request_id: request.request_id
      }
    }, status: :bad_request
  end

  def render_service_unavailable(_exception)
    render json: {
      error: {
        code: "service_unavailable",
        message: "Database service is temporarily unavailable. Please retry later.",
        request_id: request.request_id
      }
    }, status: :service_unavailable
  end
end
