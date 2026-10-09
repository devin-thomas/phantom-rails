module Api
  module V1
    class HealthController < ApplicationController
      def show
        db_connected = check_database_connection
        approved_release_active = check_approved_release

        status_code = db_connected ? :ok : :service_unavailable

        render json: {
          status: db_connected ? "ok" : "degraded",
          database: db_connected ? "connected" : "unavailable",
          approved_release: approved_release_active
        }, status: status_code
      end

      private

      def check_database_connection
        ActiveRecord::Base.connection.execute("SELECT 1")
        true
      rescue StandardError
        false
      end

      def check_approved_release
        if defined?(ApprovedRelease) && ActiveRecord::Base.connection.table_exists?(:approved_releases)
          ApprovedRelease.active.exists?
        else
          false
        end
      rescue StandardError
        false
      end
    end
  end
end
