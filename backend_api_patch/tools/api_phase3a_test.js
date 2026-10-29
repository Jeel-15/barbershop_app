#!/usr/bin/env node
/**
 * Phase 3a behaviour tests: customer create / edit / delete (+ write parity with the web),
 * validation, permissions. Needs the marked test data.
 *   node api_phase3a_test.js <webBase> <apiBase> <adminEmail> <adminPw> <staffEmail> <staffPw>
 */
const { execSync } = require('child_process');
const [webBase, apiBase, adminEmail, adminPw, staffEmail, staffPw] = process.argv.slice(2);
if (!staffPw) { console.error('usage: node api_phase3a_test.js <webBase> <apiBase> <adminEmail> <adminPw> <staffEmail> <staffPw>'); process.exit(2); }
const results = [];
const sql = (q) => execSync('mysql -uroot -h127.0.0.1 -N -B barber_shop_db', { input: q, encoding: 'utf8' }).replace(/\r/g, '').trim();
const row = (q) => sql(q).split('\t').join('|');

class Web {
  constructor() { this.jar = {}; this.csrf = null; }
  ck() { return Object.entries(this.jar).map(([k, v]) => `${k}=${v}`).join('; '); }
  store(r) { for (const c of r.headers.getSetCookie?.() || []) { const [p] = c.split(';'); const i = p.indexOf('='); this.jar[p.slice(0, i)] = p.slice(i + 1); } }
  async req(method, path, form) {
    const headers = { Cookie: this.ck(), 'X-Requested-With': 'XMLHttpRequest', 'X-CSRF-TOKEN': this.csrf, Accept: 'application/json' };
    let body; if (form) { headers['Content-Type'] = 'application/x-www-form-urlencoded'; body = new URLSearchParams(form).toString(); }
    const r = await fetch(webBase + path, { method, headers, body, redirect: 'manual' }); this.store(r); return r;
  }
  async login(email, pw) {
    const page = await fetch(webBase + '/admin/login'); this.store(page);
    const tok = ((await page.text()).match(/name="_token" value="([^"]+)"/) || [])[1];
    const r = await fetch(webBase + '/admin/post-login', { method: 'POST', redirect: 'manual', headers: { 'Content-Type': 'application/x-www-form-urlencoded', Cookie: this.ck() }, body: new URLSearchParams({ _token: tok, email, password: pw }) }); this.store(r);
    this.csrf = ((await (await fetch(webBase + '/admin/dashboard', { headers: { Cookie: this.ck() } })).text()).match(/name="csrf-token" content="([^"]+)"/) || [])[1];
  }
}
async function call(method, path, token, body) {
  const headers = { Accept: 'application/json', Authorization: 'Bearer ' + token };
  if (body) headers['Content-Type'] = 'application/json';
  const r = await fetch(apiBase + path, { method, headers, body: body ? JSON.stringify(body) : undefined });
  let json = null; try { json = await r.json(); } catch (e) { /* none */ }
  return { status: r.status, json };
}
const login = async (e, p) => (await (await fetch(apiBase + '/auth/login', { method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'application/json' }, body: JSON.stringify({ email: e, password: p, device_name: 'p3a' }) })).json()).data.token;
async function t(name, fn) { try { const r = await fn(); results.push({ name, ok: r.ok, detail: r.detail || '' }); } catch (e) { results.push({ name, ok: false, detail: 'EXCEPTION ' + e.message }); } }
const cust = (id) => row(`select customer_name,customer_phone,ifnull(customer_email,'NULL'),ifnull(customer_status,'NULL') from customers where customer_id=${id}`);

(async () => {
  const admin = await login(adminEmail, adminPw), staff = await login(staffEmail, staffPw);
  const web = new Web(); await web.login(adminEmail, adminPw);
  let created;
  await t('CUST-4 create: 201, row saved, appears in the list', async () => {
    const r = await call('POST', '/customers', admin, { full_name: 'API TEST Cust', phone_number: '5559991001', email: 'c@test.test', status: 1 });
    created = r.json?.data?.customer?.id;
    return { ok: r.status === 201 && r.json.data.customer.status_label === 'Active' && cust(created) === 'API TEST Cust|5559991001|c@test.test|1', detail: `#${created}` };
  });
  await t('WRITE PARITY create: web and API store identical rows (incl. null email / status)', async () => {
    const w = await (await web.req('POST', '/admin/customers', { full_name: 'API TEST Cust W', phone_number: '5559991002', email: '', status: '' })).json();
    const wid = Number(sql("select customer_id from customers where customer_phone='5559991002'"));
    const a = await call('POST', '/customers', admin, { full_name: 'API TEST Cust W', phone_number: '5559991003' });
    const aid = a.json.data.customer.id;
    return { ok: w.status === 1 && a.status === 201 && cust(wid).replace('5559991002', 'P') === cust(aid).replace('5559991003', 'P'), detail: `web "${cust(wid)}" api "${cust(aid)}"` };
  });
  await t('CUST-4 validation: missing name / phone, long phone, bad email → 422', async () => {
    const bad = [{ phone_number: '1' }, { full_name: 'x' }, { full_name: 'x', phone_number: '1'.repeat(21) }, { full_name: 'x', phone_number: '1', email: 'nope' }];
    const out = []; for (const b of bad) out.push((await call('POST', '/customers', admin, b)).status);
    return { ok: out.every((s) => s === 422), detail: out.join('/') };
  });
  await t('CUST-5 update: 200 and row changed; unknown id 404; invalid 422', async () => {
    const r = await call('PUT', `/customers/${created}`, admin, { full_name: 'API TEST Cust 2', phone_number: '5559991001', email: '', status: 0 });
    const miss = await call('PUT', '/customers/99999999', admin, { full_name: 'x', phone_number: '1' });
    const inv = await call('PUT', `/customers/${created}`, admin, { full_name: '' });
    return { ok: r.status === 200 && cust(created) === 'API TEST Cust 2|5559991001|NULL|0' && r.json.data.customer.status_label === 'Inactive' && miss.status === 404 && inv.status === 422, detail: cust(created) };
  });
  await t('WRITE PARITY update: web PUT and API PUT leave identical rows', async () => {
    const mk = async (n, ph) => (await call('POST', '/customers', admin, { full_name: n, phone_number: ph, email: 'a@b.cd', status: 1 })).json.data.customer.id;
    const w = await mk('API TEST Upd W', '5559991010'), a = await mk('API TEST Upd A', '5559991011');
    const wr = await (await web.req('PUT', `/admin/customers/${w}`, { full_name: 'API TEST Upd X', phone_number: '5559991010', email: 'z@y.xx', status: '0' })).json();
    const ar = await call('PUT', `/customers/${a}`, admin, { full_name: 'API TEST Upd X', phone_number: '5559991010', email: 'z@y.xx', status: 0 });
    return { ok: wr.status === 1 && ar.status === 200 && cust(w) === cust(a), detail: `${cust(w)} vs ${cust(a)}` };
  });
  await t('CUST-6 delete: customer with appointments → 409 and still there; without → 200 and gone; unknown → 404', async () => {
    const withAppt = await call('DELETE', '/customers/11', admin);
    const still = Number(sql('select count(*) from customers where customer_id=11'));
    const del = await call('DELETE', `/customers/${created}`, admin);
    const gone = Number(sql(`select count(*) from customers where customer_id=${created}`));
    const miss = await call('DELETE', '/customers/99999999', admin);
    return { ok: withAppt.status === 409 && still === 1 && del.status === 200 && gone === 0 && miss.status === 404, detail: `${withAppt.status}/${del.status}/${miss.status}` };
  });
  await t('permissions: staff (no Customer perms) gets 403 on every customer route', async () => {
    const out = [(await call('GET', '/customers', staff)).status, (await call('POST', '/customers', staff, { full_name: 'x', phone_number: '1' })).status, (await call('GET', '/customers/11', staff)).status, (await call('DELETE', '/customers/11', staff)).status];
    return { ok: out.every((s) => s === 403), detail: out.join('/') };
  });
  const w = Math.max(...results.map((r) => r.name.length));
  console.log('\nPhase 3a behaviour tests\n');
  for (const r of results) console.log((r.ok ? '  PASS ' : '  FAIL ') + r.name.padEnd(w) + (r.detail ? '  ' + r.detail : ''));
  const failed = results.filter((r) => !r.ok).length;
  console.log(`\n${results.length - failed}/${results.length} passed` + (failed ? `, ${failed} FAILED` : ''));
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
