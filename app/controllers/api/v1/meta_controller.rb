module Api
  module V1
    class MetaController < ApplicationController
      def show
        active_release = ApprovedRelease.active.first

        render json: {
          corpus_revision: ApprovedReleaseManager.current_revision,
          corpus_version: active_release&.corpus_version,
          active_approved_postings: CanonicalPosting.active_approved.count,
          origin_class_counts: origin_counts(active_release),
          available_filters: %w[q company location remote_type employment_type min_salary_usd],
          available_sorts: %w[relevance newest company title],
          disclaimer: "Phantom Rails is an inspectable portfolio search API containing approved sanitized historical and labeled adversarial synthetic records. Real private source emails and candidate records are strictly excluded."
        }
      end

      private

      def origin_counts(release)
        return { "adversarial_synthetic" => 0 } unless release

        counts = {}
        CanonicalPosting.active_approved
                        .joins(source_mentions: :source_record)
                        .group("source_records.origin_class")
                        .count
                        .each do |k, v|
          counts[k] = v
        end
        counts.presence || { "adversarial_synthetic" => release.total_items }
      end
    end
  end
end
