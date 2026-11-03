// ZenMusic · vorlon-dev
//
// Cloudflare Pages Function: forwards /api/* to the JioSaavn API worker so
// the web player can call it from the same origin (no CORS needed).
// Only GET is allowed and only one upstream host is ever contacted.

const UPSTREAM = 'https://jiosaavn-api.vorlon-revora.workers.dev';

export async function onRequest({ request }) {
  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: cors() });
  }
  if (request.method !== 'GET') {
    return new Response('Method not allowed', { status: 405, headers: cors() });
  }

  const url = new URL(request.url);
  const upstream = new URL(UPSTREAM + url.pathname + url.search);

  try {
    const res = await fetch(upstream.toString(), {
      headers: { Accept: 'application/json' },
      cf: { cacheTtl: 300, cacheEverything: true },
    });
    const headers = new Headers(cors());
    headers.set('Content-Type', res.headers.get('Content-Type') || 'application/json');
    headers.set('Cache-Control', 'public, max-age=300');
    return new Response(res.body, { status: res.status, headers });
  } catch (_) {
    return new Response(JSON.stringify({ error: 'upstream unavailable' }), {
      status: 502,
      headers: { ...cors(), 'Content-Type': 'application/json' },
    });
  }
}

function cors() {
  return { 'Access-Control-Allow-Origin': '*' };
}
