module Builders
  # Turtle serialisation helpers for src/profile.ttl.erb. The profile is
  # small enough to template by hand, but every IRI and literal still goes
  # through these so a stray quote or angle bracket in src/_data/webid.yml
  # can't produce invalid (or differently-meaning) Turtle.
  class WebidHelpers < SiteBuilder
    # Characters Turtle forbids inside an IRIREF.
    IRI_FORBIDDEN = /[\x00-\x20<>"{}|^`\\]/

    def build
      helper "turtle_iri" do |iri|
        value = iri.to_s
        raise ArgumentError, "Not an absolute IRI: #{value.inspect}" unless value.match?(%r{\Ahttps?://})
        raise ArgumentError, "Illegal character in IRI: #{value.inspect}" if value.match?(IRI_FORBIDDEN)

        "<#{value}>".html_safe
      end

      helper "turtle_string" do |text|
        escaped = text.to_s.gsub(/[\\"\n\r\t]/) do |char|
          { "\\" => "\\\\", '"' => '\\"', "\n" => "\\n", "\r" => "\\r", "\t" => "\\t" }[char]
        end
        %("#{escaped}").html_safe
      end
    end
  end
end
