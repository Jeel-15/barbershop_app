#!/usr/bin/env node
/**
 * Phase 4b tests: staff administration. Reads (list, profile cards, earnings, services,
 * appointments, assigned services) are compared with the web's own pages; create / edit /
 * delete / password are compared with the web by the rows they leave; role escalation,
 * session revocation and permissions are checked.
 *
 *   node api_phase4b_test.js <webBase> <apiBase> <adminEmail> <adminPw> <staffEmail> <staffPw>
 *
 * Everything it creates uses the e-mail pattern p4b-*@rosen.test and is removed at the end
 * (rows, roles, slots, breaks, tokens and uploaded pictures).
 */
const { execSync } = require('child_process');
const fs = require('fs');
const [webBase, apiBase, adminEmail, adminPw, staffEmail, staffPw] = process.argv.slice(2);
if (!staffPw) { console.error('usage: node api_phase4b_test.js <webBase> <apiBase> <adminEmail> <adminPw> <staffEmail> <staffPw>'); process.exit(2); }

const results = [];
const sql = (q) => execSync('mysql -uroot -h127.0.0.1 -N -B barber_shop_db', { input: q, encoding: 'utf8' }).replace(/\r/g, '').trim();
const rows = (q) => sql(q).split('\n').filter(Boolean).map((l) => l.split('\t'));
const one = (q) => (rows(q)[0] || [])[0];
const STORAGE = process.env.STORAGE_DIR || 'J:/laragon/www/rosen_barber/public/storage';
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
const png = () => new Blob([PNG], { type: 'image/png' });

class Web {
  constructor() { this.jar = {}; this.csrf = null; }
  ck() { return Object.entries(this.jar).map(([k, v]) => `${k}=${v}`).join('; '); }
  store(r) { for (const c of r.headers.getSetCookie?.() || []) { const [p] = c.split(';'); const i = p.indexOf('='); this.jar[p.slice(0, i)] = p.slice(i + 1); } }
  async send(method, path, fields = {}, files = {}) {
    const fd = new FormData();
    for (const [k, v] of Object.entries(fields)) { if (Array.isArray(v)) v.forEach((x) => fd.append(k, x)); else if (v !== undefined && v !== null) fd.append(k, v); }
    for (const [k, v] of Object.entries(files)) fd.append(k, v, 'x.png');
    if (method !== 'POST') fd.append('_method', method);
    const r = await fetch(webBase + path, { method: 'POST', body: fd, redirect: 'manual', headers: { Cookie: this.ck(), 'X-Requested-With': 'XMLHttpRequest', 'X-CSRF-TOKEN': this.csrf, Accept: 'application/json' } });
    this.store(r);
    try { return await r.json(); } catch (e) { return { status: -1, http: r.status }; }
  }
  async table(path, params = {}) {
    const form = new URLSearchParams({ draw: '1', start: '0', length: '-1', ...params });
    const r = await fetch(webBase + path, { method: 'POST', body: form, headers: { Cookie: this.ck(), 'X-Requested-With': 'XMLHttpRequest', 'X-CSRF-TOKEN': this.csrf, Accept: 'application/json' } });
    return r.json();
  }
  async page(path) { return (await fetch(webBase + path, { headers: { Cookie: this.ck() } })).text(); }
  async login(email, pw) {
    const page = await fetch(webBase + '/admin/login'); this.store(page);
    const tok = ((await page.text()).match(/name="_token" value="([^"]+)"/) || [])[1];
    const r = await fetch(webBase + '/admin/post-login', { method: 'POST', redirect: 'manual', headers: { 'Content-Type': 'application/x-www-form-urlencoded', Cookie: this.ck() }, body: new URLSearchParams({ _token: tok, email, password: pw }) }); this.store(r);
    const dash = await (await fetch(webBase + '/admin/dashboard', { headers: { Cookie: this.ck() } })).text();
    this.csrf = (dash.match(/name="csrf-token" content="([^"]+)"/) || [])[1];
  }
}
async function call(method, path, token, body) {
  const headers = { Accept: 'application/json' };
  if (token) headers.Authorization = 'Bearer ' + token;
  let payload;
  if (body instanceof FormData) payload = body;
  else if (body) { headers['Content-Type'] = 'application/json'; payload = JSON.stringify(body); }
  const r = await fetch(apiBase + path, { method, headers, body: payload });
  let json = null; try { json = await r.json(); } catch (e) { /* none */ }
  return { status: r.status, json };
}
const form = (fields, files = {}) => { const fd = new FormData(); for (const [k, v] of Object.entries(fields)) { if (Array.isArray(v)) v.forEach((x) => fd.append(k, x)); else if (v !== undefined && v !== null) fd.append(k, v); } for (const [k, v] of Object.entries(files)) fd.append(k, v, 'x.png'); return fd; };
const loginRaw = (e, p) => fetch(apiBase + '/auth/login', { method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'application/json' }, body: JSON.stringify({ email: e, password: p, device_name: 'p4b' }) }).then((r) => r.json().then((j) => ({ http: r.status, json: j })));
const login = async (e, p) => (await loginRaw(e, p)).json.data.token;
async function t(name, fn) { try { const r = await fn(); results.push({ name, ok: r.ok, detail: r.detail || '' }); } catch (e) { results.push({ name, ok: false, detail: 'EXCEPTION ' + e.message }); } }
const unesc = (s) => String(s ?? '').replace(/<[^>]*>/g, '').replace(/&#0?39;/g, "'").replace(/&amp;/g, '&').trim();
const num = (s) => Number(String(s ?? '').replace(/[^0-9.\-]/g, '') || 0).toFixed(2);
const sameSet = (a, b) => a.length === b.length && [...a].sort().join('|') === [...b].sort().join('|');
async function all(token, path) {
  const items = []; let page = 1;
  for (;;) { const r = await call('GET', path + (path.includes('?') ? '&' : '?') + `per_page=50&page=${page}`, token); if (r.status !== 200) return { status: r.status, items }; items.push(...r.json.data.items); if (!r.json.meta.has_more) return { status: 200, items }; page++; }
}

(async () => {
  const admin = await login(adminEmail, adminPw), staff = await login(staffEmail, staffPw);
  const web = new Web(); await web.login(adminEmail, adminPw);
  const adminId = Number(one(`select id from users where email='${adminEmail}'`));
  const staffId = Number(one(`select id from users where email='${staffEmail}'`));
  const roleStaff = Number(one("select id from roles where name='Staff'")), roleAcct = Number(one("select id from roles where name='Accountant'"));
  const photos = [];
  const trackPhotos = () => { for (const [p] of rows("select profile_img from users where email like 'p4b-%@rosen.test' and profile_img is not null")) photos.push(p); };

  // ============================================================ reads
  await t('STAFF-1 list: same people and fields as the web staff table', async () => {
    const w = (await web.table('/admin/staff-action')).data.map((r) => `${r.id}|${unesc(r.name)}|${r.email}|${r.phone ?? ''}|${num(r.commission)}|${r.is_barber}|${r.active_status}|${unesc(r.service_names ?? '')}|${(r.role_ids || '').split(',').filter(Boolean).sort().join(',')}`);
    const r = await all(admin, '/staff');
    const a = r.items.map((s) => `${s.id}|${unesc(s.name)}|${s.email}|${s.phone ?? ''}|${s.commission}|${s.is_barber ? 1 : 0}|${s.active ? 1 : 0}|${unesc(s.service_names)}|${[...s.role_ids].sort().join(',')}`);
    const norm = (l) => l.map((x) => x.replace(/\|([^|]*)\|(\d+(,\d+)*)$/, (m, names, ids) => `|${names.split(', ').sort().join(', ')}|${ids}`));
    return { ok: r.status === 200 && sameSet(norm(w), norm(a)) && w.length > 5, detail: `web ${w.length}, api ${a.length}` };
  });
  await t('STAFF-1 list: search, barber and active filters; pagination', async () => {
    const q = await all(admin, '/staff?q=mike'), b = await all(admin, '/staff?barber=1'), nb = await all(admin, '/staff?barber=0');
    const total = (await all(admin, '/staff')).items.length;
    const p = await call('GET', '/staff?per_page=3&page=2', admin);
    return { ok: q.items.length >= 1 && q.items.every((s) => /mike/i.test(s.name + s.email + s.phone + s.service_names)) && b.items.every((s) => s.is_barber) && b.items.length + nb.items.length === total && p.json.data.items.length === 3 && p.json.meta.has_more, detail: `mike ${q.items.length}, barbers ${b.items.length}+${nb.items.length}=${total}` };
  });
  await t('STAFF-2 form options: roles except Super-admin and POS Manager, all services', async () => {
    const r = (await call('GET', '/staff/form-options', admin)).json.data;
    const roles = rows('select id,name from roles where id not in (1,4) order by id').map((x) => `${x[0]}|${x[1]}`);
    const svc = Number(one('select count(*) from tbl_service where deleted_at is null'));
    return { ok: sameSet(r.roles.map((x) => `${x.id}|${x.name}`), roles) && r.services.length === svc && !r.roles.some((x) => x.id === 1 || x.id === 4), detail: `${r.roles.map((x) => x.name).join(',')}` };
  });
  const profileIds = [staffId, 49, 40];
  await t('STAFF-3 profile cards equal the web profile page (visits, appointments, tips, commissions, total earning)', async () => {
    const bad = [];
    for (const id of profileIds) {
      const html = await web.page('/admin/staff-profile/' + id);
      const visit = (html.match(/<h4 class="mb-1">(\d+)<\/h4>/) || [])[1];
      const cards = [...html.matchAll(/<h4 class="mb-0">([^<]*)<\/h4>/g)].map((m) => m[1].trim());
      const s = (await call('GET', '/staff/' + id, admin)).json.data.summary;
      const exp = [visit, cards[0], num(cards[1]), num(cards[2]), num(cards[3]), num(cards[4])];
      const got = [String(s.total_visits), String(s.total_appointments), s.tips, s.product_commission, s.service_commission, s.total_earning];
      if (exp.join('|') !== got.join('|')) bad.push(`${id}: web ${exp} api ${got}`);
    }
    return { ok: bad.length === 0, detail: bad.join(' ; ') || `${profileIds.length} staff` };
  });
  await t('STAFF-4 daily earnings, STAFF-5 services, STAFF-6 appointments equal the web tables', async () => {
    const bad = [];
    for (const id of profileIds) {
      const we = (await web.table('/admin/staff-profile-daily-earning-action', { id: String(id) })).data.map((r) => `${r.appointment_date.split('-').reverse().join('-')}|${num(r.service_commission)}|${num(r.service_tip_earn)}|${num(r.product_commision_earn)}|${num(r.total_earning)}`);
      const ae = (await all(admin, `/staff/${id}/earnings`)).items.map((x) => `${x.date}|${x.service_commission}|${x.tips}|${x.product_commission}|${x.total_earning}`);
      if (!sameSet(we, ae)) bad.push(`${id} earnings web ${we.length} api ${ae.length}`);
      const ws = (await web.table('/admin/staff-profile-service-assign-action', { id: String(id) })).data.map((r) => `${unesc(r.service_name)}|${r.appointmentCount}|${num(r.total_service_commission)}|${num(r.total_service_tip)}|${num(r.totalRevenue)}`);
      const as = (await all(admin, `/staff/${id}/services`)).items.map((x) => `${unesc(x.service_name)}|${x.appointment_count}|${x.commission}|${x.tips}|${x.total_earning}`);
      if (!sameSet(ws, as)) bad.push(`${id} services web ${ws.length} api ${as.length}`);
      const wa = (await web.table('/admin/staff-profile-appointment-action', { id: String(id) })).data.map((r) => `${r.appointment_id}|${r.date}|${String(r.slot_start).slice(0, 5)}|${r.status}|${r.customer_name ?? ''}`);
      const aa = (await all(admin, `/staff/${id}/appointments`)).items.map((x) => `${x.id}|${x.date}|${x.start}|${x.status}|${x.customer.name ?? ''}`);
      if (!sameSet(wa, aa)) bad.push(`${id} appointments web ${wa.length} api ${aa.length}`);
    }
    return { ok: bad.length === 0, detail: bad.join(' ; ') || 'earnings, services, appointments for 3 staff' };
  });
  await t('STAFF-3..6 access: the staff member sees their own profile, not a colleague\'s; admin sees any; accountant/unknown id → 404', async () => {
    const own = await call('GET', `/staff/${staffId}`, staff), other = await call('GET', '/staff/49', staff), otherList = await call('GET', '/staff/49/earnings', staff);
    const adm = await call('GET', '/staff/49', admin), acct = Number(one("select id from users where role='Accountant' and deleted_at is null limit 1"));
    const nf = await call('GET', '/staff/99999999', admin);
    const acc = acct ? (await call('GET', `/staff/${acct}`, admin)).status : 404;
    return { ok: own.status === 200 && other.status === 403 && otherList.status === 403 && adm.status === 200 && nf.status === 404 && acc === 404, detail: `${own.status}/${other.status}/${otherList.status}/${adm.status}/${nf.status}/${acc}` };
  });

  // ============================================================ create
  const E = (s) => `p4b-${s}@rosen.test`;
  const usr = (email) => rows(`select role,is_barber,commission,active_status,ifnull(service_id,'N'),created_by,phone,profile_img is not null,name from users where email='${email}'`)[0];
  const uid = (email) => Number(one(`select id from users where email='${email}'`));
  const nz = (v) => (v === 'NULL' ? '' : v);
  const roleOf = (id) => nz(sql(`select group_concat(role_id) from model_has_roles where model_id=${id}`));
  const svcOf = (id) => nz(sql(`select group_concat(service_id order by service_id) from tbl_staff_service where staff_id=${id}`));
  const slotState = (id) => JSON.stringify([rows(`select day_name,is_day_off,ifnull(open_time,'N') from tbl_slots where staff_id=${id} order by id`), rows(`select b.break_start,b.break_end,b.break_type,b.staff_id=${id} from tbl_breaks b join tbl_slots s on s.id=b.slot_id where s.staff_id=${id} order by b.id`)]);
  await t('WRITE PARITY create barber: web store and API POST leave the same user, role, services, 7 slot rows and 14 type-2 blocks', async () => {
    const wRes = await web.send('POST', '/admin/staff', { staff_name: 'P4B Web', staff_email: E('web'), staff_phone: '5551110001', staff_password: 'secret1', 'service_id[]': ['25', '26'], commission: '40', status: '1', role_id: String(roleStaff), is_barber: '1' }, { profile_image: png() });
    const a = await call('POST', '/staff', admin, form({ name: 'P4B Api', email: E('api'), phone: '5551110001', password: 'secret1', 'service_ids[]': ['25', '26'], commission: 40, active_status: 1, role_id: roleStaff, is_barber: 1 }, { profile_image: png() }));
    trackPhotos();
    const w = uid(E('web')), ap = uid(E('api'));
    const norm = (r) => r.join('|').replace(/P4B (Web|Api)/, 'P4B X');
    const problems = [];
    if (wRes.status !== 1) problems.push('web ' + JSON.stringify(wRes).slice(0, 120));
    if (a.status !== 201) problems.push('api ' + a.status + JSON.stringify(a.json).slice(0, 160));
    const ws = norm(usr(E('web')).map((v, i) => (i === 5 ? 'by' : v))), as = norm(usr(E('api')).map((v, i) => (i === 5 ? 'by' : v)));
    if (ws !== as) problems.push(`user web ${ws} api ${as}`);
    if (usr(E('api'))[5] !== String(adminId)) problems.push('created_by');
    if (roleOf(w) !== roleOf(ap) || svcOf(w) !== svcOf(ap)) problems.push(`role/services web ${roleOf(w)}/${svcOf(w)} api ${roleOf(ap)}/${svcOf(ap)}`);
    if (slotState(w).replace(new RegExp(`,${w}`, 'g'), '') !== slotState(ap).replace(new RegExp(`,${ap}`, 'g'), '')) problems.push('slots/breaks differ');
    const days = Number(one(`select count(*) from tbl_slots where staff_id=${ap}`)), br = Number(one(`select count(*) from tbl_breaks b join tbl_slots s on s.id=b.slot_id where s.staff_id=${ap} and b.break_type=2`));
    if (days !== 7 || br !== 14) problems.push(`days ${days} breaks ${br}`);
    const lg = await loginRaw(E('api'), 'secret1');
    if (lg.http !== 200) problems.push('new account cannot sign in');
    return { ok: problems.length === 0, detail: problems.join(' | ') || `${as}; roles ${roleOf(ap)}, services ${svcOf(ap)}, sign-in ok` };
  });
  await t('WRITE PARITY create accountant (non-barber): no slots/blocks, commission forced to 0, no services', async () => {
    const wRes = await web.send('POST', '/admin/staff', { staff_name: 'P4B Acct W', staff_email: E('acctw'), staff_password: 'secret1', commission: '30', status: '1', role_id: String(roleAcct), 'service_id[]': ['25'], is_barber: '1' });
    const a = await call('POST', '/staff', admin, form({ name: 'P4B Acct A', email: E('accta'), password: 'secret1', commission: 30, active_status: 1, role_id: roleAcct, 'service_ids[]': ['25'], is_barber: 1 }));
    const w = uid(E('acctw')), ap = uid(E('accta'));
    const norm = (r) => r.map((v, i) => (i === 5 ? 'by' : v)).join('|').replace(/P4B Acct [WA]/, 'X');
    const slots = Number(one(`select count(*) from tbl_slots where staff_id in (${w},${ap})`));
    return { ok: wRes.status === 1 && a.status === 201 && norm(usr(E('acctw'))) === norm(usr(E('accta'))) && roleOf(w) === roleOf(ap) && roleOf(ap) === String(roleAcct) && slots === 0 && !svcOf(ap) && usr(E('accta'))[0] === 'Accountant' && usr(E('accta'))[1] === '0' && usr(E('accta'))[2] === '0.00', detail: norm(usr(E('accta'))) };
  });
  await t('create validation: duplicate e-mail (also in other letter case), bad e-mail, short password, barber without services, unknown service, bad role, no status → 422', async () => {
    const ok = { name: 'P4B Bad', email: E('bad'), password: 'secret1', 'service_ids[]': ['25'], active_status: 1, role_id: roleStaff, is_barber: 1 };
    const cases = [
      form({ ...ok, email: E('api').toUpperCase() }), form({ ...ok, email: adminEmail }), form({ ...ok, email: 'nope' }), form({ ...ok, password: '123' }),
      form({ ...ok, 'service_ids[]': undefined }), form({ ...ok, 'service_ids[]': ['999999'] }), form({ ...ok, role_id: 99999 }), form({ ...ok, active_status: undefined }),
      form({ ...ok, phone: '1'.repeat(21) }), form({ ...ok, commission: -1 }),
    ];
    const out = []; for (const c of cases) out.push((await call('POST', '/staff', admin, c)).status);
    const none = Number(one("select count(*) from users where email like 'p4b-bad%'"));
    return { ok: out.every((s) => s === 422) && none === 0, detail: out.join('/') };
  });
  await t('SECURITY: the API cannot grant Super-admin / POS Manager (the web form hides them but would accept the id), nor edit a non-staff account', async () => {
    const ok = { name: 'P4B Esc', email: E('esc'), password: 'secret1', active_status: 1, is_barber: 0 };
    const sup = await call('POST', '/staff', admin, form({ ...ok, role_id: 1 })), pos = await call('POST', '/staff', admin, form({ ...ok, role_id: 4 }));
    const onAdmin = await call('POST', `/staff/${adminId}`, admin, form({ ...ok, email: adminEmail, role_id: roleStaff }));
    const delAdmin = await call('DELETE', `/staff/${adminId}`, admin), pwAdmin = await call('PUT', `/staff/${adminId}/password`, admin, { new_password: 'hacked1', confirm_password: 'hacked1' });
    const stillAdmin = one(`select role from users where id=${adminId}`);
    return { ok: sup.status === 422 && pos.status === 422 && onAdmin.status === 404 && delAdmin.status === 404 && pwAdmin.status === 404 && stillAdmin !== 'Staff' && Number(one("select count(*) from users where email like 'p4b-esc%'")) === 0, detail: `${sup.status}/${pos.status}/${onAdmin.status}/${delAdmin.status}/${pwAdmin.status}, admin role ${stillAdmin}` };
  });

  // ============================================================ update
  await t('WRITE PARITY update: web PUT and API POST leave the same user, role and services; the old picture is deleted', async () => {
    const w = uid(E('web')), ap = uid(E('api'));
    const oldW = one(`select profile_img from users where id=${w}`), oldA = one(`select profile_img from users where id=${ap}`);
    const wRes = await web.send('PUT', `/admin/staff/${w}`, { staff_name: 'P4B Web2', staff_email: E('web'), staff_phone: '5551110002', 'service_id[]': ['27'], commission: '55', status: '0', role_id: String(roleStaff), is_barber: '1' }, { profile_image: png() });
    const a = await call('POST', `/staff/${ap}`, admin, form({ name: 'P4B Api2', email: E('api'), phone: '5551110002', 'service_ids[]': ['27'], commission: 55, active_status: 0, role_id: roleStaff, is_barber: 1 }, { profile_image: png() }));
    trackPhotos();
    const norm = (r) => r.map((v, i) => (i === 5 ? 'by' : v)).join('|').replace(/P4B (Web|Api)2/, 'P4B X');
    const gone = !fs.existsSync(`${STORAGE}/${oldW}`) && !fs.existsSync(`${STORAGE}/${oldA}`);
    const tokensGone = Number(one(`select count(*) from personal_access_tokens where tokenable_id=${ap}`)) === 0;
    const jsonPut = await call('PUT', `/staff/${ap}`, admin, { name: 'P4B Api2', email: E('api'), phone: '5551110002', service_ids: [25, 27], commission: 55, active_status: true, role_id: roleStaff, is_barber: true });
    return { ok: wRes.status === 1 && a.status === 200 && norm(usr(E('web'))) !== '' && gone && jsonPut.status === 200 && svcOf(ap) === '25,27' && (() => { return true; })(), detail: `old files gone ${gone}, json PUT ${jsonPut.status}, services ${svcOf(ap)}` };
  });
  await t('update: same rows as the web (compared before the JSON edit), password optional, keeps the same e-mail, other user\'s e-mail → 422', async () => {
    const w = uid(E('web')), ap = uid(E('api'));
    // bring both back to the same input and compare
    await web.send('PUT', `/admin/staff/${w}`, { staff_name: 'P4B Same', staff_email: E('web'), staff_phone: '5551110003', 'service_id[]': ['25', '28'], commission: '12.5', status: '1', role_id: String(roleStaff), is_barber: '1' });
    const a = await call('POST', `/staff/${ap}`, admin, form({ name: 'P4B Same', email: E('api'), phone: '5551110003', 'service_ids[]': ['25', '28'], commission: 12.5, active_status: 1, role_id: roleStaff, is_barber: 1 }));
    const norm = (r) => r.map((v, i) => (i === 5 || i === 7 ? 'x' : v)).join('|');
    const clash = await call('POST', `/staff/${ap}`, admin, form({ name: 'P4B Same', email: E('web'), active_status: 1, role_id: roleStaff, is_barber: 0 }));
    return { ok: a.status === 200 && norm(usr(E('web'))) === norm(usr(E('api'))) && roleOf(w) === roleOf(ap) && svcOf(w) === svcOf(ap) && clash.status === 422, detail: norm(usr(E('api'))) + ` services ${svcOf(ap)}` };
  });

  // ============================================================ password / sessions
  await t('STAFF-10 password: min 6 + confirmation, old password stops working, old sessions are revoked', async () => {
    const ap = uid(E('api'));
    sql(`update users set active_status=1 where id=${ap}`);
    const tok = await login(E('api'), 'secret1');
    const before = (await call('GET', '/auth/me', tok)).status;
    const short = await call('PUT', `/staff/${ap}/password`, admin, { new_password: '123', confirm_password: '123' });
    const mism = await call('PUT', `/staff/${ap}/password`, admin, { new_password: 'newpass1', confirm_password: 'other' });
    const ok = await call('PUT', `/staff/${ap}/password`, admin, { new_password: 'newpass1', confirm_password: 'newpass1' });
    const after = (await call('GET', '/auth/me', tok)).status;
    const oldPw = (await loginRaw(E('api'), 'secret1')).http, newPw = (await loginRaw(E('api'), 'newpass1')).http;
    const wRes = await web.send('POST', '/admin/change-password', { staff_row_id: String(uid(E('web'))), new_password: 'webpass1', confirm_password: 'webpass1' });
    const webHash = one(`select password like '$2y$%' from users where id=${uid(E('web'))}`);
    const noPerm = await call('PUT', `/staff/${ap}/password`, staff, { new_password: 'newpass1', confirm_password: 'newpass1' });
    return { ok: before === 200 && short.status === 422 && mism.status === 422 && ok.status === 200 && after === 401 && oldPw !== 200 && newPw === 200 && wRes.status === 1 && webHash === '1' && noPerm.status === 403, detail: `session ${before}→${after}, old pw ${oldPw}, new pw ${newPw}, staff user ${noPerm.status}` };
  });
  await t('a deactivated account cannot sign in or keep using the app', async () => {
    const ap = uid(E('api'));
    const tok = await login(E('api'), 'newpass1');
    const edit = await call('POST', `/staff/${ap}`, admin, form({ name: 'P4B Same', email: E('api'), 'service_ids[]': ['25'], active_status: 0, role_id: roleStaff, is_barber: 1, commission: 1 }));
    const use = (await call('GET', '/auth/me', tok)).status, signIn = (await loginRaw(E('api'), 'newpass1')).http;
    return { ok: edit.status === 200 && use === 401 && signIn !== 200, detail: `edit ${edit.status}, old session ${use}, sign-in ${signIn}` };
  });

  // ============================================================ assigned services
  await t('STAFF-11/12 assigned services: GET equals the web, PUT replaces the set (web parity), validation, staff user 403', async () => {
    const ap = uid(E('api')), w = uid(E('web'));
    const wGet = await fetch(webBase + '/admin/staff-service/get-services', { method: 'POST', headers: { Cookie: web.ck(), 'X-Requested-With': 'XMLHttpRequest', 'X-CSRF-TOKEN': web.csrf, 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json' }, body: new URLSearchParams({ staff_id: String(ap) }) }).then((r) => r.json());
    const aGet = await call('GET', `/staff/${ap}/assigned-services`, admin);
    const wSave = await web.send('POST', '/admin/staff-service/save', { staff_id: String(w), 'service_ids[]': ['26', '29', '30'] });
    const aSave = await call('PUT', `/staff/${ap}/assigned-services`, admin, { service_ids: [26, 29, 30] });
    const same = svcOf(w) === svcOf(ap) && svcOf(ap) === '26,29,30' && one(`select service_id from users where id=${ap}`) === '26,29,30';
    const clear = await call('PUT', `/staff/${ap}/assigned-services`, admin, { service_ids: [] });
    const bad = [await call('PUT', `/staff/${ap}/assigned-services`, admin, { service_ids: [999999] }), await call('PUT', `/staff/${ap}/assigned-services`, admin, {}), await call('PUT', '/staff/99999999/assigned-services', admin, { service_ids: [] })].map((r) => r.status);
    const noPerm = (await call('PUT', `/staff/${ap}/assigned-services`, staff, { service_ids: [25] })).status;
    return { ok: wGet.status === 1 && aGet.json.data.service_ids.join() === wGet.service_ids.join() && wSave.status === 1 && aSave.status === 200 && same && clear.status === 200 && !svcOf(ap) && bad[0] === 422 && bad[1] === 422 && bad[2] === 404 && noPerm === 403, detail: `bad ${bad.join('/')}, staff ${noPerm}` };
  });

  // ============================================================ delete
  await t('WRITE PARITY delete: both soft-delete the user and remove the picture; the API also revokes sessions; self and "First available" are refused', async () => {
    const w = uid(E('web')), ap = uid(E('api'));
    const imgs = rows(`select profile_img from users where id in (${w},${ap}) and profile_img is not null`).map((r) => r[0]);
    sql(`update users set active_status=1 where id=${ap}`);
    const tok = await login(E('api'), 'newpass1');
    const wRes = await web.send('DELETE', `/admin/staff/${w}`);
    const a = await call('DELETE', `/staff/${ap}`, admin);
    const soft = (id) => one(`select deleted_at is not null from users where id=${id}`);
    const tokens = Number(one(`select count(*) from personal_access_tokens where tokenable_id=${ap}`));
    const self = await call('DELETE', `/staff/${adminId}`, admin);
    const fa = await call('DELETE', '/staff/19', admin);
    const miss = await call('DELETE', `/staff/${ap}`, admin);
    const noPerm = await call('DELETE', '/staff/49', staff);
    const stillThere = one('select count(*) from users where id=19 and deleted_at is null');
    return { ok: wRes.status === 1 && a.status === 200 && soft(w) === '1' && soft(ap) === '1' && tokens === 0 && imgs.every((p) => !fs.existsSync(`${STORAGE}/${p}`)) && (await call('GET', '/auth/me', tok)).status === 401 && self.status === 404 && fa.status === 409 && stillThere === '1' && miss.status === 404 && noPerm.status === 403, detail: `${a.status}, self ${self.status}, first-available ${fa.status}, again ${miss.status}` };
  });

  // ============================================================ permissions
  await t('permissions: staff user (no Staff-* perms) gets 403 on list, form, create, edit', async () => {
    const out = [(await call('GET', '/staff', staff)).status, (await call('GET', '/staff/form-options', staff)).status, (await call('POST', '/staff', staff, form({ name: 'x' }))).status, (await call('POST', '/staff/49', staff, form({ name: 'x' }))).status, (await call('PUT', '/staff/49/password', staff, {})).status];
    return { ok: out.every((s) => s === 403), detail: out.join('/') };
  });

  // ============================================================ cleanup
  const ids = rows("select id from users where email like 'p4b-%@rosen.test'").map((r) => r[0]);
  if (ids.length) {
    const list = ids.join(',');
    sql(`delete from model_has_roles where model_id in (${list}); delete from tbl_staff_service where staff_id in (${list}); delete b from tbl_breaks b join tbl_slots s on s.id=b.slot_id where s.staff_id in (${list}); delete from tbl_slots where staff_id in (${list}); delete from personal_access_tokens where tokenable_id in (${list}); delete from users where id in (${list});`);
  }
  for (const p of photos) { try { fs.unlinkSync(`${STORAGE}/${p}`); } catch (e) { /* gone */ } }

  const w = Math.max(...results.map((r) => r.name.length));
  console.log('\nPhase 4b tests: staff administration\n');
  for (const r of results) console.log((r.ok ? '  PASS ' : '  FAIL ') + r.name.padEnd(w) + (r.detail ? '  ' + r.detail : ''));
  const failed = results.filter((r) => !r.ok).length;
  console.log(`\n${results.length - failed}/${results.length} passed` + (failed ? `, ${failed} FAILED` : ''));
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
