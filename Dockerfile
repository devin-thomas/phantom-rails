ARG RUBY_VERSION=3.4.11
FROM docker.io/library/ruby:$RUBY_VERSION-slim

WORKDIR /rails

# Install system dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      curl \
      git \
      libpq-dev \
      pkg-config \
      postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV BUNDLE_PATH="/usr/local/bundle" \
    RAILS_LOG_TO_STDOUT="true"

# Install gems
COPY Gemfile Gemfile.lock* ./
RUN bundle install

# Copy application files
COPY . .

# Normalize line endings and file permissions on scripts
RUN sed -i 's/\r$//' bin/* 2>/dev/null || true && \
    chmod +x bin/* 2>/dev/null || true

EXPOSE 3000

ENTRYPOINT ["/rails/bin/docker-entrypoint"]
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
