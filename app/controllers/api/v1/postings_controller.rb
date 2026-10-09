module Api
  module V1
    class PostingsController < ApplicationController
      def index
        limit = 20
        if params[:limit].present?
          begin
            parsed_limit = Integer(params[:limit])
            if parsed_limit < 1 || parsed_limit > 50
              render_invalid_param("limit must be from 1 to 50") and return
            end
            limit = parsed_limit
          rescue ArgumentError
            render_invalid_param("limit must be from 1 to 50") and return
          end
        end

        scope = CanonicalPosting.active_approved.includes(source_mentions: :source_record)
        postings = scope.order(created_at: :desc, id: :desc).limit(limit)

        render json: {
          data: PostingSerializer.render_many(postings),
          page: {
            limit: limit,
            next_cursor: nil,
            corpus_revision: ApprovedReleaseManager.current_revision
          },
          meta: {
            sort: "relevance",
            query: params[:q].presence
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
    end
  end
end
