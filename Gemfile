source "https://rubygems.org"

# Pinned Rails and core dependencies
gem "rails", "~> 8.1.4"
gem "pg", "~> 1.5"
gem "puma", ">= 5.0"
gem "bootsnap", require: false

# JSON Schema validation for sanitized batches and releases
gem "json_schemer", "~> 2.3"

# Cross-Origin Resource Sharing
gem "rack-cors"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "brakeman", require: false
end
