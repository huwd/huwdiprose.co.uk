// Content negotiation for the WebID profile document at /profile, whose
// person identifier is https://huwdiprose.co.uk/profile#me. See
// docs/webid.md for the publication contract.
//
// Why a Function: readers dereference the WebID by requesting /profile
// (the #me fragment is never sent) with Accept: text/turtle or
// application/ld+json, and expect RDF back from that exact URL. Pages
// static hosting picks files by path alone, so without this /profile
// would always return HTML. _redirects and _headers match paths, not
// request headers. Zone-level rules can match headers, but they can't
// weigh q-values and belong to the shared Cloudflare config, not this
// repo. Cloudflare's Vary support (Cache Rules) only caches the variants
// an origin chooses; it doesn't choose. This Function is that origin.
// It sends Vary: Accept on every response, errors included, so caches
// keep the variants apart.
//
// File-based routing means this Function runs for /profile only; every
// other URL on the site stays a plain static asset. Both variants are
// built by Bridgetown from src/_data/webid.yml and fetched via
// env.ASSETS, so this file never contains profile data itself.
//
// Selection: each variant takes the q-value of the most specific Accept
// range that matches it (RFC 9110 section 12.5.1). The highest q wins.
// Ties go to the earlier variant below, so Turtle - the one format the
// WebID spec requires - wins them. Turtle is also the fallback when the
// header is missing, a bare */*, or names only formats we don't offer.
// JSON-LD is for readers following the Solid WebID Profile draft, which
// may ask for text/turtle or application/ld+json. A browser's Accept
// lists text/html explicitly and */* at a lower q, so it gets HTML.
//
// Headers are set here, not in _headers: Pages doesn't apply _headers to
// Function responses.

const VARIANTS = [
  // Listed in tie-break order.
  { type: 'text/turtle', asset: '/profile.ttl', contentType: 'text/turtle; charset=utf-8' },
  { type: 'application/ld+json', asset: '/profile.jsonld', contentType: 'application/ld+json; charset=utf-8' },
  { type: 'text/html', asset: '/profile', contentType: 'text/html; charset=utf-8' },
];

const CACHE_CONTROL = 'public, max-age=300';

export function parseAccept(header) {
  if (!header || !header.trim()) return [];

  return header.split(',').flatMap((part) => {
    const [range, ...params] = part.trim().split(';').map((s) => s.trim());
    if (!/^[^/\s]+\/[^/\s]+$/.test(range)) return [];

    let q = 1;
    for (const param of params) {
      const [key, value] = param.split('=').map((s) => s.trim());
      if (key.toLowerCase() === 'q') {
        q = Number.parseFloat(value);
        if (!Number.isFinite(q) || q < 0 || q > 1) return [];
      }
    }
    return [{ range: range.toLowerCase(), q }];
  });
}

function specificity(range, type) {
  if (range === type) return 3;
  const [rangeMain, rangeSub] = range.split('/');
  if (rangeSub === '*' && rangeMain === type.split('/')[0]) return 2;
  if (range === '*/*') return 1;
  return 0;
}

function qualityFor(type, ranges) {
  let best = { specificity: 0, q: 0 };
  for (const { range, q } of ranges) {
    const s = specificity(range, type);
    if (s > best.specificity) best = { specificity: s, q };
  }
  return best.q;
}

export function selectVariant(acceptHeader) {
  const ranges = parseAccept(acceptHeader);
  if (ranges.length === 0) return VARIANTS[0];

  let chosen = VARIANTS[0];
  let chosenQ = qualityFor(chosen.type, ranges);
  for (const variant of VARIANTS.slice(1)) {
    const q = qualityFor(variant.type, ranges);
    if (q > chosenQ) {
      chosen = variant;
      chosenQ = q;
    }
  }
  return chosen;
}

function commonHeaders(headers) {
  headers.set('Vary', 'Accept');
  headers.set('Access-Control-Allow-Origin', '*');
  headers.set('Access-Control-Expose-Headers', 'Content-Type, Link, Vary, ETag');
  // set, not append: the asset response already carries _headers' Link.
  headers.set(
    'Link',
    '</profile>; rel="canonical", ' +
      '</profile.ttl>; rel="alternate"; type="text/turtle", ' +
      '</profile.jsonld>; rel="alternate"; type="application/ld+json"',
  );
  return headers;
}

export async function onRequest({ request, env }) {
  const method = request.method.toUpperCase();
  const url = new URL(request.url);

  // Pages routes /profile/ here too. One document URL only: redirect it,
  // so nothing can come to depend on a second spelling.
  if (url.pathname !== '/profile') {
    return new Response(null, {
      status: 301,
      headers: commonHeaders(new Headers({ Location: `/profile${url.search}` })),
    });
  }

  if (method === 'OPTIONS') {
    const headers = commonHeaders(new Headers());
    headers.set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
    headers.set('Access-Control-Allow-Headers', 'Accept');
    headers.set('Access-Control-Max-Age', '86400');
    return new Response(null, { status: 204, headers });
  }

  if (method !== 'GET' && method !== 'HEAD') {
    const headers = commonHeaders(new Headers({ Allow: 'GET, HEAD, OPTIONS' }));
    return new Response('Method Not Allowed\n', { status: 405, headers });
  }

  const variant = selectVariant(request.headers.get('Accept'));
  const assetResponse = await env.ASSETS.fetch(new URL(variant.asset, request.url), { method });

  if (!assetResponse.ok) {
    // Surface a broken build loudly rather than serving the wrong thing.
    return new Response(`Profile variant ${variant.asset} unavailable\n`, {
      status: 502,
      headers: commonHeaders(new Headers({ 'Content-Type': 'text/plain; charset=utf-8' })),
    });
  }

  const headers = commonHeaders(new Headers(assetResponse.headers));
  headers.set('Content-Type', variant.contentType);
  headers.set('Cache-Control', CACHE_CONTROL);

  return new Response(method === 'HEAD' ? null : assetResponse.body, { status: 200, headers });
}
