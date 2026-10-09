module Api
  module V1
    class PostingsController < ApplicationController
      def index
        result = SearchPostings.call(search_params)

        unless result.success?
          status = case result.error_code
                   when "cursor_expired" then :gone
                   when "stale_cursor" then :conflict
                   else :bad_request
                   end
          render json: {
            error: {
              code: result.error_code,
              message: result.error_message,
              request_id: request.request_id
            }
          }, status: status and return
        end

        render json: {
          data: PostingSerializer.render_many(result.postings, scores: result.scores),
          page: {
            limit: result.limit,
            next_cursor: result.next_cursor,
            corpus_revision: result.corpus_revision
          },
          meta: {
            sort: result.sort,
            query: result.query
          }
        }
      end

      def show
        posting = CanonicalPosting.active_approved
                                  .includes(source_mentions: :source_record)
                                  .find_by(public_id: params[:id])

        if posting.nil?
          render_not_found and return
        end

        render json: {
          data: PostingSerializer.render_one(posting)
        }
      end

      def provenance
        posting = CanonicalPosting.active_approved
                                  .includes(source_mentions: :source_record, field_selections: { source_revision: :source_mention })
                                  .find_by(public_id: params[:id])

        if posting.nil?
          render_not_found and return
        end

        render json: {
          data: PostingSerializer.render_provenance(posting)
        }
      end

      private

      def search_params
        params.permit(:q, :company, :location, :remote_type, :employment_type, :min_salary_usd, :sort, :limit, :cursor).to_h.symbolize_keys
      end
    end
  end
end
