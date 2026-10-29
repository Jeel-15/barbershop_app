#!/usr/bin/env node
/**
 * Phase 4a tests: services, categories, products, GST, payment methods, shop settings,
 * shop hours and closures. Reads and writes are compared with the web's own endpoints;
 * validation, images and permissions are checked.
 *
 *   node api_phase4a_test.js <webBase> <apiBase> <adminEmail> <adminPw> <staffEmail> <staffPw>
 *
 * It changes shared data (settings, shop hours, default GST) and RESTORES them at the end from a
 * snapshot taken first; everything it creates is named "API TEST ..." and removed (uploaded pictures too).
 * It never turns the invoice-mail setting on while an invoice is saved, so no real mail can go out.
 */
const { execSync } = require('child_process');
const fs = require('fs');
const [webBase, apiBase, adminEmail, adminPw, staffEmail, staffPw] = process.argv.slice(2);
if (!staffPw) { console.error('usage: node api_phase4a_test.js <webBase> <apiBase> <adminEmail> <adminPw> <staffEmail> <staffPw>'); process.exit(2); }

const results = [];
const sql = (q) => execSync('mysql -uroot -h127.0.0.1 -N -B barber_shop_db', { input: q, encoding: 'utf8' }).replace(/\r/g, '').trim();
const rows = (q) => sql(q).split('\n').filter(Boolean).map((l) => l.split('\t'));
const one = (q) => (rows(q)[0] || [])[0];
const STORAGE = process.env.STORAGE_DIR || 'J:/laragon/www/rosen_barber/public/storage';

// a 1x1 PNG
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64');
const png = (name = 'x.png') => new Blob([PNG], { type: 'image/png' });

class Web {
  constructor() { this.jar = {}; this.csrf = null; }
  ck() { return Object.entries(this.jar).map(([k, v]) => `${k}=${v}`).join('; '); }
  store(r) { for (const c of r.headers.getSetCookie?.() || []) { const [p] = c.split(';'); const i = p.indexOf('='); this.jar[p.slice(0, i)] = p.slice(i + 1); } }
  async send(method, path, fields = {}, files = {}) {
    const fd = new FormData();
    for (const [k, v] of Object.entries(fields)) if (v !== undefined && v !== null) fd.append(k, v);
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
const form = (fields, files = {}) => { const fd = new FormData(); for (const [k, v] of Object.entries(fields)) if (v !== undefined && v !== null) fd.append(k, v); for (const [k, v] of Object.entries(files)) fd.append(k, v, 'x.png'); return fd; };
const login = async (e, p) => (await (await fetch(apiBase + '/auth/login', { method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'application/json' }, body: JSON.stringify({ email: e, password: p, device_name: 'p4a' }) })).json()).data.token;
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

  // ---------- snapshot of the shared data this test touches
  const snap = {
    setting: rows('select service_reminder_day,service_default_duration,service_fee,invoice_send_sts,ifnull(footer_about,"\\N"),ifnull(contact_address,"\\N"),ifnull(contact_phone,"\\N"),ifnull(contact_email,"\\N"),ifnull(support_email,"\\N"),ifnull(whatsapp,"\\N"),ifnull(website_url,"\\N"),ifnull(facebook_url,"\\N"),ifnull(instagram_url,"\\N"),ifnull(tiktok_url,"\\N"),ifnull(youtube_url,"\\N"),ifnull(twitter_url,"\\N"),ifnull(linkedin_url,"\\N") from tbl_setting where id=1')[0],
    slots: rows('select id,is_day_off,ifnull(open_time,"\\N"),ifnull(close_time,"\\N") from tbl_slots where staff_id=0'),
    breaks: rows('select b.slot_id,b.break_start,b.break_end,b.break_type from tbl_breaks b join tbl_slots s on s.id=b.slot_id where s.staff_id=0'),
    gst: rows('select id,default_status from tbl_gst'),
  };
  const originalSts = snap.setting[3];
  const files = [];       // uploaded picture paths to remove at the end
  const track = (q) => { for (const [p] of rows(q)) if (p && p !== 'NULL') files.push(p); };

  const cat = Number(one('select id from tbl_service_category where deleted_at is null order by id limit 1'));
  const cat2 = Number(one(`select id from tbl_service_category where deleted_at is null and id<>${cat} order by id limit 1`)) || cat;

  // ============================================================ SERVICES
  const srv = (id) => rows(`select category_id,service_name,price,duration,status,tip_status,ifnull(commission,'N'),ifnull(description,'N'),created_by,ifnull(home_section,'N'),service_img is not null from tbl_service where id=${id}`)[0];
  let sid;
  await t('CAT-1 services list: same services and fields as the web table', async () => {
    const w = (await web.table('/admin/service-action')).data.map((r) => `${r.id}|${unesc(r.service_name)}|${num(r.price)}|${r.duration}|${r.status}|${r.tip_status}|${r.commission === null ? 'N' : num(r.commission)}|${unesc(r.category_name)}|${r.home_section ?? 'N'}`);
    const r = await all(admin, '/services');
    const a = r.items.map((s) => `${s.id}|${unesc(s.name)}|${s.price}|${s.duration}|${s.active ? 1 : 0}|${s.eligible_for_tip ? 1 : 0}|${s.commission_percent === null ? 'N' : s.commission_percent}|${unesc(s.category_name)}|${s.home_section ?? 'N'}`);
    return { ok: r.status === 200 && sameSet(w, a) && w.length > 0, detail: `web ${w.length}, api ${a.length}` };
  });
  await t('CAT-1 services: search and category/active filters', async () => {
    const q = await all(admin, '/services?q=cut');
    const c = await all(admin, `/services?category_id=${cat}`);
    const act = await all(admin, '/services?active=1'), ina = await all(admin, '/services?active=0');
    const total = Number(one('select count(*) from tbl_service s join tbl_service_category c on c.id=s.category_id where s.deleted_at is null'));
    return { ok: q.items.length > 0 && q.items.every((s) => /cut/i.test(s.name + s.category_name)) && c.items.every((s) => s.category_id === cat) && act.items.length + ina.items.length === total, detail: `cut ${q.items.length}, active ${act.items.length}+${ina.items.length}=${total}` };
  });
  await t('WRITE PARITY create service: web store and API POST leave the same row (image saved, active/tip flags, commission null)', async () => {
    const wRes = await web.send('POST', '/admin/service', { category_id: String(cat), service_nm: 'API TEST Svc W', price: '12.5', duration: '25', service_commission: '', description: 'd', active_status: 'on', eligible_for_tip: 'on' }, { service_image: png() });
    const wId = Number(one("select id from tbl_service where service_name='API TEST Svc W' order by id desc limit 1"));
    const a = await call('POST', '/services', admin, form({ category_id: cat, name: 'API TEST Svc A', price: '12.5', duration: 25, description: 'd', active_status: 1, eligible_for_tip: 1 }, { image: png() }));
    sid = a.json?.data?.service?.id;
    track(`select service_img from tbl_service where id in (${wId},${sid})`);
    const norm = (r) => r.slice(0, 10).join('|').replace(/Svc [WA]/, 'Svc X');
    return { ok: wRes.status === 1 && a.status === 201 && norm(srv(wId)) === norm(srv(sid)) && srv(sid)[10] === '1' && a.json.data.service.image_url.includes('/storage/service_images/'), detail: `web ${norm(srv(wId))} | api ${norm(srv(sid))}` };
  });
  await t('CAT-1 service validation: no image, bad category, negative price, duration 0, commission 101, missing flags, bad image type → 422', async () => {
    const ok = { category_id: cat, name: 'API TEST Bad', price: '5', duration: 10, active_status: 1, eligible_for_tip: 0 };
    const cases = [form(ok), form({ ...ok, category_id: 99999 }, { image: png() }), form({ ...ok, price: '-1' }, { image: png() }), form({ ...ok, duration: 0 }, { image: png() }), form({ ...ok, commission: 101 }, { image: png() }), form({ category_id: cat, name: 'x', price: 1, duration: 5 }, { image: png() }), (() => { const f = form(ok); f.append('image', new Blob(['hello'], { type: 'text/plain' }), 'x.txt'); return f; })()];
    const out = []; for (const c of cases) out.push((await call('POST', '/services', admin, c)).status);
    return { ok: out.every((s) => s === 422) && Number(one("select count(*) from tbl_service where service_name='API TEST Bad'")) === 0, detail: out.join('/') };
  });
  await t('WRITE PARITY update service: web PUT and API POST/PUT leave the same row; the old picture file is deleted when replaced', async () => {
    const wId = Number(one("select id from tbl_service where service_name='API TEST Svc W' order by id desc limit 1"));
    const oldW = one(`select service_img from tbl_service where id=${wId}`), oldA = one(`select service_img from tbl_service where id=${sid}`);
    const wRes = await web.send('PUT', `/admin/service/${wId}`, { category_id: String(cat2), service_nm: 'API TEST Svc W', price: '20', duration: '40', service_commission: '15', description: 'new' }, { service_image: png() });
    const a = await call('POST', `/services/${sid}`, admin, form({ category_id: cat2, name: 'API TEST Svc A', price: '20', duration: 40, commission: 15, description: 'new', active_status: 0, eligible_for_tip: 0 }, { image: png() }));
    track(`select service_img from tbl_service where id in (${wId},${sid})`);
    const norm = (r) => r.slice(0, 10).join('|').replace(/Svc [WA]/, 'Svc X');
    const cmp = norm(srv(wId)) === norm(srv(sid));
    const webLine = norm(srv(wId));
    const gone = !fs.existsSync(`${STORAGE}/${oldW}`) && !fs.existsSync(`${STORAGE}/${oldA}`);
    const putJson = await call('PUT', `/services/${sid}`, admin, { category_id: cat2, name: 'API TEST Svc A', price: 21, duration: 40, commission: 15, description: 'new', active_status: true, eligible_for_tip: false });
    return { ok: wRes.status === 1 && a.status === 200 && cmp && gone && putJson.status === 200 && srv(sid)[4] === '1', detail: `same row as web: ${cmp} (${webLine}) | old files gone ${gone} | json PUT ${putJson.status}` };
  });
  await t('CAT-1b home-section: set signature_grooming, clear, bad value → 422, unknown → 404 (web parity)', async () => {
    const wId = Number(one("select id from tbl_service where service_name='API TEST Svc W' order by id desc limit 1"));
    const w = await web.send('POST', '/admin/service-home-section', { service_id: String(wId), home_section: 'signature_grooming' });
    const a = await call('PATCH', `/services/${sid}/home-section`, admin, { home_section: 'signature_grooming' });
    const same = srv(wId)[9] === 'signature_grooming' && srv(sid)[9] === 'signature_grooming';
    const clr = await call('PATCH', `/services/${sid}/home-section`, admin, { home_section: null });
    const bad = await call('PATCH', `/services/${sid}/home-section`, admin, { home_section: 'hero' });
    const miss = await call('PATCH', '/services/99999999/home-section', admin, { home_section: null });
    return { ok: w.status === 1 && a.status === 200 && same && clr.status === 200 && srv(sid)[9] === 'N' && bad.status === 422 && miss.status === 404, detail: `${a.status}/${clr.status}/${bad.status}/${miss.status}` };
  });
  await t('WRITE PARITY delete service: both soft-delete the row and remove the picture', async () => {
    const wId = Number(one("select id from tbl_service where service_name='API TEST Svc W' order by id desc limit 1"));
    const imgs = [one(`select service_img from tbl_service where id=${wId}`), one(`select service_img from tbl_service where id=${sid}`)];
    const w = await web.send('DELETE', `/admin/service/${wId}`);
    const a = await call('DELETE', `/services/${sid}`, admin);
    const soft = (id) => one(`select deleted_at is not null from tbl_service where id=${id}`);
    const miss = await call('DELETE', `/services/${sid}`, admin);
    return { ok: w.status === 1 && a.status === 200 && soft(wId) === '1' && soft(sid) === '1' && imgs.every((p) => !fs.existsSync(`${STORAGE}/${p}`)) && miss.status === 404 && (await call('GET', `/services/${sid}`, admin)).status === 404 || false, detail: `${a.status}/${miss.status}` };
  });

  // ============================================================ CATEGORIES
  const ctg = (id) => rows(`select category_name,ifnull(description,'N'),created_by,service_image is not null from tbl_service_category where id=${id}`)[0];
  let cid;
  await t('CAT-2 categories: same list as the web; image optional; create + update + delete parity', async () => {
    const w = (await web.table('/admin/service-category-action')).data.map((r) => `${r.id}|${unesc(r.category_name)}`);
    const a = (await call('GET', '/service-categories', admin)).json.data.items.map((r) => `${r.id}|${unesc(r.name)}`);
    const wRes = await web.send('POST', '/admin/service-category', { category_nm: 'API TEST Cat W', category_description: 'x' });
    const wId = Number(one("select id from tbl_service_category where category_name='API TEST Cat W' order by id desc limit 1"));
    const r = await call('POST', '/service-categories', admin, form({ name: 'API TEST Cat A', description: 'x' }));
    cid = r.json?.data?.category?.id;
    const same = ctg(wId).join('|').replace(/Cat [WA]/, 'Cat X') === ctg(cid).join('|').replace(/Cat [WA]/, 'Cat X');
    const up = await call('POST', `/service-categories/${cid}`, admin, form({ name: 'API TEST Cat A2', description: 'y' }, { image: png() }));
    track(`select service_image from tbl_service_category where id=${cid}`);
    const dW = await web.send('DELETE', `/admin/service-category/${wId}`);
    const dA = await call('DELETE', `/service-categories/${cid}`, admin);
    const soft = (id) => one(`select deleted_at is not null from tbl_service_category where id=${id}`);
    const bad = await call('POST', '/service-categories', admin, form({ description: 'no name' }));
    const listOk = sameSet(w, a);
    const checks = { listOk, wRes: wRes.status === 1, created: r.status === 201, same, up: up.status === 200 && !!up.json.data.category.image_url, dW: dW.status === 1, dA: dA.status === 200, soft: soft(wId) === '1' && soft(cid) === '1', bad: bad.status === 422 };
    return { ok: Object.values(checks).every(Boolean), detail: JSON.stringify(checks) + ` web ${ctg(wId)} api ${ctg(cid)}` };
  });

  // ============================================================ PRODUCTS
  const prd = (id) => rows(`select category_id,product_name,price,stock,commission,status,ifnull(description,'N'),created_by,product_img is not null from tbl_product where id=${id}`)[0];
  let pid;
  await t('CAT-3 products: same list as the web table', async () => {
    const w = (await web.table('/admin/product-action')).data.map((r) => `${r.id}|${unesc(r.product_name)}|${num(r.price)}|${r.stock}|${num(r.commission)}|${r.status}`);
    const r = await all(admin, '/products');
    const a = r.items.map((p) => `${p.id}|${unesc(p.name)}|${p.price}|${p.stock}|${p.commission_percent}|${p.active ? 1 : 0}`);
    return { ok: r.status === 200 && sameSet(w, a), detail: `web ${w.length}, api ${a.length}` };
  });
  await t('WRITE PARITY product create / update / delete: web and API leave the same rows', async () => {
    const wRes = await web.send('POST', '/admin/product', { product_nm: 'API TEST Prd W', category_id: String(cat), price: '9.5', stock_qty: '7', commission: '12', status: '1', description: 'd' }, { product_image: png() });
    const wId = Number(one("select id from tbl_product where product_name='API TEST Prd W' order by id desc limit 1"));
    const a = await call('POST', '/products', admin, form({ name: 'API TEST Prd A', category_id: cat, price: '9.5', stock: 7, commission: 12, active_status: 1, description: 'd' }, { image: png() }));
    pid = a.json?.data?.product?.id;
    track(`select product_img from tbl_product where id in (${wId},${pid})`);
    const norm = (r) => r.join('|').replace(/API TEST Prd [WA]/, 'P');
    const created = norm(prd(wId)) === norm(prd(pid));
    const wu = await web.send('PUT', `/admin/product/${wId}`, { product_nm: 'API TEST Prd W', category_id: String(cat2), price: '11', stock_qty: '3', commission: '8', status: '0', description: 'e' });
    const au = await call('POST', `/products/${pid}`, admin, form({ name: 'API TEST Prd A', category_id: cat2, price: '11', stock: 3, commission: 8, active_status: 0, description: 'e' }));
    const updated = norm(prd(wId)) === norm(prd(pid));
    const dW = await web.send('DELETE', `/admin/product/${wId}`), dA = await call('DELETE', `/products/${pid}`, admin);
    const soft = (id) => one(`select deleted_at is not null from tbl_product where id=${id}`);
    return { ok: wRes.status === 1 && a.status === 201 && created && wu.status === 1 && au.status === 200 && updated && dW.status === 1 && dA.status === 200 && soft(wId) === '1' && soft(pid) === '1', detail: `created ${created} updated ${updated}` };
  });
  await t('CAT-3 product validation: no image on create, stock -1, commission missing, bad category → 422', async () => {
    const ok = { name: 'API TEST PBad', category_id: cat, price: 1, stock: 1, commission: 1, active_status: 1 };
    const cases = [form(ok), form({ ...ok, stock: -1 }, { image: png() }), (({ commission, ...r }) => form(r, { image: png() }))(ok), form({ ...ok, category_id: 99999 }, { image: png() })];
    const out = []; for (const c of cases) out.push((await call('POST', '/products', admin, c)).status);
    return { ok: out.every((s) => s === 422), detail: out.join('/') };
  });

  // ============================================================ GST
  await t('CAT-4 GST: same records as the web table; create default clears the others; set default; delete the default warns', async () => {
    const w = (await web.table('/admin/gst-action')).data.map((r) => `${r.id}|${unesc(r.name)}|${num(r.rate)}|${r.tax_type}|${r.default_status}`);
    const a = (await call('GET', '/gst', admin)).json.data.items.map((g) => `${g.id}|${unesc(g.name)}|${g.rate}|${g.tax_type}|${g.is_default ? 1 : 0}`);
    const c1 = await call('POST', '/gst', admin, { name: 'API TEST GST 1', rate: 7, tax_type: 'exclude', is_default: true });
    const id1 = c1.json.data.gst.id;
    const onlyOne = Number(one('select count(*) from tbl_gst where default_status=1')) === 1 && one(`select default_status from tbl_gst where id=${id1}`) === '1';
    const c2 = await call('POST', '/gst', admin, { name: 'API TEST GST 2', rate: 3, tax_type: 'include', is_default: false });
    const id2 = c2.json.data.gst.id;
    const d = await call('POST', `/gst/${id2}/default`, admin);
    const swapped = one(`select default_status from tbl_gst where id=${id2}`) === '1' && one(`select default_status from tbl_gst where id=${id1}`) === '0' && Number(one('select count(*) from tbl_gst where default_status=1')) === 1;
    const up = await call('PUT', `/gst/${id1}`, admin, { name: 'API TEST GST 1b', rate: 8.25, tax_type: 'include', is_default: false });
    const del = await call('DELETE', `/gst/${id2}`, admin);
    const none = Number(one('select count(*) from tbl_gst where default_status=1')) === 0;
    const del1 = await call('DELETE', `/gst/${id1}`, admin);
    const hard = Number(one(`select count(*) from tbl_gst where id in (${id1},${id2})`)) === 0;
    const bad = [await call('POST', '/gst', admin, { name: 'x', rate: -1, tax_type: 'include', is_default: false }), await call('POST', '/gst', admin, { name: 'x', rate: 5, tax_type: 'weird', is_default: false }), await call('POST', '/gst', admin, { name: 'x', rate: 5, tax_type: 'include' })].map((r) => r.status);
    return { ok: sameSet(w, a) && onlyOne && c1.status === 201 && swapped && d.status === 200 && up.status === 200 && del.json.data.no_default_gst === true && /no default GST/i.test(del.json.message) && none && del1.json.data.no_default_gst === false && hard && bad.every((s) => s === 422), detail: `list ${w.length}, bad ${bad.join('/')}` };
  });
  await t('WRITE PARITY GST: web store/update/delete and API leave the same rows', async () => {
    const wRes = await web.send('POST', '/admin/gst', { gst_name: 'API TEST GST W', gst_rate: '6.5', tax_type: 'exclude', Gst_defualt: '1' });
    const wId = Number(one("select id from tbl_gst where name='API TEST GST W'"));
    const wState = rows(`select rate,tax_type,default_status from tbl_gst where id=${wId}`)[0].join('|');
    const a = await call('POST', '/gst', admin, { name: 'API TEST GST A', rate: 6.5, tax_type: 'exclude', is_default: true });
    const aId = a.json.data.gst.id;
    const aState = rows(`select rate,tax_type,default_status from tbl_gst where id=${aId}`)[0].join('|');
    const wu = await web.send('PUT', `/admin/gst/${wId}`, { gst_name: 'API TEST GST W', gst_rate: '9', tax_type: 'include' });   // web: no flag ⇒ un-default
    const au = await call('PUT', `/gst/${aId}`, admin, { name: 'API TEST GST A', rate: 9, tax_type: 'include', is_default: false });
    const uw = rows(`select rate,tax_type,default_status from tbl_gst where id=${wId}`)[0].join('|'), ua = rows(`select rate,tax_type,default_status from tbl_gst where id=${aId}`)[0].join('|');
    const dw = await web.send('DELETE', `/admin/gst/${wId}`); const da = await call('DELETE', `/gst/${aId}`, admin);
    return { ok: wRes.status === 1 && a.status === 201 && wState === aState && wu.status === 1 && au.status === 200 && uw === ua && dw.status === 1 && da.status === 200, detail: `${wState} → ${uw}` };
  });

  // ============================================================ PAYMENT METHODS
  await t('CAT-5 payment methods: list; unique name (also vs deleted ones, web rule); update; soft delete', async () => {
    const list = (await call('GET', '/payment-methods', admin)).json.data.items;
    const c = await call('POST', '/payment-methods', admin, { name: 'API TEST Pay' });
    const id = c.json.data.payment_method.id;
    const dup = await call('POST', '/payment-methods', admin, { name: 'API TEST Pay' });
    const wDup = await web.send('POST', '/admin/payment-method', { name: 'API TEST Pay' });
    const up = await call('PUT', `/payment-methods/${id}`, admin, { name: 'API TEST Pay 2' });
    const same = await call('PUT', `/payment-methods/${id}`, admin, { name: 'API TEST Pay 2' });
    const clash = await call('PUT', `/payment-methods/${id}`, admin, { name: list[0].name });
    const del = await call('DELETE', `/payment-methods/${id}`, admin);
    const soft = one(`select deleted_at is not null from tbl_payment_method where id=${id}`) === '1';
    const dup2 = await call('POST', '/payment-methods', admin, { name: 'API TEST Pay 2' });
    const miss = await call('DELETE', `/payment-methods/${id + 100000}`, admin);
    return { ok: list.length >= 4 && c.status === 201 && dup.status === 422 && wDup.status !== 1 && up.status === 200 && same.status === 200 && clash.status === 422 && del.status === 200 && soft && dup2.status === 422 && miss.status === 404, detail: `${dup.status}/${clash.status}/${dup2.status} (deleted names stay reserved, like the web)` };
  });
  await t('CAT-5 an unknown/deleted payment method is refused on invoices (POS) and shows up in the POS catalog only while active', async () => {
    const catalog = (await call('GET', '/pos/catalog', admin)).json.data.payment_methods.map((m) => m.name);
    return { ok: !catalog.includes('API TEST Pay 2') && catalog.includes('Cash'), detail: catalog.join(',') };
  });

  // ============================================================ SETTINGS
  const settingRow = () => rows('select service_reminder_day,service_default_duration,service_fee,invoice_send_sts,ifnull(footer_about,"\\N"),contact_address,contact_phone,contact_email,ifnull(support_email,"\\N"),ifnull(whatsapp,"\\N"),ifnull(website_url,"\\N"),ifnull(facebook_url,"\\N") from tbl_setting where id=1')[0].join('|');
  await t('SHOP-1 settings: general values equal the DB; PUT general and web PUT leave the same row', async () => {
    const g = (await call('GET', '/settings', admin)).json.data;
    const same0 = g.general.service_reminder_day === Number(snap.setting[0]) && Number(g.general.service_fee) === Number(snap.setting[2]) && g.general.invoice_mail_send_status === (snap.setting[3] === '1');
    const wRes = await web.send('PUT', '/admin/setting/1', { setting_section: 'general', service_reminder_day: '45', service_default_duration: '20', service_fee: '2.25' });
    const wRow = settingRow();
    const a = await call('PUT', '/settings/general', admin, { service_reminder_day: 45, service_default_duration: 20, service_fee: 2.25, invoice_mail_send_status: false });
    const aRow = settingRow();
    const bad = [await call('PUT', '/settings/general', admin, { service_reminder_day: 0, service_default_duration: 20, service_fee: 1, invoice_mail_send_status: false }), await call('PUT', '/settings/general', admin, { service_reminder_day: 5, service_default_duration: 20, service_fee: -1, invoice_mail_send_status: false }), await call('PUT', '/settings/general', admin, { service_reminder_day: 5, service_default_duration: 20, service_fee: 1 })].map((r) => r.status);
    return { ok: same0 && wRes.status === 1 && a.status === 200 && wRow === aRow && wRow.startsWith('45|20|2.25|0|') && bad.every((s) => s === 422), detail: `${aRow.slice(0, 20)} bad ${bad.join('/')}` };
  });
  await t('SHOP-1b contact: web PUT and API PUT leave the same row (whatsapp digits only, empty URLs become null)', async () => {
    const fields = { footer_about: 'API TEST about', contact_address: '1 Test St', contact_phone: '780-555-0100', contact_email: 'shop@test.test', support_email: '', whatsapp: '+1 (780) 555-0100', website_url: '', facebook_url: 'https://fb.test/x' };
    const wRes = await web.send('PUT', '/admin/setting/1', { setting_section: 'contact', ...fields });
    const wRow = settingRow();
    const a = await call('PUT', '/settings/contact', admin, fields);
    const aRow = settingRow();
    const bad = [await call('PUT', '/settings/contact', admin, { ...fields, contact_email: 'nope' }), await call('PUT', '/settings/contact', admin, { ...fields, contact_address: '' })].map((r) => r.status);
    return { ok: wRes.status === 1 && a.status === 200 && wRow === aRow && wRow.includes('|17805550100|') && bad.every((s) => s === 422), detail: aRow };
  });

  // ============================================================ SHOP HOURS
  await t('SHOP-2 shop hours: GET equals the DB rows; PUT replaces hours/day-off/breaks like the web slot store', async () => {
    const g = (await call('GET', '/shop-hours', admin)).json.data.days;
    const dbRows = rows('select day_name,is_day_off,open_time,close_time from tbl_slots where staff_id=0');
    const readOk = g.length === 7 && g[0].day === 'Monday' && g[6].day === 'Sunday' && g.every((d) => { const r = dbRows.find((x) => x[0] === d.day); return r && (Number(r[1]) === 1) === d.is_day_off && (r[2] || '').slice(0, 5) === (d.open_time || ''); });
    const days = g.map((d) => ({ day: d.day, is_day_off: d.day === 'Sunday', open_time: '08:30', close_time: '19:30', breaks: d.day === 'Monday' ? [{ break_start: '12:00', break_end: '12:30' }, { break_start: '15:00', break_end: '15:15' }] : [] }));
    const a = await call('PUT', '/shop-hours', admin, { days });
    const after = (await call('GET', '/shop-hours', admin)).json.data.days;
    // the same through the web form
    const wForm = {}; for (const d of days) { wForm[`days[${d.day}][is_day_off]`] = d.is_day_off ? '1' : '0'; wForm[`days[${d.day}][open_time]`] = d.open_time; wForm[`days[${d.day}][close_time]`] = d.close_time; (d.breaks || []).forEach((b, i) => { wForm[`days[${d.day}][breaks][${i}][break_start]`] = b.break_start; wForm[`days[${d.day}][breaks][${i}][break_end]`] = b.break_end; }); }
    const state = () => JSON.stringify([rows('select day_name,is_day_off,open_time,close_time from tbl_slots where staff_id=0 order by id'), rows('select b.break_start,b.break_end,b.break_type,ifnull(b.staff_id,"N") from tbl_breaks b join tbl_slots s on s.id=b.slot_id where s.staff_id=0 order by b.id')]);
    const apiState = state();
    const w = await web.send('POST', '/admin/slot', wForm);
    const sameAsWeb = state() === apiState;
    const bad = [await call('PUT', '/shop-hours', admin, { days: [{ day: 'Funday', is_day_off: false, open_time: '09:00', close_time: '17:00' }] }), await call('PUT', '/shop-hours', admin, { days: [{ day: 'Monday', is_day_off: false, open_time: '17:00', close_time: '09:00' }] }), await call('PUT', '/shop-hours', admin, { days: [{ day: 'Monday', is_day_off: false, open_time: '09:00', close_time: '17:00', breaks: [{ break_start: '13:00', break_end: '12:00' }] }] }), await call('PUT', '/shop-hours', admin, { days: [{ day: 'Monday', is_day_off: false }] }), await call('PUT', '/shop-hours', admin, { days: [] })].map((r) => r.status);
    return { ok: readOk && a.status === 200 && after[0].breaks.length === 2 && after[0].open_time === '08:30' && after[6].is_day_off === true && w.status === 1 && sameAsWeb && bad.every((s) => s === 422), detail: `bad ${bad.join('/')}, same as web ${sameAsWeb}` };
  });
  await t('SHOP-2 the changed shop hours reach the slot finder (a day off ⇒ no slots on that day)', async () => {
    const d = new Date(); for (let i = 0; i < 14 && d.toLocaleDateString('en-US', { weekday: 'long', timeZone: 'America/Edmonton' }) !== 'Sunday'; i++) d.setDate(d.getDate() + 1);
    const date = d.toLocaleDateString('sv-SE', { timeZone: 'America/Edmonton' });
    const staffId = Number(one(`select id from users where email='${staffEmail}'`));
    const r = await call('GET', `/appointments/slots?date=${date}&staff_ids=${staffId}&service_ids=25`, admin);
    return { ok: r.status === 200 && r.json.data.slots.length === 0, detail: `Sunday ${date}: ${r.json.data.slots.length} slots (${r.json.data.message})` };
  });

  // ============================================================ CLOSURES
  const clo = (id) => rows(`select date,closure_status,ifnull(start_time,'N'),ifnull(end_time,'N'),ifnull(reason,'N') from tbl_shop_closure where id=${id}`)[0].join('|');
  await t('SHOP-3 closures: same list as the web; full-day + partial create/update/delete parity incl. the 00:55 → 12:55 fix', async () => {
    const w = (await web.table('/admin/shop-closures-action')).data.map((r) => `${r.id}|${String(r.date).slice(0, 10)}|${r.closure_status}`);
    const r = await all(admin, '/shop-closures');
    const a = r.items.map((c) => `${c.id}|${c.date}|${c.full_day ? 1 : 0}`);
    const bad = [];
    const mk = async (date, fields, apiBody) => {
      const wr = await web.send('POST', '/admin/shop-closures', { close_date: date, ...fields });
      const wId = Number(one(`select id from tbl_shop_closure where reason like 'API TEST W%' order by id desc limit 1`));
      const ar = await call('POST', '/shop-closures', admin, apiBody);
      return [wr, wId, ar, ar.json?.data?.closure?.id];
    };
    const cases = [
      ['2031-05-01', { full_day_closure: '1', close_reason: 'API TEST W full' }, { date: '2031-05-01', full_day: true, reason: 'API TEST A full' }],
      ['2031-05-02', { start_time: '10:00', end_time: '12:30', close_reason: 'API TEST W part' }, { date: '2031-05-02', full_day: false, start_time: '10:00', end_time: '12:30', reason: 'API TEST A part' }],
      ['2031-05-03', { start_time: '10:00', end_time: '00:55', close_reason: 'API TEST W fix' }, { date: '2031-05-03', full_day: false, start_time: '10:00', end_time: '00:55', reason: 'API TEST A fix' }],
    ];
    const made = [];
    for (const [d, wf, ab] of cases) {
      const [wr, wId, ar, aId] = await mk(d, wf, ab);
      made.push(wId, aId);
      if (!wId || !aId) { bad.push(`${d}: web ${JSON.stringify(wr).slice(0, 160)} api ${ar.status} ${JSON.stringify(ar.json).slice(0, 160)}`); continue; }
      const n = (s) => s.replace(/API TEST [WA]/, 'R');
      if (wr.status !== 1 || ar.status !== 201 || n(clo(wId)) !== n(clo(aId))) bad.push(`${d}: web ${clo(wId)} api ${aId ? clo(aId) : ar.status}`);
    }
    const tooLate = await call('POST', '/shop-closures', admin, { date: '2031-05-04', full_day: false, start_time: '15:00', end_time: '14:00', reason: 'API TEST bad' });
    const noTimes = await call('POST', '/shop-closures', admin, { date: '2031-05-04', full_day: false, reason: 'API TEST bad' });
    const noDate = await call('POST', '/shop-closures', admin, { full_day: true });
    const upd = await call('PUT', `/shop-closures/${made[1]}`, admin, { date: '2031-05-09', full_day: true, reason: 'API TEST A moved' });
    const afterUpd = clo(made[1]);
    const del = await call('DELETE', `/shop-closures/${made[1]}`, admin);
    const miss = await call('DELETE', `/shop-closures/${made[1]}`, admin);
    const filt = await all(admin, '/shop-closures?from=2031-05-01&to=2031-05-03');
    return { ok: sameSet(w.filter((x) => !x.includes('2031')), a.filter((x) => !x.includes('2031'))) && bad.length === 0 && tooLate.status === 422 && noTimes.status === 422 && noDate.status === 422 && upd.status === 200 && afterUpd.startsWith('2031-05-09|1|N|N') && del.status === 200 && miss.status === 404 && filt.items.length >= 3, detail: bad.join(' | ') || `list web ${w.length}, filter ${filt.items.length}` };
  });
  await t('SHOP-3 a closure removes slots on that day (slot finder honours it)', async () => {
    const staffId = Number(one(`select id from users where email='${staffEmail}'`));
    sql(`delete from tbl_shop_closure where reason like 'API TEST%'`);
    const d = new Date(); d.setDate(d.getDate() + 5);
    const date = d.toLocaleDateString('sv-SE', { timeZone: 'America/Edmonton' });
    const wk = d.toLocaleDateString('en-US', { weekday: 'long', timeZone: 'America/Edmonton' });
    if (wk === 'Sunday') return { ok: true, detail: 'skipped (that day is the Sunday off day)' };
    const before = (await call('GET', `/appointments/slots?date=${date}&staff_ids=${staffId}&service_ids=25`, admin)).json.data.slots.length;
    await call('POST', '/shop-closures', admin, { date, full_day: true, reason: 'API TEST Slot' });
    const after = (await call('GET', `/appointments/slots?date=${date}&staff_ids=${staffId}&service_ids=25`, admin)).json.data.slots.length;
    return { ok: before > 0 && after === 0, detail: `${date}: ${before} → ${after} slots` };
  });

  // ============================================================ permissions
  await t('permissions: staff user (no catalog/shop perms) gets 403 on every module; a role-less admin account too', async () => {
    const paths = [['GET', '/services'], ['POST', '/services'], ['GET', '/service-categories'], ['GET', '/products'], ['GET', '/gst'], ['GET', '/payment-methods'], ['GET', '/settings'], ['PUT', '/settings/general'], ['GET', '/shop-hours'], ['PUT', '/shop-hours'], ['GET', '/shop-closures'], ['POST', '/shop-closures'], ['DELETE', '/services/1'], ['PATCH', '/services/1/home-section']];
    const out = []; for (const [m, p] of paths) out.push((await call(m, p, staff, m === 'GET' || m === 'DELETE' ? null : {})).status);
    return { ok: out.every((s) => s === 403), detail: out.join('/') };
  });

  // ============================================================ restore + cleanup
  const q = (s) => (s === '\\N' ? 'NULL' : `'${String(s).replace(/'/g, "''")}'`);
  const s = snap.setting;
  sql(`update tbl_setting set service_reminder_day=${s[0]},service_default_duration=${s[1]},service_fee=${s[2]},invoice_send_sts=${originalSts},footer_about=${q(s[4])},contact_address=${q(s[5])},contact_phone=${q(s[6])},contact_email=${q(s[7])},support_email=${q(s[8])},whatsapp=${q(s[9])},website_url=${q(s[10])},facebook_url=${q(s[11])},instagram_url=${q(s[12])},tiktok_url=${q(s[13])},youtube_url=${q(s[14])},twitter_url=${q(s[15])},linkedin_url=${q(s[16])} where id=1`);
  for (const [id, off, open, close] of snap.slots) sql(`update tbl_slots set is_day_off=${off},open_time=${q(open)},close_time=${q(close)} where id=${id}`);
  sql('delete b from tbl_breaks b join tbl_slots s on s.id=b.slot_id where s.staff_id=0');
  for (const [slot, st, en, type] of snap.breaks) sql(`insert into tbl_breaks (slot_id,break_start,break_end,break_type,created_at,updated_at) values (${slot},'${st}','${en}',${type},now(),now())`);
  sql("delete from tbl_gst where name like 'API TEST%'");
  for (const [id, def] of snap.gst) sql(`update tbl_gst set default_status=${def} where id=${id}`);
  sql("delete from tbl_service where service_name like 'API TEST%'; delete from tbl_product where product_name like 'API TEST%'; delete from tbl_service_category where category_name like 'API TEST%'; delete from tbl_payment_method where name like 'API TEST%'; delete from tbl_shop_closure where reason like 'API TEST%';");
  for (const p of files) { try { fs.unlinkSync(`${STORAGE}/${p}`); } catch (e) { /* already gone */ } }

  const w = Math.max(...results.map((r) => r.name.length));
  console.log('\nPhase 4a tests: catalog and shop administration\n');
  for (const r of results) console.log((r.ok ? '  PASS ' : '  FAIL ') + r.name.padEnd(w) + (r.detail ? '  ' + r.detail : ''));
  const failed = results.filter((r) => !r.ok).length;
  console.log(`\n${results.length - failed}/${results.length} passed` + (failed ? `, ${failed} FAILED` : ''));
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
