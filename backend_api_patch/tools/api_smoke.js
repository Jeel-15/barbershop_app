#!/usr/bin/env node
/**
 * Smoke + timing test for the Rosenthal mobile API (v1).
 *
 *   node api_smoke.js <baseUrl> <adminEmail> <adminPassword> <staffEmail> <staffPassword>
 *   e.g. node api_smoke.js http://localhost/rosen_barber/public/api/v1 admin@x.com pw staff@x.com pw
 *
 * Exits with code 1 if any check fails. Needs Node 18+ (built-in fetch).
 * The rate-limit check runs LAST because it temporarily locks the login for ~1 minute.
 */
const [base, adminEmail, adminPw, staffEmail, staffPw] = process.argv.slice(2);
if (!base || !adminEmail || !adminPw || !staffEmail || !staffPw) {
  console.error('usage: node api_smoke.js <baseUrl> <adminEmail> <adminPw> <staffEmail> <staffPw>');
  process.exit(2);
}

const results = [];
// hard limit per call (ms); anything above SOFT only prints a warning
const budgetMs = { default: 1500 };
const SOFT = 600;

async function call(method, path, { token, body, accept = true } = {}) {
  const headers = {};
  if (accept) headers.Accept = 'application/json';
  if (body) headers['Content-Type'] = 'application/json';
  if (token) headers.Authorization = 'Bearer ' + token;
  const t0 = performance.now();
  const res = await fetch(base + path, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const ms = Math.round(performance.now() - t0);
  let json = null;
  const text = await res.text();
  try { json = JSON.parse(text); } catch { /* html or empty */ }
  return { status: res.status, json, ms, text, headers: res.headers };
}

async function check(name, fn, ms = budgetMs.default) {
  let ok = false, detail = '', took = 0;
  try {
    const r = await fn();
    ok = r.ok; detail = r.detail || ''; took = r.ms || 0;
  } catch (e) { detail = 'EXCEPTION ' + e.message; }
  const slow = took > ms;
  const warn = took > SOFT && !slow ? "  [slow >"+SOFT+"ms]" : "";
  results.push({ name, ok: ok && !slow, detail: (slow ? `${detail} (TOO SLOW ${took}ms > ${ms}ms)` : detail) + warn, took });
}

const envelopeOk = (j) => j && (j.status === 0 || j.status === 1) && typeof j.message === 'string';

(async () => {
  let adminTok, staffTok;

  await check('health is public and healthy', async () => {
    const r = await call('GET', '/health');
    return { ok: r.status === 200 && r.json?.data?.db === true && r.json?.data?.schema_ok === true, detail: JSON.stringify(r.json?.data || r.text.slice(0, 100)), ms: r.ms };
  });

  await check('unauthenticated /auth/me → 401 JSON envelope even WITHOUT an Accept header', async () => {
    const r = await call('GET', '/auth/me', { accept: false });
    return { ok: r.status === 401 && envelopeOk(r.json) && r.json.status === 0, detail: `http ${r.status} ${r.json ? '' : 'NOT JSON: ' + r.text.slice(0, 60)}`, ms: r.ms };
  });

  await check('unknown endpoint → 404 envelope', async () => {
    const r = await call('GET', '/nope');
    return { ok: r.status === 404 && envelopeOk(r.json), detail: `http ${r.status} ${r.json?.message}`, ms: r.ms };
  });

  await check('response carries X-Request-Id and body request_id on errors', async () => {
    const r = await call('GET', '/auth/me');
    return { ok: !!r.headers.get('x-request-id') && r.json?.request_id === r.headers.get('x-request-id'), detail: r.headers.get('x-request-id') || 'missing', ms: r.ms };
  });

  await check('login validation → 422 with errors{}', async () => {
    const r = await call('POST', '/auth/login', { body: { email: 'bad' } });
    return { ok: r.status === 422 && r.json?.errors?.email && r.json?.errors?.password, detail: `http ${r.status} ${r.json?.message}`, ms: r.ms };
  });

  await check('wrong password → 401, unknown email → 401 (same message)', async () => {
    const a = await call('POST', '/auth/login', { body: { email: adminEmail, password: 'wrong-pw-1' } });
    const b = await call('POST', '/auth/login', { body: { email: 'nobody@nowhere.test', password: 'wrong-pw-1' } });
    return { ok: a.status === 401 && b.status === 401 && a.json.message === b.json.message, detail: `${a.json?.message} | ${b.json?.message}`, ms: Math.max(a.ms, b.ms) };
  });

  await check('admin login → token, 30-day expiry, user+modules', async () => {
    const r = await call('POST', '/auth/login', { body: { email: adminEmail, password: adminPw, device_name: 'smoke-admin' } });
    adminTok = r.json?.data?.token;
    const days = (new Date(r.json?.data?.expires_at) - Date.now()) / 86400000;
    return { ok: r.status === 200 && !!adminTok && days > 29 && days < 31 && r.json.data.user.modules.dashboard === true, detail: `expires in ${days.toFixed(1)} days, home=${r.json?.data?.user?.home}`, ms: r.ms };
  });

  await check('staff login → limited modules (web parity)', async () => {
    const r = await call('POST', '/auth/login', { body: { email: staffEmail, password: staffPw, device_name: 'smoke-staff' } });
    staffTok = r.json?.data?.token;
    const m = r.json?.data?.user?.modules || {};
    const ok = r.status === 200 && m.dashboard && m.appointments && m.calendar && m.invoices && m.staff_report && m.working_hours && !m.reports && !m.customers && !m.staff;
    return { ok, detail: Object.entries(m).filter(([, v]) => v).map(([k]) => k).join(','), ms: r.ms };
  });

  await check('/auth/me returns the same user', async () => {
    const r = await call('GET', '/auth/me', { token: adminTok });
    return { ok: r.status === 200 && r.json?.data?.user?.email === adminEmail, detail: r.json?.data?.user?.role, ms: r.ms };
  });

  await check('/bootstrap has everything the app needs', async () => {
    const r = await call('GET', '/bootstrap', { token: adminTok });
    const d = r.json?.data || {};
    const need = ['user', 'shop', 'currency', 'timezone', 'server_time', 'tax', 'payment_methods', 'statuses', 'appointment_actions', 'slot_step_minutes', 'shop_hours', 'limits', 'app'];
    const missing = need.filter((k) => !(k in d));
    const ok = r.status === 200 && missing.length === 0 && d.statuses.length === 5 && d.shop_hours.length === 7 && d.slot_step_minutes >= 5 && d.slot_step_minutes <= 60 && d.currency.code === 'CAD';
    return { ok, detail: missing.length ? 'missing ' + missing.join(',') : `tax=${d.tax ? d.tax.rate + '% ' + d.tax.type : 'none'}, step=${d.slot_step_minutes}min, methods=${d.payment_methods.length}, tz=${d.timezone}`, ms: r.ms };
  });

  await check('/bootstrap for staff works too', async () => {
    const r = await call('GET', '/bootstrap', { token: staffTok });
    return { ok: r.status === 200 && r.json?.data?.user?.is_staff === true, detail: '', ms: r.ms };
  });

  await check('device limit: only the newest 5 tokens survive', async () => {
    const tokens = [];
    for (let i = 0; i < 6; i++) {
      const r = await call('POST', '/auth/login', { body: { email: staffEmail, password: staffPw, device_name: 'dev-' + i } });
      tokens.push(r.json?.data?.token);
    }
    // staffTok (earlier) + 6 new = 7 tokens, so the 2 oldest are gone
    const oldest = await call('GET', '/auth/me', { token: staffTok });
    const newest = await call('GET', '/auth/me', { token: tokens[5] });
    staffTok = tokens[5];
    return { ok: oldest.status === 401 && newest.status === 200, detail: `oldest→${oldest.status}, newest→${newest.status}`, ms: 0 };
  }, 99999);

  await check('logout revokes only that token', async () => {
    const other = await call('POST', '/auth/login', { body: { email: adminEmail, password: adminPw, device_name: 'second' } });
    const r = await call('POST', '/auth/logout', { token: adminTok });
    const after = await call('GET', '/auth/me', { token: adminTok });
    const stillOk = await call('GET', '/auth/me', { token: other.json.data.token });
    adminTok = other.json.data.token;
    return { ok: r.status === 200 && after.status === 401 && stillOk.status === 200, detail: `logout ${r.status}, reuse ${after.status}, other device ${stillOk.status}`, ms: r.ms };
  });

  await check('logout-all revokes every token of the user', async () => {
    const a = await call('POST', '/auth/login', { body: { email: staffEmail, password: staffPw, device_name: 'a' } });
    const b = await call('POST', '/auth/login', { body: { email: staffEmail, password: staffPw, device_name: 'b' } });
    const r = await call('POST', '/auth/logout-all', { token: a.json.data.token });
    const ca = await call('GET', '/auth/me', { token: a.json.data.token });
    const cb = await call('GET', '/auth/me', { token: b.json.data.token });
    return { ok: r.status === 200 && ca.status === 401 && cb.status === 401, detail: `a→${ca.status}, b→${cb.status}`, ms: r.ms };
  });

  // Last: it locks the login for about a minute.
  await check('login rate limit → 429 envelope with retry_after', async () => {
    let last;
    for (let i = 0; i < 12; i++) last = await call('POST', '/auth/login', { body: { email: 'rl-test@nowhere.test', password: 'x' + i } });
    return { ok: last.status === 429 && envelopeOk(last.json) && last.json.retry_after > 0, detail: `http ${last.status}, retry_after=${last.json?.retry_after}s`, ms: 0 };
  }, 99999);

  // ---- report
  const w = Math.max(...results.map((r) => r.name.length));
  console.log('\nAPI smoke test →', base, '\n');
  for (const r of results) console.log((r.ok ? '  PASS ' : '  FAIL ') + r.name.padEnd(w) + (r.took ? `  ${String(r.took).padStart(4)}ms` : '        ') + (r.detail ? '  ' + r.detail : ''));
  const failed = results.filter((r) => !r.ok).length;
  console.log(`\n${results.length - failed}/${results.length} passed` + (failed ? `, ${failed} FAILED` : ''));
  process.exit(failed ? 1 : 0);
})();
