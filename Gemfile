source "https://rubygems.org"

ruby File.read(".ruby-version").strip

gem "bridgetown", "~> 2.2.2"
gem "falcon"

gem "bridgetown-seo-tag", "~> 7.0"
gem "bridgetown-sitemap", "~> 3.0"

gem "base64"

# Not the site build's dependencies - used by the wikidata enrichment
# scripts in scripts/. Deliberately not in a :development/:test group:
# Cloudflare Pages' build image runs its automatic `bundle install`
# with BUNDLE_WITHOUT="development test" but doesn't propagate that to
# our separate build command, so `bin/bridgetown build`'s
# `require "bundler/setup"` would try to verify these against the full
# Gemfile.lock and fail with Bundler::GemNotFound, since they were
# never actually installed - confirmed by an actual failed Pages build.
gem "wikidata_adaptor"
gem "dotenv"

# Used by scripts/check_webid.rb to parse the WebID profile as real RDF
# (same reason as above for not being in a :development/:test group).
gem "rdf", "~> 3.3"
gem "rdf-turtle", "~> 3.3"
gem "rdf-isomorphic", "~> 3.3"
gem "ostruct" # rdf requires it; leaves the default gems in Ruby 3.5
