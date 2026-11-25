# Verifies the WebID publication contract in docs/webid.md.
#
#   ruby scripts/check_webid.rb --build [output]   # built files only
#   ruby scripts/check_webid.rb <base_url>         # a running site
#
# The HTTP mode works against `wrangler pages dev`, a Pages preview or the
# custom domain. The person IRI is always the production one from
# src/_data/webid.yml, whatever host is being checked: the RDF must
# describe https://huwdiprose.co.uk/profile#me even when it's served from
# localhost or a preview URL. So the RDF is parsed against the host
# actually fetched, which makes any relative IRI in it fail this check
# rather than quietly resolving to the right answer in production only.
#
# Reader: the Ruby `rdf`, `rdf-turtle` and `json-ld` gems (versions
# printed on run). JSON-LD is parsed without loading remote documents,
# so the inline context is the only one it can use.

require 'yaml'
require 'net/http'
require 'uri'
require 'rdf'
require 'rdf/turtle'
require 'rdf/isomorphic'
require 'json/ld'

MODEL = YAML.safe_load_file('src/_data/webid.yml')
PERSON = RDF::URI(MODEL.fetch('person'))
DOCUMENT = RDF::URI(MODEL.fetch('document'))
FOAF = RDF::Vocabulary.new('http://xmlns.com/foaf/0.1/')
SOLID = RDF::Vocabulary.new('http://www.w3.org/ns/solid/terms#')
PIM = RDF::Vocabulary.new('http://www.w3.org/ns/pim/space#')

BROWSER_ACCEPT = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'.freeze
TURTLE_ACCEPT = 'text/turtle'.freeze
JSONLD_ACCEPT = 'application/ld+json'.freeze

$failures = 0

def check(description)
  ok = yield
  puts "  #{ok ? 'ok  ' : 'FAIL'} #{description}"
  $failures += 1 unless ok
rescue StandardError => e
  puts "  FAIL #{description} (#{e.class}: #{e.message})"
  $failures += 1
end

def parse_turtle(body, base_uri)
  RDF::Graph.new << RDF::Turtle::Reader.new(body, base_uri: base_uri, validate: true)
end

NO_REMOTE_DOCUMENTS = lambda do |url, **|
  raise JSON::LD::JsonLdError::LoadingDocumentFailed, "refusing to load remote document #{url}"
end

# Parsed to a Hash first: given a string, the reader routes the input
# document itself through the loader, which would trip the block above.
def parse_jsonld(body, base_uri)
  RDF::Graph.new.tap do |graph|
    JSON::LD::API.toRdf(JSON.parse(body), base: base_uri, documentLoader: NO_REMOTE_DOCUMENTS) do |statement|
      graph << statement
    end
  end
end

# The statements src/_data/webid.yml says the profile makes - nothing more.
def expected_graph
  RDF::Graph.new.tap do |g|
    g << [DOCUMENT, RDF.type, FOAF.PersonalProfileDocument]
    g << [DOCUMENT, FOAF.maker, PERSON]
    g << [DOCUMENT, FOAF.primaryTopic, PERSON]
    g << [PERSON, RDF.type, FOAF.Person]
    g << [PERSON, FOAF.name, RDF::Literal(MODEL.fetch('name'))]
    g << [PERSON, FOAF.homepage, RDF::URI(MODEL.fetch('homepage'))]
    g << [PERSON, FOAF.img, RDF::URI(MODEL.fetch('image'))]
    g << [PERSON, SOLID.oidcIssuer, RDF::URI(MODEL.fetch('oidc_issuer'))]
    g << [PERSON, PIM.storage, RDF::URI(MODEL.fetch('storage'))]
    g << [PERSON, FOAF.isPrimaryTopicOf, DOCUMENT]
    MODEL.fetch('accounts').each { |a| g << [PERSON, FOAF.account, RDF::URI(a.fetch('url'))] }
  end
end

def graph_checks(graph, label)
  check("#{label}: describes exactly #{PERSON} as a foaf:Person") do
    graph.has_statement?(RDF::Statement(PERSON, RDF.type, FOAF.Person))
  end
  check("#{label}: #{DOCUMENT} has #{PERSON} as its primary topic") do
    graph.has_statement?(RDF::Statement(DOCUMENT, FOAF.primaryTopic, PERSON))
  end
  check("#{label}: person and document are distinct resources") { PERSON != DOCUMENT }
  check("#{label}: graph matches src/_data/webid.yml exactly (isomorphic)") do
    graph.isomorphic_with?(expected_graph)
  end
end

# Statements visible in the HTML view. Not RDF, so this is the agreement
# check the issue asks for between the alternate representation and the
# model: each public statement appears, and nothing claims a different id.
def html_checks(html, label)
  check("#{label}: shows the WebID #{PERSON}") { html.include?(%(<code class="webid-person">#{PERSON}</code>)) }
  check("#{label}: shows the name") { html.include?(%(<dd class="webid-name">#{MODEL['name']}</dd>)) }
  check("#{label}: shows the avatar") { html.include?(%(class="webid-image" src="#{MODEL['image']}")) }
  check("#{label}: links the homepage") { html.include?(%(class="webid-homepage" href="#{MODEL['homepage']}")) }
  check("#{label}: shows the Solid login issuer") do
    html.include?(%(<code class="webid-oidc-issuer">#{MODEL['oidc_issuer']}</code>))
  end
  check("#{label}: shows the Solid Pod") do
    html.include?(%(<code class="webid-storage">#{MODEL['storage']}</code>))
  end
  MODEL['accounts'].each do |a|
    check("#{label}: links #{a['label']}") { html.include?(%(class="webid-account" href="#{a['url']}")) }
  end
  check("#{label}: advertises the Turtle alternate") do
    html.include?('<link rel="alternate" type="text/turtle" href="/profile.ttl" />')
  end
  check("#{label}: advertises the JSON-LD alternate") do
    html.include?('<link rel="alternate" type="application/ld+json" href="/profile.jsonld" />')
  end
  check("#{label}: canonical is the document URL") do
    html.include?(%(<link rel="canonical" href="#{DOCUMENT}" />))
  end
end

def build_mode(dir)
  puts "Build output: #{dir}"
  ttl = File.read(File.join(dir, 'profile.ttl'))
  turtle = parse_turtle(ttl, 'https://build.invalid/profile.ttl')
  graph_checks(turtle, 'profile.ttl')
  jsonld = parse_jsonld(File.read(File.join(dir, 'profile.jsonld')), 'https://build.invalid/profile.jsonld')
  graph_checks(jsonld, 'profile.jsonld')
  check('profile.jsonld and profile.ttl are the same graph') { jsonld.isomorphic_with?(turtle) }
  html_checks(File.read(File.join(dir, 'profile.html')), 'profile.html')
  check('_headers ships with the build') { File.exist?(File.join(dir, '_headers')) }
  check('functions/profile.js exists') { File.exist?('functions/profile.js') }
end

def request(uri, accept: nil, method: Net::HTTP::Get)
  req = method.new(uri)
  req['Accept'] = accept if accept
  req['User-Agent'] = 'huwdiprose-webid-check'
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 10, read_timeout: 15) do |http|
    http.request(req)
  end
end

# Follows redirects the way an RDF reader would, returning the final
# response and URL. Records each hop so redirect behaviour is visible.
def fetch(url, accept:, limit: 5)
  uri = URI(url)
  hops = []
  loop do
    response = request(uri, accept: accept)
    return [response, uri, hops] unless response.is_a?(Net::HTTPRedirection)
    raise "too many redirects from #{url}" if hops.size >= limit

    hops << "#{response.code} #{uri} -> #{response['location']}"
    uri = URI.join(uri.to_s, response['location'])
  end
end

def negotiated_checks(response, label, type, negotiated: true)
  check("#{label}: 200") { response.code == '200' }
  check("#{label}: Content-Type #{type}") { response['content-type'].to_s.start_with?(type) }
  if negotiated
    check("#{label}: Vary includes Accept") { response['vary'].to_s.split(/,\s*/).map(&:downcase).include?('accept') }
  end
  check("#{label}: public CORS (Access-Control-Allow-Origin: *)") { response['access-control-allow-origin'] == '*' }
  check("#{label}: short public cache lifetime") do
    response['cache-control'].to_s.match?(/\bpublic\b/) &&
      response['cache-control'][/max-age=(\d+)/, 1].to_i.between?(0, 3600)
  end
end

def http_mode(base)
  base = base.chomp('/')
  puts "Site: #{base}"
  doc = "#{base}/profile"

  response, final, hops = fetch(doc, accept: TURTLE_ACCEPT)
  check('Turtle request to /profile is served without redirects') { hops.empty? && final.path == '/profile' }
  negotiated_checks(response, 'Accept: text/turtle', 'text/turtle')
  graph_checks(parse_turtle(response.body, final.to_s), 'Accept: text/turtle')
  check('Turtle response carries no login/challenge cookies') { response.get_fields('set-cookie').nil? }

  jsonld_response, jsonld_final, jsonld_hops = fetch(doc, accept: JSONLD_ACCEPT)
  check('JSON-LD request to /profile is served without redirects') { jsonld_hops.empty? }
  negotiated_checks(jsonld_response, 'Accept: application/ld+json', 'application/ld+json')
  graph_checks(parse_jsonld(jsonld_response.body, jsonld_final.to_s), 'Accept: application/ld+json')

  [['no Accept header', nil], ['Accept: */*', '*/*'], ['Accept: application/rdf+xml (unsupported)', 'application/rdf+xml'],
   ['Accept: text/turtle;q=0.9, text/html;q=0.5', 'text/turtle;q=0.9, text/html;q=0.5'],
   ['Accept: application/ld+json, text/turtle (tie)', 'application/ld+json, text/turtle']].each do |label, accept|
    r = request(URI(doc), accept: accept)
    check("#{label}: gets Turtle") { r.code == '200' && r['content-type'].to_s.start_with?('text/turtle') }
    check("#{label}: Vary includes Accept") { r['vary'].to_s.downcase.include?('accept') }
  end

  html_response = request(URI(doc), accept: BROWSER_ACCEPT)
  negotiated_checks(html_response, 'browser Accept', 'text/html')
  html_checks(html_response.body, 'browser Accept')
  weighted = request(URI(doc), accept: 'text/turtle;q=0.5, text/html')
  check('Accept: text/turtle;q=0.5, text/html prefers HTML') { weighted['content-type'].to_s.start_with?('text/html') }
  weighted_jsonld = request(URI(doc), accept: 'text/turtle;q=0.5, application/ld+json')
  check('Accept: text/turtle;q=0.5, application/ld+json prefers JSON-LD') do
    weighted_jsonld['content-type'].to_s.start_with?('application/ld+json')
  end

  static, = fetch("#{base}/profile.ttl", accept: '*/*')
  negotiated_checks(static, '/profile.ttl', 'text/turtle', negotiated: false)
  check('/profile.ttl is the same graph as negotiated /profile') do
    parse_turtle(static.body, "#{base}/profile.ttl").isomorphic_with?(parse_turtle(response.body, final.to_s))
  end
  static_jsonld, = fetch("#{base}/profile.jsonld", accept: '*/*')
  negotiated_checks(static_jsonld, '/profile.jsonld', 'application/ld+json', negotiated: false)
  check('/profile.jsonld is the same graph as negotiated Turtle') do
    parse_jsonld(static_jsonld.body, "#{base}/profile.jsonld").isomorphic_with?(parse_turtle(response.body, final.to_s))
  end

  avatar = request(URI("#{base}#{URI(MODEL['image']).path}"), accept: 'image/*')
  check('avatar image resolves as an image') { avatar.code == '200' && avatar['content-type'].to_s.start_with?('image/') }

  slash = request(URI("#{doc}/"), accept: TURTLE_ACCEPT)
  check('/profile/ redirects permanently to /profile') do
    slash.code == '301' && URI.join("#{doc}/", slash['location']).path == '/profile'
  end
  html_alias = request(URI("#{base}/profile.html"), accept: BROWSER_ACCEPT)
  check('/profile.html redirects to /profile') do
    html_alias.is_a?(Net::HTTPRedirection) && URI.join(doc, html_alias['location']).path == '/profile'
  end

  options = request(URI(doc), method: Net::HTTP::Options)
  check('CORS preflight (OPTIONS) succeeds') { %w[200 204].include?(options.code) && options['access-control-allow-origin'] == '*' }
end

puts "Reader: rdf #{RDF::VERSION}, rdf-turtle #{RDF::Turtle::VERSION}, json-ld #{JSON::LD::VERSION}"
if ARGV[0] == '--build'
  build_mode(ARGV[1] || 'output')
else
  http_mode(ARGV[0] || 'http://localhost:8788')
end

if $failures.zero?
  puts 'WebID checks passed.'
else
  abort "#{$failures} WebID check(s) failed."
end
