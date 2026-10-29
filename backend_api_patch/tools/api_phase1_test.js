#!/usr/bin/env node
/**
 * Phase 1 behaviour tests (actions, permissions, scope, validation, profile).
 *
 *   node api_phase1_test.js <apiBase> <adminEmail> <adminPw> <staffEmail> <staffPw>
 *
 * Expects the marked test appointments APITEST-1..7 to exist (see the test-data
 * script) and a local MySQL reachable as `mysql -uroot barber_shop_db` for the one
 * permission test that temporarily removes the staff user's role.
 */
const { execSync } = require('child_process');
const [apiBase, adminEmail, adminPw, staffEmail, staffPw] = process.argv.slice(2);
if (!staffPw) { console.error('usage: node api_phase1_test.js <apiBase> <adminEmail> <adminPw> <staffEmail> <staffPw>'); process.exit(2); }

const results = [];
const rec = (name, ok, detail = '') => results.push({ name, ok, detail });
const mysql = (sql) => execSync(`mysql -uroot -h127.0.0.1 -N -B barber_shop_db -e "${sql}"`, { encoding: 'utf8' }).trim();

async function call(method, path, { token, body, form } = {}) {
  const headers = { Accept: 'application/json' };
  if (token) headers.Authorization = 'Bearer ' + token;
  let payload;
  if (body) { headers['Content-Type'] = 'application/json'; payload = JSON.stringify(body); }
  if (form) payload = form;
  const res = await fetch(apiBase + path, { method, headers, body: payload });
  let json = null; try { json = await res.json(); } catch { /* not json */ }
  return { status: res.status, json, headers: res.headers };
}
const login = async (email, pw, device = 'p1') => (await call('POST', '/auth/login', { body: { email, password: pw, device_name: device } })).json.data.token;
const idOf = (code) => Number(mysql(`select appointment_id from tbl_appointment where booking_code='${code}'`));
const statusOf = (id) => Number(mysql(`select status from tbl_appointment where appointment_id=${id}`));

async function t(name, fn) {
  try { const r = await fn(); rec(name, r.ok, r.detail || ''); } catch (e) { rec(name, false, 'EXCEPTION ' + e.message); }
}

(async () => {
  const admin = await login(adminEmail, adminPw);
  const staff = await login(staffEmail, staffPw);
  const A1 = idOf('APITEST-1'), A3 = idOf('APITEST-3'), A4 = idOf('APITEST-4'), A7 = idOf('APITEST-7'), A2 = idOf('APITEST-2');
  const completedId = Number(mysql("select appointment_id from tbl_appointment where status=1 limit 1"));

  // ------------------------------------------------ confirm / cancel rules
  await t('confirm a Pending appointment → 200, status 3, actions without "confirm"', async () => {
    const r = await call('POST', `/appointments/${A1}/confirm`, { token: admin });
    const a = r.json?.data?.appointment;
    return { ok: r.status === 200 && a.status === 3 && statusOf(A1) === 3 && !a.actions.includes('confirm') && a.actions.includes('cancel'), detail: `http ${r.status} → ${a?.status_label} [${a?.actions}]` };
  });
  await t('confirm again → 409 "already confirmed" (no silent success)', async () => {
    const r = await call('POST', `/appointments/${A1}/confirm`, { token: admin });
    return { ok: r.status === 409 && /already confirmed/i.test(r.json.message), detail: r.json?.message };
  });
  await t('cancel a Confirmed appointment → 200, status 2', async () => {
    const r = await call('POST', `/appointments/${A1}/cancel`, { token: admin });
    return { ok: r.status === 200 && statusOf(A1) === 2, detail: r.json?.message };
  });
  await t('confirm a Cancelled appointment → 409 (the web offers no such button)', async () => {
    const r = await call('POST', `/appointments/${A1}/confirm`, { token: admin });
    return { ok: r.status === 409 && statusOf(A1) === 2, detail: r.json?.message };
  });
  await t('cancel a Cancelled appointment → 409', async () => {
    const r = await call('POST', `/appointments/${A1}/cancel`, { token: admin });
    return { ok: r.status === 409, detail: r.json?.message };
  });
  await t('confirm a Rescheduled (4) appointment → 200 (web shows Confirm for 4)', async () => {
    const r = await call('POST', `/appointments/${A7}/confirm`, { token: admin });
    return { ok: r.status === 200 && statusOf(A7) === 3, detail: r.json?.message };
  });
  await t('a COMPLETED appointment can be neither confirmed nor cancelled (web would allow any status)', async () => {
    const before = statusOf(completedId);
    const c = await call('POST', `/appointments/${completedId}/confirm`, { token: admin });
    const x = await call('POST', `/appointments/${completedId}/cancel`, { token: admin });
    return { ok: c.status === 409 && x.status === 409 && statusOf(completedId) === before && before === 1, detail: `confirm ${c.status}, cancel ${x.status}, status still ${statusOf(completedId)}` };
  });
  await t('unknown id → 404 envelope; non-numeric id → 404 envelope', async () => {
    const a = await call('POST', '/appointments/99999999/confirm', { token: admin });
    const b = await call('POST', '/appointments/abc/confirm', { token: admin });
    return { ok: a.status === 404 && b.status === 404 && a.json.status === 0 && b.json.status === 0, detail: `${a.status}/${b.status}` };
  });

  // ------------------------------------------------ staff scope
  await t('staff cannot act on another barber\'s appointment → 404 (and nothing changes)', async () => {
    const before = statusOf(A4);
    const r = await call('POST', `/appointments/${A4}/confirm`, { token: staff });
    return { ok: r.status === 404 && statusOf(A4) === before, detail: `http ${r.status}, status still ${statusOf(A4)}` };
  });
  await t('staff cannot view another barber\'s appointment detail → 404', async () => {
    const r = await call('GET', `/appointments/${A4}`, { token: staff });
    return { ok: r.status === 404, detail: `http ${r.status}` };
  });
  await t('staff CAN confirm an appointment that has one of their own lines', async () => {
    const r = await call('POST', `/appointments/${A3}/confirm`, { token: staff });
    return { ok: r.status === 200 && statusOf(A3) === 3, detail: `http ${r.status}` };
  });
  await t('staff sees only their own service lines on a shared appointment (no other barber, no price leak)', async () => {
    const r = await call('GET', `/appointments/${A2}`, { token: staff });
    const a = r.json?.data?.appointment;
    const names = a.staff_grouped.map((g) => g.staff_name);
    const adminView = (await call('GET', `/appointments/${A2}`, { token: admin })).json.data.appointment;
    return { ok: r.status === 200 && names.length === 1 && names[0] === 'API Test Staff' && adminView.staff_grouped.length === 2, detail: `staff sees [${names}], admin sees ${adminView.staff_grouped.length} groups` };
  });
  await t('staff list never contains appointments of other staff', async () => {
    const r = await call('GET', '/appointments?per_page=50', { token: staff });
    const bad = r.json.data.items.filter((i) => !i.staff_ids.includes(51));
    return { ok: r.status === 200 && bad.length === 0, detail: `${r.json.meta.total} rows, foreign: ${bad.length}` };
  });

  // ------------------------------------------------ permissions
  await t('user WITHOUT roles gets 403 on appointments and dashboard (web: canany middleware)', async () => {
    const saved = mysql('select role_id from model_has_roles where model_id=51');
    const adminId = mysql("select id from users where email='" + adminEmail + "'");
    mysql("delete from model_has_roles where model_id=51");
    try {
      const tok = await login(staffEmail, staffPw, 'norole');
      const a = await call('GET', '/appointments', { token: tok });
      const b = await call('GET', '/dashboard/summary', { token: tok });
      const c = await call('GET', '/dashboard/today', { token: tok });
      const me = await call('GET', '/me/profile', { token: tok });
      return { ok: a.status === 403 && b.status === 403 && c.status === 403 && me.status === 200 && a.json.status === 0, detail: `appointments ${a.status}, summary ${b.status}, today ${c.status}, profile still ${me.status}; msg="${a.json?.message}"` };
    } finally {
      if (saved) mysql('insert into model_has_roles (role_id, model_type, model_id) select ' + saved + ', model_type, 51 from model_has_roles where model_id=' + adminId + ' limit 1');
    }
  });
  await t('staff role restored correctly (6 permissions again)', async () => {
    const tok = await login(staffEmail, staffPw, 'after');
    const me = await call('GET', '/auth/me', { token: tok });
    return { ok: me.json.data.user.permissions.length === 6, detail: `${me.json.data.user.permissions.length} permissions` };
  });
  await t('dashboard widgets mirror @can: staff sees today+upcoming only', async () => {
    const r = await call('GET', '/dashboard/summary', { token: staff });
    const w = r.json.data.widgets;
    return { ok: w.today && w.upcoming && !w.top_services && !w.top_products && r.json.data.scope === 'staff', detail: JSON.stringify(w) };
  });

  // ------------------------------------------------ validation & paging
  await t('validation: bad status/date/day_type → 422 with errors{}', async () => {
    const a = await call('GET', '/appointments?status=9', { token: admin });
    const b = await call('GET', '/appointments?start_date=23-10-2026', { token: admin });
    const c = await call('GET', '/appointments?day_type=Night', { token: admin });
    return { ok: [a, b, c].every((r) => r.status === 422 && r.json.errors), detail: [a, b, c].map((r) => r.status).join('/') };
  });
  await t('paging: per_page=1000 is clamped to 50; page=0 becomes 1; meta is correct', async () => {
    const r = await call('GET', '/appointments?per_page=1000&page=0', { token: admin });
    const m = r.json.meta;
    const p2 = await call('GET', '/appointments?per_page=5&page=2', { token: admin });
    return { ok: m.per_page === 50 && m.page === 1 && p2.json.data.items.length === 5 && p2.json.meta.has_more === true && p2.json.meta.page === 2, detail: JSON.stringify(m) };
  });
  await t('money and ids are typed: money = "NN.NN" strings, ids = integers', async () => {
    const r = await call('GET', `/appointments/${A2}`, { token: admin });
    const a = r.json.data.appointment;
    return { ok: /^\d+\.\d{2}$/.test(a.total) && /^\d+\.\d{2}$/.test(a.subtotal) && Number.isInteger(a.id) && a.services_grouped.every((g) => /^\d+\.\d{2}$/.test(g.price)), detail: `total=${a.total} subtotal=${a.subtotal}` };
  });
  await t('bootstrap actions: no "complete" while the flag is off (web "Complete" 404s)', async () => {
    const r = await call('GET', '/bootstrap', { token: admin });
    const acts = r.json.data.appointment_actions;
    return { ok: !Object.values(acts).flat().includes('complete') && r.json.data.app.feature_flags.complete_from_appointment === false, detail: JSON.stringify(acts['0']) };
  });

  // ------------------------------------------------ profile
  await t('ME-1 profile: staff gets stats + services, admin gets stats=null', async () => {
    const s = await call('GET', '/me/profile', { token: staff });
    const a = await call('GET', '/me/profile', { token: admin });
    const st = s.json.data.stats;
    return { ok: s.status === 200 && st && /^\d+\.\d{2}$/.test(st.total_earning) && Array.isArray(s.json.data.services) && a.json.data.stats === null, detail: `staff stats ${JSON.stringify(st)}` };
  });
  await t('ME-2 update: name/phone saved, email must be unique', async () => {
    const me = (await call('GET', '/me/profile', { token: staff })).json.data.user;
    const f = new FormData(); f.set('name', 'API Test Staff'); f.set('email', staffEmail); f.set('phone', '7805550101');
    const ok = await call('POST', '/me/profile', { token: staff, form: f });
    const g = new FormData(); g.set('name', 'X'); g.set('email', adminEmail);
    const dup = await call('POST', '/me/profile', { token: staff, form: g });
    return { ok: ok.status === 200 && ok.json.data.user.phone === '7805550101' && dup.status === 422 && !!dup.json.errors.email, detail: `save ${ok.status}, duplicate email ${dup.status}` };
  });
  await t('ME-2 photo upload: PNG accepted (URL changes), .txt rejected, old file removed on replace', async () => {
    const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
    const send = async () => { const f = new FormData(); f.set('name', 'API Test Staff'); f.set('email', staffEmail); f.set('profile_image', new Blob([png], { type: 'image/png' }), 'x.png'); return call('POST', '/me/profile', { token: staff, form: f }); };
    const r1 = await send();
    const p1 = mysql('select profile_img from users where id=51');
    const r2 = await send();
    const p2 = mysql('select profile_img from users where id=51');
    const bad = new FormData(); bad.set('name', 'API Test Staff'); bad.set('email', staffEmail); bad.set('profile_image', new Blob(['hello'], { type: 'text/plain' }), 'x.txt');
    const r3 = await call('POST', '/me/profile', { token: staff, form: bad });
    const fs = require('fs');
    const oldGone = !fs.existsSync('J:/laragon/www/rosen_barber/public/storage/' + p1);
    const newThere = fs.existsSync('J:/laragon/www/rosen_barber/public/storage/' + p2);
    mysql('update users set profile_img=NULL where id=51');
    if (newThere) fs.unlinkSync('J:/laragon/www/rosen_barber/public/storage/' + p2);
    return { ok: r1.status === 200 && /storage\/profile_images\//.test(r1.json.data.user.profile_image_url) && p1 !== p2 && oldGone && newThere && r3.status === 422, detail: `upload ${r1.status}, replace ${r2.status}, old removed ${oldGone}, txt ${r3.status}` };
  });

  // ------------------------------------------------ global rate limit (envelope, not Laravel's default 60/min)
  await t('rate limit: 300 quick calls → 429 in OUR envelope (240/min per user), no 5xx, no debug leak', async () => {
    const tok = await login(adminEmail, adminPw, 'burst');
    const rs = [];
    for (let b = 0; b < 6; b++) rs.push(...await Promise.all(Array.from({ length: 50 }, () => call('GET', '/auth/me', { token: tok }))));
    const limited = rs.filter((r) => r.status === 429);
    const okCount = rs.filter((r) => r.status === 200).length;
    const leak = limited.some((r) => r.json && (r.json.exception || r.json.file));
    const serverErrors = rs.filter((r) => r.status >= 500).length;
    return { ok: serverErrors === 0 && limited.length > 0 && okCount >= 200 && !leak && limited[0].json.status === 0 && limited[0].json.retry_after > 0, detail: `${okCount} ok, ${limited.length} limited, ${serverErrors} server errors, retry_after=${limited[0]?.json?.retry_after}` };
  });

  const w = Math.max(...results.map((r) => r.name.length));
  console.log('\nPhase 1 behaviour tests\n');
  for (const r of results) console.log((r.ok ? '  PASS ' : '  FAIL ') + r.name.padEnd(w) + (r.detail ? '  ' + r.detail : ''));
  const failed = results.filter((r) => !r.ok).length;
  console.log(`\n${results.length - failed}/${results.length} passed` + (failed ? `, ${failed} FAILED` : ''));
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
