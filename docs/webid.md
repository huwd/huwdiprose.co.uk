# WebID profile

This site publishes a public [WebID](https://www.w3.org/2005/Incubator/webid/spec/identity/) for Huw Diprose. A WebID is a URL that identifies a person. Software can fetch it to get machine-readable statements about that person.

The profile names a Solid-OIDC issuer for logging in, and a Solid Pod for storage. Neither is run from this repository, and it names a private preferences file in the Pod, as the Solid WebID Profile draft requires. See [what this does not cover](#what-this-does-not-cover).

## Publication contract

| Item | Value |
| --- | --- |
| Person identifier (the WebID) | `https://huwdiprose.co.uk/profile#me` |
| Profile document | `https://huwdiprose.co.uk/profile` |
| Required format | Turtle (`text/turtle`) |
| Other formats | JSON-LD (`application/ld+json`), and HTML for people reading in a browser |
| Source of truth | `src/_data/webid.yml` in this repository |
| Update policy | Changes are made through Git and deployed with the site |

The person identifier is permanent. Access policies and tokens may come to embed this exact string. Do not change its host, path, trailing slash or fragment.

The person and the document are different things. `/profile#me` is Huw; `/profile` is the document describing him. The `#me` fragment is never sent in HTTP requests, so the document must describe the full identifier itself.

### Why this shape

The WebID spec's main example is `https://bob.example.org/profile#me`, and `#me` is the most common fragment among people hosting their own WebID. Tim Berners-Lee and others serve HTML and Turtle from the same URL using content negotiation, which is the approach used here. A hash URI avoids the 303 redirect that a WebID without a fragment would need.

## Public statements

The profile states only:

- the document is a `foaf:PersonalProfileDocument`, made by and about the person
- the person is a `foaf:Person` and a `foaf:Agent`
- their name (`foaf:name`)
- their homepage (`foaf:homepage`)
- their avatar (`foaf:img`), which is the site favicon
- their Solid-OIDC issuer (`solid:oidcIssuer`)
- their Solid Pod (`pim:storage`)
- their preferences file in the Pod (`pim:preferencesFile`), which only they can read
- their Bluesky, X, GitHub and Keybase accounts (`foaf:account`)

Vocabularies: [FOAF](http://xmlns.com/foaf/spec/), [Solid terms](http://www.w3.org/ns/solid/terms) and [PIM space](http://www.w3.org/ns/pim/space).

Only publish statements that are true, public and backed by a working resource. Do not add an email address. Do not add placeholder issuers, storage, inboxes or preferences files to make the profile look like a complete Solid deployment.

## How it is served

| Request | Response |
| --- | --- |
| `GET /profile` asking for `text/turtle` | Turtle |
| `GET /profile` asking for `application/ld+json` | JSON-LD |
| `GET /profile` from a browser (prefers `text/html`) | HTML |
| `GET /profile` with no `Accept` header, `*/*`, or only unsupported types | Turtle |
| `GET /profile.ttl` | Turtle, without negotiation |
| `GET /profile.jsonld` | JSON-LD, without negotiation |
| `GET /profile/` | 301 redirect to `/profile` |
| `GET /profile.html` | 308 redirect to `/profile` (Cloudflare Pages default) |
| `OPTIONS /profile` | 204 with CORS headers, allowing the `Accept`, `Authorization` and `DPoP` request headers |
| Any other method | 405 |

Each format takes the q-value of the most specific matching `Accept` range, as set out in RFC 9110, and the highest wins. Turtle is the format the WebID spec requires, so it wins ties and is the fallback. A request that names only formats the site does not offer, such as `application/rdf+xml`, gets Turtle rather than a 406 error. JSON-LD is there for readers following the Solid WebID Profile draft, which may ask for either Turtle or JSON-LD.

Every response from `/profile` includes:

- `Vary: Accept`
- `Access-Control-Allow-Origin: *`
- `Cache-Control: public, max-age=300`, so changes appear within 5 minutes
- a `Link` header giving the canonical URL and the Turtle and JSON-LD alternates

Solid apps that are logged in send their access token with every request, including the profile read that finds the Pod. That adds `Authorization` and `DPoP` headers, so the browser asks first with a CORS preflight. The preflight for `/profile` allows both. `Access-Control-Allow-Origin` can stay `*`, because these requests carry no cookies.

Only `/profile` answers preflights. Cloudflare Pages serves `/profile.ttl` and `/profile.jsonld` as static files and returns `405` to `OPTIONS`, so a logged-in app can't read them directly. Apps should read the WebID document, `/profile`, anyway.

### Files

| File | Purpose |
| --- | --- |
| `src/_data/webid.yml` | The profile data. Edit this to change the profile. |
| `src/webid/profile.ttl.erb` | Builds `/profile.ttl` from the data |
| `src/webid/profile.jsonld.erb` | Builds `/profile.jsonld` from the same data |
| `src/webid/profile.erb` | Builds the HTML view from the same data |
| `plugins/builders/webid_helpers.rb` | Validates IRIs, escapes Turtle strings and builds the JSON-LD |
| `functions/profile.js` | Cloudflare Pages Function that negotiates `/profile` |
| `src/_headers` | Headers for direct requests to `/profile.ttl` and `/profile.jsonld` |
| `scripts/check_webid.rb` | Checks the contract |

Pages runs the Function for `/profile` only. The rest of the site stays static.

Pages static hosting chooses files by path alone, so without the Function `/profile` would always return HTML and RDF readers could not dereference the WebID. The comment at the top of `functions/profile.js` explains why negotiation runs there rather than in Cloudflare configuration.

### Absolute IRIs

Both RDF files use absolute IRIs throughout. A relative `<#me>` inside `profile.ttl` would identify `profile.ttl#me`, not `/profile#me`. The JSON-LD context is inline, so readers need no second request to interpret it.

## Checking it

`rake verify` runs the WebID checks against the build output and a local `wrangler pages dev` server, after the existing smoke and redirect checks.

To check a Pages preview or the live site:

```sh
bundle exec rake "check_webid[https://huwdiprose.co.uk]"
```

The checks parse the RDF with the Ruby `rdf`, `rdf-turtle` and `json-ld` gems, which are the named reader for this milestone. JSON-LD is parsed with remote document loading refused, so a remote context fails the check. The checks confirm that:

- the graph describes exactly `https://huwdiprose.co.uk/profile#me`
- the graph matches `src/_data/webid.yml`, with no extra or missing statements
- the HTML view shows the same identifier and statements
- the Turtle and JSON-LD, negotiated or fetched directly, are all the same graph
- status codes, content types, `Vary`, CORS (including a preflight that allows `Authorization` and `DPoP`), cache lifetime and redirects are correct
- each `Accept` case gets the right format
- no cookie or login is needed
- the preferences file refuses anonymous reads with a `401` (HTTP checks only). The Pod gives the same `401` for a file that doesn't exist, so this doesn't prove the file is there.

The RDF is parsed against the URL actually fetched. A relative identifier would then resolve to the wrong host on a preview or localhost, and the checks would fail, rather than passing only in production.

## What this does not cover

- **Login beyond one issuer.** The profile names one `solid:oidcIssuer`, `https://id.huwdiprose.co.uk`: a self-hosted instance of the [Solid-OIDC broker](https://github.com/huwd/solid-oidc). It was added once the broker had authenticated this exact WebID. Pocket ID at `auth.huwdiprose.co.uk` is not a Solid-OIDC issuer itself: the broker signs people in through it, then issues the Solid tokens.
- **Storage beyond the Pod root.** The profile names one `pim:storage`, `https://pod.huwdiprose.co.uk/`: a self-hosted [Community Solid Server](https://communitysolidserver.github.io/CommunitySolidServer/) whose root is the storage. Its access rules give this WebID, and nobody else, Read, Write and Control, and it accepts logins from the issuer above. It runs outside this repository. Apart from the preferences file, the profile names nothing in the Pod: no `ldp:inbox` or `solid:publicTypeIndex`. Each needs a real resource in the Pod first.
- **Optional Solid WebID Profile features.** The [Solid WebID Profile draft](https://solid.github.io/webid-profile/) (January 2026) requires a `foaf:Agent` type and exactly one `pim:preferencesFile`, and the profile has both. The preferences file is `https://pod.huwdiprose.co.uk/settings/prefs.ttl`, readable only by this WebID. `check_webid.rb` checks that it refuses anonymous reads, but that can't show it exists: confirm that by reading it as the owner after any change to the Pod. The profile has no type indexes or extended profile documents.
- **Writable profiles.** The profile changes only through Git. Solid apps that expect to edit the profile will not be able to.

Related: [issue 262](https://github.com/huwd/huwdiprose.co.uk/issues/262) and the broader content negotiation experiment in [issue 261](https://github.com/huwd/huwdiprose.co.uk/issues/261).
