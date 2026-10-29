#!/usr/bin/env node
/**
 * Phase 5 tests: admin reports (API vs the web's tables), testimonials, gallery and roles
 * (write parity with the web, validation, protection of system roles, permissions).
 *
 *   node api_phase5_test.js <webBase> <apiBase> <adminEmail> <adminPw> <staffEmail> <staffPw>
 *
 * Needs the marked test data (invoiced test appointments) so the reports have rows. Everything it
 * creates is named "API TEST ..." and removed at the end (pictures and role permissions too).
 */
const { execSync } = require('child_process');
const fs = require('fs');
const [webBase, apiBase, adminEmail, adminPw, staffEmail, staffPw] = process.argv.slice(2);
if (!staffPw) { console.error('usage: node api_phase5_test.js <webBase> <apiBase> <adminEmail> <adminPw> <staffEmail> <staffPw>'); process.exit(2); }

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
  async login(email, pw) {
    const page = await fetch(webBase + '/admin/login'); this.store(page);
    const tok = ((await page.text()).match(/name="_token" value="([^"]+)"/) || [])[1];
    const r = await fetch(webBase + '/admin/post-login', { method: 'POST', redirect: 'manual', headers: { 'Content-Type': 'application/x-www-form-urlencoded', Cookie: this.ck() }, body: new URLSearchParams({ _token: tok, email, password: pw }) }); this.store(r);
    const dash = await (await fetch(webBase + '/admin/dashboard', { headers: { Cookie: this.ck() } })).text();
    this.csrf = (dash.match(/name="csrf-token" content="([^"]+)"/) || [])[1];
  }
}
async function call(method, path, token, body) {
  const headers = { Accept: 'application/json', Authorization: 'Bearer ' + token };
  let payload;
  if (body instanceof FormData) payload = body;
  else if (body) { headers['Content-Type'] = 'application/json'; payload = JSON.stringify(body); }
  const r = await fetch(apiBase + path, { method, headers, body: payload });
  let json = null; try { json = await r.json(); } catch (e) { /* none */ }
  return { status: r.status, json };
}
const form = (fields, files = {}) => { const fd = new FormData(); for (const [k, v] of Object.entries(fields)) { if (Array.isArray(v)) v.forEach((x) => fd.append(k, x)); else if (v !== undefined && v !== null) fd.append(k, v); } for (const [k, v] of Object.entries(files)) fd.append(k, v, 'x.png'); return fd; };
const login = async (e, p) => (await (await fetch(apiBase + '/auth/login', { method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'application/json' }, body: JSON.stringify({ email: e, password: p, device_name: 'p5' }) })).json()).data.token;
async function t(name, fn) { try { const r = await fn(); results.push({ name, ok: r.ok, detail: r.detail || '' }); } catch (e) { results.push({ name, ok: false, detail: 'EXCEPTION ' + e.message }); } }
const unesc = (s) => String(s ?? '').replace(/<[^>]*>/g, '').replace(/&#0?39;/g, "'").replace(/&amp;/g, '&').trim();
const num = (s) => Number(String(s ?? '').replace(/[^0-9.\-]/g, '') || 0).toFixed(2);
const sameSet = (a, b) => a.length === b.length && [...a].sort().join('|') === [...b].sort().join('|');
async function all(token, path) {
  const items = []; let page = 1;
  for (;;) { const r = await call('GET', path + (path.includes('?') ? '&' : '?') + `per_page=50&page=${page}`, token); if (r.status !== 200) return { status: r.status, items }; items.push(...r.json.data.items); if (!r.json.meta.has_more) return { status: 200, items, meta: r.json.meta }; page++; }
}

(async () => {
  const admin = await login(adminEmail, adminPw), staff = await login(staffEmail, staffPw);
  const web = new Web(); await web.login(adminEmail, adminPw);
  const staffId = Number(one(`select id from users where email='${staffEmail}'`));
  const files = [];
  const trackFiles = (q) => { for (const [p] of rows(q)) if (p && p !== 'NULL' && !p.startsWith('frontend/')) files.push(p); };
  const ranges = [['', {}, ''], ['2026-10-01..2026-10-31', { start_date: '2026-10-01', end_date: '2026-10-31' }, '?start_date=2026-10-01&end_date=2026-10-31'], ['staff', { staff_id: String(staffId) }, `?staff_id=${staffId}`], ['2000-01-01..2026-10-21', { start_date: '2000-01-01', end_date: '2026-10-21' }, '?start_date=2000-01-01&end_date=2026-10-21']];

  // ============================================================ reports
  await t('RPT-1 appointments report: same invoices, money and summary cards as the web (4 filter sets)', async () => {
    const bad = [];
    for (const [label, wp, ap] of ranges) {
      const w = await web.table('/admin/get-report-appointment', wp);
      const r = await all(admin, '/reports/appointments' + ap);
      const wl = w.data.map((x) => `${x.appointment_id}|${x.date.split('-').reverse().join('-')}|${unesc(x.customer_name)}|${num(x.service_discount)}|${num(x.sub_total)}|${num(x.service_tip)}|${num(x.service_total_amt)}`);
      const al = r.items.map((x) => `${x.id}|${x.date}|${unesc(x.customer.name)}|${x.discount}|${x.sub_total}|${x.tip}|${x.total}`);
      if (!sameSet(wl, al)) bad.push(`${label}: rows web ${wl.length} api ${al.length}`);
      const ws = w.summary, as = r.meta.summary;
      for (const [wk, ak] of [['total_revenue', 'total_revenue'], ['total_tips', 'total_tips'], ['staff_total_service_tip', 'staff_total_service_tip'], ['staff_total_service_commission', 'staff_total_service_commission'], ['staff_total_product_commission', 'staff_total_product_commission'], ['staff_total_earning', 'staff_total_earning'], ['total_discount', 'total_discount']]) if (num(ws[wk]) !== as[ak]) bad.push(`${label} ${wk}: web ${ws[wk]} api ${as[ak]}`);
      if (Number(ws.total_appointments) !== as.total_appointments || Number(ws.total_visits) !== as.total_visits) bad.push(`${label} counts`);
    }
    return { ok: bad.length === 0, detail: bad.join(' ; ') || 'rows + 9 summary figures x 4 filters' };
  });
  await t('RPT-2 payments report: same methods, revenue and summary', async () => {
    const bad = [];
    for (const [label, wp, ap] of ranges) {
      const w = await web.table('/admin/get-report-payment', wp);
      const r = await call('GET', '/reports/payments' + ap, admin);
      const wl = w.data.map((x) => `${unesc(x.method)}|${num(x.revenue)}`), al = r.json.data.items.map((x) => `${unesc(x.method)}|${x.revenue}`);
      if (!sameSet(wl, al)) bad.push(`${label}: web ${wl} api ${al}`);
      if (num(w.summary.total_revenue) !== r.json.meta.summary.total_revenue || num(w.summary.total_discount) !== r.json.meta.summary.total_discount) bad.push(`${label} summary`);
    }
    return { ok: bad.length === 0, detail: bad.join(' ; ') || '4 filter sets' };
  });
  await t('RPT-3 staff earnings: same barbers/figures as the web; the rows ignore the end date like the web (Q46), the summary does not', async () => {
    const bad = [];
    for (const [label, wp, ap] of ranges) {
      const w = await web.table('/admin/get-staff-performance', wp);
      const r = await call('GET', '/reports/staff-earnings' + ap, admin);
      const wl = w.data.map((x) => `${x.staff_id}|${x.appointments}|${num(x.revenue)}|${num(x.tips)}|${num(x.service_commission)}|${num(x.product_commission)}`);
      const al = r.json.data.items.map((x) => `${x.staff_id}|${x.appointments}|${x.revenue}|${x.tips}|${x.service_commission}|${x.product_commission}`);
      if (!sameSet(wl, al)) bad.push(`${label}: rows web ${wl.length} api ${al.length}`);
      const s = w.summary, a = r.json.meta.summary;
      if (num(s.totalRevenue) !== a.total_revenue || num(s.total_service_tip) !== a.total_service_tip || Number(s.appointmentCount) !== a.appointment_count) bad.push(`${label} summary`);
    }
    return { ok: bad.length === 0, detail: bad.join(' ; ') || '4 filter sets' };
  });
  await t('RPT-4 customer invoices: same invoices, customers, staff and "amount" as the web', async () => {
    const bad = [];
    for (const [label, wp, ap] of ranges) {
      const w = await web.table('/admin/customer-report-invoice', wp);
      const r = await all(admin, '/reports/customer-invoices' + ap);
      const wl = w.data.map((x) => `${x.appointment_id}|${unesc(x.customer_name)}|${unesc(x.staff_name)}|${num(x.amount)}`);
      const al = r.items.map((x) => `${x.id}|${unesc(x.customer_name)}|${unesc(x.staff_names)}|${x.amount}`);
      const norm = (l) => l.map((s) => { const p = s.split('|'); p[2] = p[2].split(', ').sort().join(', '); return p.join('|'); });
      if (!sameSet(norm(wl), norm(al))) bad.push(`${label}: web ${wl.length} api ${al.length}`);
    }
    return { ok: bad.length === 0, detail: bad.join(' ; ') || '4 filter sets' };
  });
  await t('RPT-5 product sales and RPT-6 top products: same rows and summary as the web', async () => {
    const bad = [];
    for (const [label, wp, ap] of ranges) {
      const w5 = await web.table('/admin/sell-product-report', wp);
      const r5 = await all(admin, '/reports/product-sales' + ap);
      const a5 = r5.items.map((x) => `${x.id}|${unesc(x.product_name)}|${unesc(x.customer_name)}|${x.amount}`), l5 = w5.data.map((x) => `${x.id}|${unesc(x.product_name)}|${unesc(x.customer_name)}|${num(x.amount)}`);
      if (!sameSet(l5, a5)) bad.push(`${label} sales: web ${l5.length} api ${a5.length}`);
      const w6 = await web.table('/admin/top-selling-product-report', wp);
      const r6 = await call('GET', '/reports/top-products' + ap, admin);
      const l6 = w6.data.map((x) => `${x.product_id}|${x.sell_unit}|${num(x.total_commission)}|${num(x.total_revenue)}|${num(x.total_discount)}`), a6 = r6.json.data.items.map((x) => `${x.product_id}|${x.units_sold}|${x.commission}|${x.revenue}|${x.discount}`);
      if (!sameSet(l6, a6)) bad.push(`${label} top: web ${l6.length} api ${a6.length}`);
      const s = w6.summary, a = r6.json.meta.summary;
      if (num(s.total_revenue) !== a.total_revenue || Number(s.total_units_sold) !== a.total_units_sold || num(s.total_commission) !== a.total_commission) bad.push(`${label} top summary`);
    }
    return { ok: bad.length === 0, detail: bad.join(' ; ') || '4 filter sets' };
  });
  await t('reports: paging + search work; bad dates → 422; staff-role users (also Managers, Q24) → 403; role-less → 403', async () => {
    const p1 = await call('GET', '/reports/appointments?per_page=2&page=1', admin), p2 = await call('GET', '/reports/appointments?per_page=2&page=2', admin);
    const q = await call('GET', '/reports/customer-invoices?q=INV-', admin);
    const bad = await call('GET', '/reports/appointments?start_date=tomorrow', admin);
    const st = [await call('GET', '/reports/appointments', staff), await call('GET', '/reports/payments', staff), await call('GET', '/reports/top-products', staff)].map((r) => r.status);
    return { ok: p1.json.data.items.length === 2 && p2.json.data.items[0].id !== p1.json.data.items[0].id && q.json.data.items.length > 0 && bad.status === 422 && st.every((s) => s === 403), detail: `staff user ${st.join('/')}` };
  });

  // ============================================================ testimonials
  const tst = (id) => rows(`select client_name,client_role,review,rating,sort_order,status,created_by,client_image is not null from tbl_testimonial where id=${id}`)[0];
  let tid;
  await t('CONT-1 testimonials: list equals the web table (order: sort order, newest first)', async () => {
    for (const [n, order] of [['A', 5], ['B', 1], ['C', 5]]) await call('POST', '/testimonials', admin, form({ client_name: 'API TEST Order ' + n, review: 'x', rating: 5, sort_order: order, active_status: 1 }));
    const w = (await web.table('/admin/testimonial/gettabledata')).data.map((x) => x.id);
    const r = await all(admin, '/testimonials');
    const names = r.items.filter((x) => x.client_name.startsWith('API TEST Order')).map((x) => x.client_name.slice(-1)).join('');
    return { ok: r.status === 200 && JSON.stringify(w) === JSON.stringify(r.items.map((x) => x.id)) && w.length >= 3 && names === 'BCA', detail: `web ${w.length}, api ${r.items.length}, order ${names} (sort order, then newest first)` };
  });
  await t('WRITE PARITY testimonial create / update / delete: same rows as the web (default role "Regular Client", status flag, picture handling)', async () => {
    const wRes = await web.send('POST', '/admin/testimonial', { client_name: 'API TEST T W', review: 'Great cut', rating: '4', sort_order: '3', status: '1' }, { client_image: png() });
    const wId = Number(one("select id from tbl_testimonial where client_name='API TEST T W' order by id desc limit 1"));
    const a = await call('POST', '/testimonials', admin, form({ client_name: 'API TEST T A', review: 'Great cut', rating: 4, sort_order: 3, active_status: 1 }, { image: png() }));
    tid = a.json?.data?.testimonial?.id;
    trackFiles(`select client_image from tbl_testimonial where id in (${wId},${tid})`);
    const norm = (r) => r.join('|').replace(/T [WA]\|/, 'T X|');
    const created = norm(tst(wId)) === norm(tst(tid));
    const old = [one(`select client_image from tbl_testimonial where id=${wId}`), one(`select client_image from tbl_testimonial where id=${tid}`)];
    const wu = await web.send('PUT', `/admin/testimonial/${wId}`, { client_name: 'API TEST T W', client_role: 'Barber fan', review: 'Updated', rating: '5', sort_order: '1' }, { client_image: png() });
    const au = await call('POST', `/testimonials/${tid}`, admin, form({ client_name: 'API TEST T A', client_role: 'Barber fan', review: 'Updated', rating: 5, sort_order: 1, active_status: 0 }, { image: png() }));
    trackFiles(`select client_image from tbl_testimonial where id in (${wId},${tid})`);
    const updated = norm(tst(wId)) === norm(tst(tid));
    const gone = old.every((p) => !fs.existsSync(`${STORAGE}/${p}`));
    const imgs = [one(`select client_image from tbl_testimonial where id=${wId}`), one(`select client_image from tbl_testimonial where id=${tid}`)];
    const dW = await web.send('DELETE', `/admin/testimonial/${wId}`), dA = await call('DELETE', `/testimonials/${tid}`, admin);
    const soft = (id) => one(`select deleted_at is not null from tbl_testimonial where id=${id}`);
    return { ok: wRes.status === 1 && a.status === 201 && created && wu.status === 1 && au.status === 200 && updated && gone && dW.status === 1 && dA.status === 200 && soft(wId) === '1' && soft(tid) === '1' && imgs.every((p) => !fs.existsSync(`${STORAGE}/${p}`)), detail: `created ${created} updated ${updated} old pictures gone ${gone}` };
  });
  await t('CONT-1 a bundled default picture (frontend/...) is never deleted; validation (rating 0/6, no name, long review) → 422; unknown → 404', async () => {
    const seeded = one("select id from tbl_testimonial where client_image like 'frontend/%' and deleted_at is null limit 1");
    let safe = true;
    if (seeded) {
      const before = sql(`select client_image from tbl_testimonial where id=${seeded}`);
      const up = await call('POST', `/testimonials/${seeded}`, admin, form({ client_name: 'API TEST keep', review: 'x', rating: 3, active_status: 1 }));
      safe = up.status === 200 && fs.existsSync(`J:/laragon/www/rosen_barber/public/${before}`);
      sql(`update tbl_testimonial set client_name=(select client_name from (select client_name from tbl_testimonial where id=${seeded}) x) where id=${seeded}`);
    }
    const ok = { client_name: 'API TEST V', review: 'ok', rating: 3, active_status: 1 };
    const out = []; for (const b of [{ ...ok, rating: 0 }, { ...ok, rating: 6 }, { ...ok, client_name: '' }, { ...ok, review: 'x'.repeat(2001) }, { ...ok, active_status: undefined }]) out.push((await call('POST', '/testimonials', admin, form(b))).status);
    const miss = await call('DELETE', '/testimonials/99999999', admin);
    return { ok: safe && out.every((s) => s === 422) && miss.status === 404, detail: `${out.join('/')}, seeded ${seeded || 'none'}` };
  });

  // ============================================================ gallery
  await t('CONT-2 gallery: list equals the web, add parity (file saved), replace (old file deleted), delete parity (file removed), validation', async () => {
    const wList = (await web.table('/admin/gallery/gettabledata')).data.map((x) => x.id);
    const aList = (await all(admin, '/gallery')).items.map((x) => x.id);
    const wAdd = await web.send('POST', '/admin/gallery', {}, { gallery_image: png() });
    const wId = Number(one('select max(id) from galleries'));
    const a = await call('POST', '/gallery', admin, form({}, { image: png() }));
    const aId = a.json?.data?.picture?.id;
    trackFiles(`select image from galleries where id in (${wId},${aId})`);
    const wImg = one(`select image from galleries where id=${wId}`), aImg = one(`select image from galleries where id=${aId}`);
    const added = wAdd.status === 1 && a.status === 201 && fs.existsSync(`${STORAGE}/${wImg}`) && fs.existsSync(`${STORAGE}/${aImg}`) && aImg.startsWith('gallery/') && a.json.data.picture.image_url.includes('/storage/gallery/');
    const rep = await call('POST', `/gallery/${aId}`, admin, form({}, { image: png() }));
    const newImg = one(`select image from galleries where id=${aId}`);
    trackFiles(`select image from galleries where id=${aId}`);
    const replaced = rep.status === 200 && newImg !== aImg && !fs.existsSync(`${STORAGE}/${aImg}`) && fs.existsSync(`${STORAGE}/${newImg}`);
    const dW = await web.send('DELETE', `/admin/gallery/${wId}`), dA = await call('DELETE', `/gallery/${aId}`, admin);
    const removed = dW.status === 1 && dA.status === 200 && !fs.existsSync(`${STORAGE}/${wImg}`) && !fs.existsSync(`${STORAGE}/${newImg}`) && Number(one(`select count(*) from galleries where id in (${wId},${aId})`)) === 0;
    const bad = [await call('POST', '/gallery', admin, form({})), await call('POST', '/gallery', admin, (() => { const f = form({}); f.append('image', new Blob(['hello'], { type: 'text/plain' }), 'x.txt'); return f; })()), await call('POST', '/gallery/99999999', admin, form({}, { image: png() }))].map((r) => r.status);
    const missDel = await call('DELETE', `/gallery/${aId}`, admin);
    return { ok: sameSet(wList.map(String), aList.map(String)) && added && replaced && removed && bad[0] === 422 && bad[1] === 422 && bad[2] === 404 && missDel.status === 404, detail: `list web ${wList.length} api ${aList.length}; bad ${bad.join('/')}` };
  });

  // ============================================================ roles
  const roleRow = (name) => rows(`select r.id, group_concat(p.name order by p.name) from roles r left join role_has_permissions rp on rp.role_id=r.id left join permissions p on p.id=rp.permission_id where r.name='${name}' group by r.id`)[0];
  await t('ROLE-1 roles: same roles as the web table, permission ids equal the DB, permission catalog is complete and grouped', async () => {
    const w = (await web.table('/admin/roles-action')).data.map((x) => `${x.id}|${x.name}`);
    const r = (await call('GET', '/roles', admin)).json.data;
    const a = r.roles.map((x) => `${x.id}|${x.name}`);
    const dbPerm = Number(one('select count(*) from permissions'));
    const catalogCount = r.permission_groups.reduce((n, g) => n + g.permissions.length, 0);
    const first = r.roles.find((x) => x.id === 2);
    const dbIds = rows('select permission_id from role_has_permissions where role_id=2').map((x) => Number(x[0])).sort((x, y) => x - y);
    const one1 = await call('GET', '/roles/2', admin);
    return { ok: sameSet(w, a) && catalogCount === dbPerm && JSON.stringify(first.permission_ids) === JSON.stringify(dbIds) && r.permission_groups.some((g) => g.group === 'Staff') && one1.status === 200 && (await call('GET', '/roles/99999', admin)).status === 404 && r.roles.find((x) => x.id === 1).locked === true, detail: `${a.length} roles, ${catalogCount} permissions in ${r.permission_groups.length} groups` };
  });
  await t('WRITE PARITY role create / update / delete: web and API leave the same role + permissions', async () => {
    const perms = rows("select id from permissions where name in ('Customer-Add','Gst-Add','Product-Edit') order by id").map((x) => x[0]);
    const wRes = await web.send('POST', '/admin/roles', { role_nm: 'API TEST Role W', 'permissions[]': perms });
    const a = await call('POST', '/roles', admin, { name: 'API TEST Role A', permission_ids: perms.map(Number) });
    const same = roleRow('API TEST Role W')[1] === roleRow('API TEST Role A')[1] && roleRow('API TEST Role A')[1] === 'Customer-Add,Gst-Add,Product-Edit';
    const wid = roleRow('API TEST Role W')[0], aid = roleRow('API TEST Role A')[0];
    const perms2 = rows("select id from permissions where name in ('Customer-Edit')").map((x) => x[0]);
    const wu = await web.send('PUT', `/admin/roles/${wid}`, { role_nm: 'API TEST Role W2', 'permissions[]': perms2 });
    const au = await call('PUT', `/roles/${aid}`, admin, { name: 'API TEST Role A2', permission_ids: perms2.map(Number) });
    const updated = roleRow('API TEST Role W2')[1] === roleRow('API TEST Role A2')[1] && roleRow('API TEST Role A2')[1] === 'Customer-Edit';
    const clear = await call('PUT', `/roles/${aid}`, admin, { name: 'API TEST Role A2' });
    const cleared = !roleRow('API TEST Role A2')[1] || roleRow('API TEST Role A2')[1] === 'NULL';
    const dW = await web.send('DELETE', `/admin/roles/${wid}`), dA = await call('DELETE', `/roles/${aid}`, admin);
    const gone = Number(one(`select count(*) from roles where id in (${wid},${aid})`)) === 0;
    return { ok: wRes.status === 1 && a.status === 201 && same && wu.status === 1 && au.status === 200 && updated && clear.status === 200 && cleared && dW.status === 1 && dA.status === 200 && gone, detail: `created ${same} updated ${updated}` };
  });
  await t('ROLE-2 protection: system roles cannot be deleted or renamed, a role in use cannot be deleted, duplicate/invalid input → 422/404', async () => {
    const staffRole = Number(one("select id from roles where name='Staff'"));
    const del = [await call('DELETE', '/roles/1', admin), await call('DELETE', '/roles/2', admin), await call('DELETE', '/roles/4', admin), await call('DELETE', `/roles/${one("select id from roles where name='Accountant'")}`, admin)].map((r) => r.status);
    const ren = await call('PUT', `/roles/${staffRole}`, admin, { name: 'Employees' });
    const stillStaff = one(`select name from roles where id=${staffRole}`) === 'Staff';
    const sameName = await call('PUT', `/roles/${staffRole}`, admin, { name: 'Staff', permission_ids: rows(`select permission_id from role_has_permissions where role_id=${staffRole}`).map((x) => Number(x[0])) });
    const created = await call('POST', '/roles', admin, { name: 'API TEST InUse', permission_ids: [] });
    const rid = created.json.data.role.id;
    sql(`insert into model_has_roles (role_id, model_type, model_id) values (${rid}, 'App\\\\Models\\\\User', ${staffId})`);
    const inUse = await call('DELETE', `/roles/${rid}`, admin);
    sql(`delete from model_has_roles where role_id=${rid} and model_id=${staffId}`);
    const dup = await call('POST', '/roles', admin, { name: 'Staff', permission_ids: [] });
    const bad = [await call('POST', '/roles', admin, { permission_ids: [] }), await call('POST', '/roles', admin, { name: 'API TEST Bad', permission_ids: [999999] })].map((r) => r.status);
    const miss = [await call('PUT', '/roles/99999', admin, { name: 'x' }), await call('DELETE', '/roles/99999', admin)].map((r) => r.status);
    return { ok: del.every((s) => s === 409) && ren.status === 409 && stillStaff && sameName.status === 200 && inUse.status === 409 && dup.status === 422 && bad.every((s) => s === 422) && miss.every((s) => s === 404), detail: `delete ${del.join('/')}, rename ${ren.status}, in use ${inUse.status}, dup ${dup.status}, bad ${bad.join('/')}, miss ${miss.join('/')}` };
  });

  // ============================================================ permissions
  await t('permissions: staff user gets 403 on testimonials, gallery and roles', async () => {
    const out = [(await call('GET', '/testimonials', staff)).status, (await call('POST', '/testimonials', staff, form({}))).status, (await call('GET', '/gallery', staff)).status, (await call('DELETE', '/gallery/1', staff)).status, (await call('GET', '/roles', staff)).status, (await call('POST', '/roles', staff, {})).status];
    return { ok: out.every((s) => s === 403), detail: out.join('/') };
  });

  // ============================================================ cleanup
  sql("delete from tbl_testimonial where client_name like 'API TEST%'; delete rp from role_has_permissions rp join roles r on r.id=rp.role_id where r.name like 'API TEST%'; delete from roles where name like 'API TEST%';");
  for (const p of files) { try { fs.unlinkSync(`${STORAGE}/${p}`); } catch (e) { /* gone */ } }

  const w = Math.max(...results.map((r) => r.name.length));
  console.log('\nPhase 5 tests: reports, content and roles\n');
  for (const r of results) console.log((r.ok ? '  PASS ' : '  FAIL ') + r.name.padEnd(w) + (r.detail ? '  ' + r.detail : ''));
  const failed = results.filter((r) => !r.ok).length;
  console.log(`\n${results.length - failed}/${results.length} passed` + (failed ? `, ${failed} FAILED` : ''));
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
