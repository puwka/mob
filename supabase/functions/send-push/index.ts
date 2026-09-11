import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.1'

const PUSH_SECRET = Deno.env.get('PUSH_HOOK_SECRET') ?? ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const FIREBASE_SA_JSON = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON') ?? ''

type ServiceAccount = {
  project_id: string
  client_email: string
  private_key: string
}

type PushJob = {
  id: string
  user_id: string
  title: string
  body: string
  data: Record<string, string>
}

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

function assertSecret(req: Request) {
  const header = req.headers.get('x-push-secret') ?? ''
  if (!PUSH_SECRET || header !== PUSH_SECRET) {
    throw new Response(JSON.stringify({ error: 'unauthorized' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    })
  }
}

function parseServiceAccount(): ServiceAccount {
  if (!FIREBASE_SA_JSON) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT_JSON is not set')
  }
  const parsed = JSON.parse(FIREBASE_SA_JSON) as ServiceAccount
  if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
    throw new Error('Invalid FIREBASE_SERVICE_ACCOUNT_JSON')
  }
  parsed.private_key = parsed.private_key.replace(/\\n/g, '\n')
  return parsed
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '')
  const raw = atob(b64)
  const buf = new Uint8Array(raw.length)
  for (let i = 0; i < raw.length; i++) buf[i] = raw.charCodeAt(i)
  return buf.buffer
}

function base64Url(data: ArrayBuffer | Uint8Array | string): string {
  let bytes: Uint8Array
  if (typeof data === 'string') {
    bytes = new TextEncoder().encode(data)
  } else if (data instanceof Uint8Array) {
    bytes = data
  } else {
    bytes = new Uint8Array(data)
  }
  let str = ''
  for (const b of bytes) str += String.fromCharCode(b)
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  const header = base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const claim = base64Url(
    JSON.stringify({
      iss: sa.client_email,
      sub: sa.client_email,
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
    }),
  )
  const unsigned = `${header}.${claim}`
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned),
  )
  const jwt = `${unsigned}.${base64Url(sig)}`

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })
  if (!res.ok) {
    throw new Error(`OAuth token failed: ${await res.text()}`)
  }
  const body = await res.json()
  return body.access_token as string
}

async function sendFcm(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
) {
  const stringData: Record<string, string> = {}
  for (const [k, v] of Object.entries(data ?? {})) {
    if (v == null) continue
    stringData[k] = String(v)
  }

  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data: stringData,
          android: {
            priority: 'HIGH',
            notification: {
              channel_id: 'moystrikbol_default',
              sound: 'default',
            },
          },
          apns: {
            payload: {
              aps: {
                sound: 'default',
                badge: 1,
              },
            },
          },
        },
      }),
    },
  )

  if (res.ok) return { ok: true as const }

  const text = await res.text()
  // Drop invalid tokens
  const invalid =
    text.includes('UNREGISTERED') ||
    text.includes('INVALID_ARGUMENT') ||
    text.includes('NOT_FOUND')
  return { ok: false as const, text, invalid }
}

Deno.serve(async (req) => {
  try {
    if (req.method !== 'POST') {
      return jsonResponse({ error: 'method_not_allowed' }, 405)
    }
    assertSecret(req)

    if (!SUPABASE_URL || !SERVICE_ROLE) {
      return jsonResponse({ error: 'supabase_env_missing' }, 500)
    }

    const sa = parseServiceAccount()
    const accessToken = await getAccessToken(sa)
    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE)

    const payload = await req.json().catch(() => ({}))
    const jobId = typeof payload.job_id === 'string' ? payload.job_id : null
    const drain = payload.mode === 'drain' || !jobId

    let jobs: PushJob[] = []
    if (jobId) {
      const { data, error } = await supabase
        .from('push_jobs')
        .select('id, user_id, title, body, data')
        .eq('id', jobId)
        .is('processed_at', null)
        .maybeSingle()
      if (error) throw error
      if (data) jobs = [data as PushJob]
    } else if (drain) {
      const { data, error } = await supabase
        .from('push_jobs')
        .select('id, user_id, title, body, data')
        .is('processed_at', null)
        .order('created_at', { ascending: true })
        .limit(100)
      if (error) throw error
      jobs = (data ?? []) as PushJob[]
    }

    let sent = 0
    let failed = 0

    for (const job of jobs) {
      const { data: tokens, error: tokenErr } = await supabase
        .from('user_push_tokens')
        .select('token')
        .eq('user_id', job.user_id)
      if (tokenErr) {
        await supabase
          .from('push_jobs')
          .update({ processed_at: new Date().toISOString(), error: tokenErr.message })
          .eq('id', job.id)
        failed++
        continue
      }

      if (!tokens || tokens.length === 0) {
        await supabase
          .from('push_jobs')
          .update({
            processed_at: new Date().toISOString(),
            error: 'no_tokens',
          })
          .eq('id', job.id)
        continue
      }

      const data =
        job.data && typeof job.data === 'object'
          ? (job.data as Record<string, string>)
          : {}

      let jobError: string | null = null
      for (const row of tokens) {
        const result = await sendFcm(
          accessToken,
          sa.project_id,
          row.token,
          job.title,
          job.body,
          data,
        )
        if (result.ok) {
          sent++
        } else {
          failed++
          jobError = result.text
          if (result.invalid) {
            await supabase
              .from('user_push_tokens')
              .delete()
              .eq('token', row.token)
          }
        }
      }

      await supabase
        .from('push_jobs')
        .update({
          processed_at: new Date().toISOString(),
          error: jobError,
        })
        .eq('id', job.id)
    }

    return jsonResponse({ ok: true, jobs: jobs.length, sent, failed })
  } catch (e) {
    if (e instanceof Response) return e
    console.error(e)
    return jsonResponse(
      { error: e instanceof Error ? e.message : String(e) },
      500,
    )
  }
})
