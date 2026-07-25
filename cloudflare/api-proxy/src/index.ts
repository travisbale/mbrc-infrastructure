/**
 * Same-origin API proxy for manitobarydercup.com.
 *
 * The SPA (served by Cloudflare Pages) calls relative paths — `/api/auth/*` and
 * `/api/scorecard/*` — so the browser never needs CORS and never sees the Cloud Run
 * URLs. This Worker is bound to the route `manitobarydercup.com/api/*` (see
 * wrangler.toml); everything else falls through to Pages.
 *
 * It mirrors the dev Vite proxy exactly (web/vite.config.ts):
 *   - strips the `/api/<service>` prefix (the Go services are mounted at root), and
 *   - rewrites heimdall's refresh-token cookie Path from `/v1/refresh` (heimdall-
 *     relative) to `/api/auth/v1/refresh`, so the browser sends it back.
 *
 * Because bots hit this edge Worker before any origin, Cloudflare's Bot Fight Mode,
 * WAF, and rate-limit rules filter traffic before it can ever wake Cloud Run.
 */

export interface Env {
  /** Cloud Run URL for heimdall, e.g. https://heimdall-abc123-uc.a.run.app */
  HEIMDALL_URL: string
  /** Cloud Run URL for scorecard, e.g. https://scorecard-abc123-uc.a.run.app */
  SCORECARD_URL: string
  /**
   * Optional shared secret added as `X-Proxy-Secret` on every upstream request so the
   * Cloud Run services can reject anything that didn't come through this Worker. Not yet
   * enforced by the services — see the repo README's "Harden ingress" step.
   */
  PROXY_SECRET?: string
}

interface Route {
  prefix: string
  target: keyof Pick<Env, 'HEIMDALL_URL' | 'SCORECARD_URL'>
  rewriteCookies: boolean
}

// Longest prefixes first so `/api/scorecard` can never be shadowed by a broader rule.
const ROUTES: Route[] = [
  { prefix: '/api/scorecard', target: 'SCORECARD_URL', rewriteCookies: false },
  { prefix: '/api/auth', target: 'HEIMDALL_URL', rewriteCookies: true },
]

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url)
    const route = ROUTES.find(
      (r) => url.pathname === r.prefix || url.pathname.startsWith(r.prefix + '/'),
    )
    if (!route) return new Response('Not found', { status: 404 })

    const origin = env[route.target]
    if (!origin) return new Response('Proxy target not configured', { status: 502 })

    // Strip the `/api/<service>` prefix; the service is mounted at root.
    const upstreamPath = url.pathname.slice(route.prefix.length) || '/'
    const upstreamUrl = origin.replace(/\/$/, '') + upstreamPath + url.search

    const headers = new Headers(request.headers)
    // Let fetch set Host from the Cloud Run URL — forwarding the edge Host would misroute.
    headers.delete('host')
    if (env.PROXY_SECRET) headers.set('X-Proxy-Secret', env.PROXY_SECRET)

    const upstream = await fetch(upstreamUrl, {
      method: request.method,
      headers,
      body: request.method === 'GET' || request.method === 'HEAD' ? undefined : request.body,
      redirect: 'manual',
    })

    const response = new Response(upstream.body, upstream)

    if (route.rewriteCookies) {
      const cookies = upstream.headers.getSetCookie()
      if (cookies.length) {
        response.headers.delete('set-cookie')
        for (const cookie of cookies) {
          response.headers.append('set-cookie', rewriteCookiePath(cookie, route.prefix))
        }
      }
    }

    return response
  },
} satisfies ExportedHandler<Env>

/**
 * Re-anchor a Set-Cookie Path under the proxied prefix:
 *   Path=/v1/refresh -> Path=/api/auth/v1/refresh
 *   Path=/           -> Path=/api/auth
 * Any other Path is left as-is.
 */
function rewriteCookiePath(cookie: string, prefix: string): string {
  return cookie
    .replace(/;\s*Path=\/v1\/refresh\b/i, `; Path=${prefix}/v1/refresh`)
    .replace(/;\s*Path=\/(?=\s*(;|$))/i, `; Path=${prefix}`)
}
