require "json"

module Builders
  # Serialisation helpers for the WebID profile templates in src/webid/.
  # The profile is small enough to template by hand, but every IRI is
  # validated and every literal escaped here, so a stray quote or angle
  # bracket in src/_data/webid.yml fails the build rather than producing
  # invalid (or differently-meaning) RDF.
  class WebidHelpers < SiteBuilder
    # Characters Turtle forbids inside an IRIREF.
    IRI_FORBIDDEN = /[\x00-\x20<>"{}|^`\\]/
    FOAF = "http://xmlns.com/foaf/0.1/".freeze
    SOLID = "http://www.w3.org/ns/solid/terms#".freeze

    def build
      helper "turtle_iri" do |iri|
        "<#{absolute_iri!(iri)}>".html_safe
      end

      helper "turtle_string" do |text|
        escaped = text.to_s.gsub(/[\\"\n\r\t]/) do |char|
          { "\\" => "\\\\", '"' => '\\"', "\n" => "\\n", "\r" => "\\r", "\t" => "\\t" }[char]
        end
        %("#{escaped}").html_safe
      end

      helper "webid_jsonld" do |webid|
        JSON.pretty_generate(jsonld_document(webid)).html_safe
      end
    end

    private

    def absolute_iri!(iri)
      value = iri.to_s
      raise ArgumentError, "Not an absolute IRI: #{value.inspect}" unless value.match?(%r{\Ahttps?://})
      raise ArgumentError, "Illegal character in IRI: #{value.inspect}" if value.match?(IRI_FORBIDDEN)

      value
    end

    # The same statements as profile.ttl.erb. The context is inline, not a
    # remote URL, so readers never need a second fetch to interpret it and
    # it can't change underneath the profile.
    def jsonld_document(webid)
      person = absolute_iri!(webid.person)
      document = absolute_iri!(webid.document)
      iri_term = ->(term) { { "@id" => "foaf:#{term}", "@type" => "@id" } }

      {
        "@context" => {
          "foaf" => FOAF,
          "solid" => SOLID,
          "name" => "foaf:name",
          "maker" => iri_term.("maker"),
          "primaryTopic" => iri_term.("primaryTopic"),
          "isPrimaryTopicOf" => iri_term.("isPrimaryTopicOf"),
          "homepage" => iri_term.("homepage"),
          "img" => iri_term.("img"),
          "account" => iri_term.("account").merge("@container" => "@set"),
          "oidcIssuer" => { "@id" => "solid:oidcIssuer", "@type" => "@id" },
        },
        "@graph" => [
          {
            "@id" => document,
            "@type" => "foaf:PersonalProfileDocument",
            "maker" => person,
            "primaryTopic" => person,
          },
          {
            "@id" => person,
            "@type" => "foaf:Person",
            "name" => webid.name.to_s,
            "homepage" => absolute_iri!(webid.homepage),
            "img" => absolute_iri!(webid.image),
            "oidcIssuer" => absolute_iri!(webid.oidc_issuer),
            "account" => webid.accounts.map { |account| absolute_iri!(account.url) },
            "isPrimaryTopicOf" => document,
          },
        ],
      }
    end
  end
end
