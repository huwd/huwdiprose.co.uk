# For technical reasons, this file is *NOT* reloaded automatically when you use
# `bin/bridgetown start`. If you change this file, please restart the server process.
#
# For reloadable site metadata like title, SEO description, social media
# handles, etc., take a look at `src/_data/site_metadata.yml`

Bridgetown.configure do |config|
  # The base hostname & protocol for your site, e.g. https://example.com
  url "https://huwdiprose.co.uk"

  # Available options are `erb` (default), `serbea`, or `liquid`
  template_engine "erb"

  # See list of timezone values here:
  # https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
  timezone "UTC"

  # Ports of jekyll-seo-tag and jekyll-sitemap. Site-wide metadata for
  # the SEO tag lives in src/_data/site_metadata.yml, not here.
  init :"bridgetown-seo-tag"
  init :"bridgetown-sitemap"

  # default_locale is already "en" out of the box (matches the Jekyll
  # site's hardcoded <html lang="en">) - left unset deliberately, since
  # setting it explicitly here switches Bridgetown into locale-prefixed
  # output paths (output/en/... instead of output/...), which this
  # single-language site doesn't want.

  # bridgetown-seo-tag's og:locale comes from site["lang"], which (via
  # Drops::SiteDrop's fallback_data delegation) resolves to
  # site.config["lang"] - a build config value, not site_metadata.yml
  # data, despite reading like site metadata.
  lang "en_GB"

  # Bridgetown copies _redirects through by default, but not Cloudflare
  # Pages' other underscore-prefixed control file.
  include "_headers"

  # Custom collections, ported from Jekyll's _config.yml. :books and
  # :reviews intentionally share a permalink - book reviews and
  # multi-book reviews both publish under /review/book/.
  #
  # Uses :slug, not :title: :title slugifies data.title (the front-matter
  # field), but Jekyll's :title/:path placeholders are filename-based -
  # see plugins/builders/filename_derived_defaults.rb, which sets
  # data.slug from the filename so :slug resolves the same way Jekyll's
  # URLs did.
  collections do
    books do
      output true
      permalink "/review/book/:year/:month/:day/:slug/"
    end

    reviews do
      output true
      permalink "/review/book/:year/:month/:day/:slug/"
    end

    blogs do
      output true
      permalink "/blog/:year/:month/:day/:slug/"
    end

    # :path (not :name) strips any leading YYYY-MM-DD- from the filename
    # unconditionally (Bridgetown::Resource::Base::DATE_FILENAME_MATCHER,
    # no per-collection opt-out) - that would silently change every
    # existing /weeknotes/YYYY-MM-DD-slug/ URL. :name doesn't strip it.
    weeknotes do
      output true
      permalink "/weeknotes/:name/"
    end
  end

  # Every book defaults to the `book` layout, same as Jekyll's
  # `defaults:` block.
  config.defaults << {
    scope: { collection: :books },
    values: { layout: :book },
  }

  # bridgetown-seo-tag resolves <meta name="author">/twitter:creator from
  # page["author"] || page["authors"].first || site author - books/reviews
  # set `authors:` for the book's own author (bibliographic data), which
  # otherwise wins that lookup and produces things like
  # <meta name="author" content="Helen Macdonald"> and a malformed
  # twitter:creator (no real handle known for most book authors). Explicit
  # page["author"] takes priority over page["authors"], so this default
  # makes every book/review page correctly attribute its SEO author meta
  # to the actual page author (Huw), without touching individual files.
  seo_author_default = { author: { name: "Huw Diprose", twitter: "huwdiprose" } }
  config.defaults << { scope: { collection: :books }, values: seo_author_default }
  config.defaults << { scope: { collection: :reviews }, values: seo_author_default }

  # Sitewide default og:image/twitter:image for bridgetown-seo-tag - without
  # this, seo_tag.image is never set, so og:image is absent from every page
  # and the Twitter card silently degrades from summary_large_image to a
  # bare summary. Per-page `image:` front matter (none currently set) would
  # still take priority over this.
  config.defaults << {
    scope: { path: "" },
    values: { image: "/images/social-card.png" },
  }
end
