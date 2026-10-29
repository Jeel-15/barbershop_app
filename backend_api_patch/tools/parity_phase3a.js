#!/usr/bin/env node
/**
 * Parity test, Phase 3a (read side): customers, customer profile, dashboard top lists
 * and the staff earnings report, API versus the web's own endpoints.
 *
 *   node parity_phase3a.js <webBase> <apiBase> <adminEmail> <adminPw> <staffEmail> <staffPw>
 *
 * Needs the marked test data (APITEST-8/9 are invoiced appointments with commission,
 * tips and a product for the test barber). Needs Node 20+.
 */
const [webBase, apiBase, adminEmail, adminPw, staffEmail, staffPw] = process.argv.slice(2);
if (!staffPw) { console.error('usage: node parity_phase3a.js <webBase> <apiBase> <adminEmail> <adminPw> <staffEmail> <staffPw>'); process.exit(2); }

const results = [];
const rec = (name, ok, detail = '') => results.push({ name, ok, detail });

class Web {
  constructor() { this.jar = {}; this.csrf = null; }
  cookieHeader() { return Object.entries(this.jar).map(([k, v]) => `${k}=${v}`).join('; '); }
  store(res) { for (const c of res.headers.getSetCookie?.() || []) { const [pair] = c.split(';'); const i = pair.indexOf('='); this.jar[pair.slice(0, i)] = pair.slice(i + 1); } }
  async req(method, path, { form, ajax } = {}) {
    const headers = { Cookie: this.cookieHeader() };
    let body;
    if (form) { headers['Content-Type'] = 'application/x-www-form-urlencoded'; body = form instanceof URLSearchParams ? form.toString() : new URLSearchParams(form).toString(); }
    if (ajax) { headers['X-Requested-With'] = 'XMLHttpRequest'; headers['X-CSRF-TOKEN'] = this.csrf; headers.Accept = 'application/json'; }
    const res = await fetch(webBase + path, { method, headers, body, redirect: 'manual' });
    this.store(res);
    return res;
  }
  async login(email, pw) {
    const page = await (await this.req('GET', '/admin/login')).text();
    const token = (page.match(/name="_token" value="([^"]+)"/) || [])[1];
    const res = await this.req('POST', '/admin/post-login', { form: { _token: token, email, password: pw } });
    if (res.status !== 302) throw new Error('web login failed for ' + email);
    const dash = await (await this.req('GET', '/admin/dashboard')).text();
    this.csrf = (dash.match(/name="csrf-token" content="([^"]+)"/) || [])[1];
    this.dashboardHtml = dash;
  }
  async table(path, params = {}) {
    const form = new URLSearchParams({ draw: '1', start: '0', length: '-1', ...params });
    const res = await this.req('POST', path, { form, ajax: true });
    return res.json();
  }
}
async function api(token, path) {
  const res = await fetch(apiBase + path, { headers: { Accept: 'application/json', Authorization: 'Bearer ' + token } });
  return { status: res.status, json: await res.json() };
}
async function apiAll(token, path) {
  const items = []; let page = 1;
  for (;;) {
    const r = await api(token, path + (path.includes('?') ? '&' : '?') + `per_page=50&page=${page}`);
    if (r.status !== 200) return { status: r.status, items, json: r.json };
    items.push(...r.json.data.items);
    if (!r.json.meta.has_more) return { status: 200, items, meta: r.json.meta };
    page++;
  }
}
async function apiLogin(email, pw) {
  const res = await fetch(apiBase + '/auth/login', { method: 'POST', headers: { Accept: 'application/json', 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: pw, device_name: 'parity3a' }) });
  const j = await res.json(); if (!j.data?.token) throw new Error('api login failed ' + email); return j.data.token;
}
const unesc = (s) => String(s ?? '').replace(/<[^>]*>/g, '').replace(/&#0?39;/g, "'").replace(/&amp;/g, '&').trim();
const num = (s) => Number(String(s ?? '').replace(/[^0-9.\-]/g, '') || 0).toFixed(2);
const sameSet = (a, b) => a.length === b.length && [...a].sort().join('|') === [...b].sort().join('|');
async function t(name, fn) { try { const r = await fn(); rec(name, r.ok, r.detail || ''); } catch (e) { rec(name, false, 'EXCEPTION ' + e.message); } }

async function run() {
  const adminWeb = new Web(); await adminWeb.login(adminEmail, adminPw);
  const staffWeb = new Web(); await staffWeb.login(staffEmail, staffPw);
  const admin = await apiLogin(adminEmail, adminPw), staff = await apiLogin(staffEmail, staffPw);

  // ------------------------------------------------------------------ customers list
  const wCust = await adminWeb.table('/admin/customers-action');
  await t('CUST-1 customers: same people, same fields as the web list', async () => {
    const r = await apiAll(admin, '/customers');
    const w = wCust.data.map((c) => `${c.customer_id}|${unesc(c.customer_name)}|${c.customer_phone}|${c.customer_email ?? ''}|${c.customer_status ?? ''}`);
    const a = r.items.map((c) => `${c.id}|${unesc(c.name)}|${c.phone}|${c.email ?? ''}|${c.status ?? ''}`);
    return { ok: r.status === 200 && sameSet(w, a) && w.length > 0, detail: `web ${w.length}, api ${a.length}` };
  });
  await t('CUST-1 customers: search finds the same customers as the web search box', async () => {
    const term = unesc(wCust.data[0].customer_name).split(' ')[0].slice(0, 3);
    const w = (await adminWeb.table('/admin/customers-action', { 'search[value]': term })).data.map((c) => c.customer_id);
    const r = await apiAll(admin, '/customers?q=' + encodeURIComponent(term));
    const a = r.items.map((c) => c.id);
    // the web box also matches id and status text; every API hit must be a web hit
    return { ok: a.length > 0 && a.every((id) => w.includes(id)), detail: `term "${term}": web ${w.length}, api ${a.length}` };
  });
  await t('CUST-1 customers: status filter, pagination meta, staff (no Customer perm) → 403', async () => {
    const act = await apiAll(admin, '/customers?status=1'), ina = await apiAll(admin, '/customers?status=0');
    const p1 = await api(admin, '/customers?per_page=5&page=1'), p2 = await api(admin, '/customers?per_page=5&page=2');
    const forb = await api(staff, '/customers');
    const all = wCust.data.length;
    return { ok: act.items.every((c) => c.status === 1) && ina.items.every((c) => c.status !== 1) && act.items.length + ina.items.length === all && p1.json.data.items.length === 5 && p1.json.meta.has_more === true && p2.json.data.items[0].id !== p1.json.data.items[0].id && forb.status === 403, detail: `active ${act.items.length} + other ${ina.items.length} = ${all}; staff ${forb.status}` };
  });

  // ------------------------------------------------------------------ profile
  const ids = wCust.data.map((c) => c.customer_id);
  await t('CUST-2 profile: visits + total spend equal the web profile page for every customer', async () => {
    const bad = [];
    for (const id of ids) {
      const html = await (await adminWeb.req('GET', '/admin/customer-profile/' + id)).text();
      const vals = [...html.matchAll(/<strong class="fs-4">([^<]*)<\/strong>/g)].map((m) => m[1].trim());
      const r = await api(admin, '/customers/' + id);
      const p = r.json.data.customer;
      if (String(p.total_visits) !== vals[0] || num(vals[1]) !== p.total_spend) bad.push(`${id}: web ${vals[0]}/${vals[1]} api ${p.total_visits}/${p.total_spend}`);
    }
    return { ok: bad.length === 0, detail: bad.length ? bad.join('; ') : `${ids.length} customers` };
  });
  await t('CUST-2 profile: unknown id → 404', async () => ({ ok: (await api(admin, '/customers/99999999')).status === 404 }));

  // ------------------------------------------------------------------ customer appointments
  const withAppts = (await Promise.all(ids.map(async (id) => [id, (await api(admin, `/customers/${id}`)).json.data.customer.appointments_total]))).filter(([, n]) => n > 0).map(([id]) => id);
  await t('CUST-3 customer appointments: same appointments, staff names and times as the web table (all customers with bookings)', async () => {
    const bad = [];
    for (const id of withAppts) {
      const w = await adminWeb.table('/admin/customer-pending-appointment-action', { customer_id: String(id) });
      const r = await apiAll(admin, `/customers/${id}/appointments`);
      const wl = w.data.map((x) => `${x.appointment_id}|${x.date}|${String(x.slot_start).slice(0, 5)}|${String(x.slot_end).slice(0, 5)}|${x.status}|${x.staff_names ?? ''}|${x.staff_ids ?? ''}|${x.service_ids ?? ''}`);
      const al = r.items.map((x) => `${x.id}|${x.date}|${x.start}|${x.end}|${x.status}|${x.staff_names}|${x.staff_ids.join(',')}|${x.service_ids.join(',')}`);
      const norm = (list) => list.map((l) => l.split('|').map((v, i) => (i === 6 || i === 7 ? v.split(',').filter(Boolean).sort().join(',') : v)).join('|'));
      if (!sameSet(norm(wl), norm(al))) bad.push(`customer ${id}: web ${wl.length} api ${al.length}`);
    }
    return { ok: bad.length === 0 && withAppts.length > 0, detail: bad.length ? bad.join('; ') : `${withAppts.length} customers with bookings` };
  });
  await t('CUST-3 filters (date range, barber, time of day) match the web; the web\'s broken status filter works in the API', async () => {
    const id = withAppts.sort((x, y) => x - y)[0];
    const bad = [];
    const cases = [
      [{ start_date: '2000-01-01', end_date: '2100-01-01' }, '?start_date=2000-01-01&end_date=2100-01-01'],
      [{ staff_id: '51' }, '?staff_id=51'], [{ staff_id: '49' }, '?staff_id=49'],
      [{ day_type: 'Morning' }, '?day_type=Morning'], [{ day_type: 'Afternoon' }, '?day_type=Afternoon'],
    ];
    for (const [wp, ap] of cases) {
      const cust = [...withAppts, 11].includes(11) ? 11 : id;
      const w = await adminWeb.table('/admin/customer-pending-appointment-action', { customer_id: String(cust), ...wp });
      const r = await apiAll(admin, `/customers/${cust}/appointments${ap}`);
      if (!sameSet(w.data.map((x) => String(x.appointment_id)), r.items.map((x) => String(x.id)))) bad.push(`${JSON.stringify(wp)}: web ${w.data.length} api ${r.items.length}`);
    }
    const st = await apiAll(admin, `/customers/11/appointments?status=2`);
    const all = await apiAll(admin, `/customers/11/appointments`);
    if (!st.items.every((x) => x.status === 2) || st.items.length >= all.items.length) bad.push('status filter not applied');
    return { ok: bad.length === 0, detail: bad.length ? bad.join('; ') : `status=2 → ${st.items.length} of ${all.items.length}` };
  });

  // ------------------------------------------------------------------ dashboard lists
  await t('DASH-4 top services: same services, revenue and counts as the web table', async () => {
    const w = (await adminWeb.table('/admin/top-services')).data.map((r) => `${unesc(r.service_name)}|${num(r.totalRevenue)}|${r.appointmentCount}`);
    const r = await apiAll(admin, '/dashboard/top-services');
    const a = r.items.map((x) => `${unesc(x.service_name)}|${x.total_revenue}|${x.appointment_count}`);
    return { ok: r.status === 200 && sameSet(w, a) && w.length > 0, detail: `${w.length} services` };
  });
  await t('DASH-5 staff performance: same barbers and figures as the web', async () => {
    const w = (await adminWeb.table('/admin/staff-performance')).data.map((r) => `${r.staff_id}|${unesc(r.staff_name)}|${num(r.totalRevenue)}|${num(r.totalCommission)}|${r.appointmentCount}`);
    const r = await apiAll(admin, '/dashboard/staff-performance');
    const a = r.items.map((x) => `${x.staff_id}|${unesc(x.staff_name)}|${x.total_revenue}|${x.total_commission}|${x.appointment_count}`);
    return { ok: r.status === 200 && sameSet(w, a) && w.length > 0, detail: `${w.length} barbers` };
  });
  await t('DASH-6 top products: same products and sold counts as the dashboard table', async () => {
    const html = adminWeb.dashboardHtml;
    const seg = html.slice(html.indexOf('id="TopStaffDataTable"'));
    const body = seg.slice(seg.indexOf('<tbody'), seg.indexOf('</tbody>'));
    const w = [...body.matchAll(/<td>([^<]*)<\/td>\s*<td>(\d+)<\/td>/g)].map((m) => `${unesc(m[1])}|${m[2]}`);
    const r = await apiAll(admin, '/dashboard/top-products');
    const a = r.items.map((x) => `${unesc(x.product_name)}|${x.total_sold}`);
    return { ok: r.status === 200 && sameSet(w, a), detail: `web ${w.length}, api ${a.length}` };
  });
  await t('DASH-4/5/6 permissions: a role-less user gets 403; search narrows the list', async () => {
    const s = await apiAll(admin, '/dashboard/top-services?q=cut');
    const none = (await api(staff, '/dashboard/top-services')).status;     // staff role has no Top_Services
    const none2 = (await api(staff, '/dashboard/top-products')).status;
    return { ok: s.items.every((x) => /cut/i.test(x.service_name)) && none === 403 && none2 === 403, detail: `staff top-services ${none}, top-products ${none2}, search "cut" → ${s.items.length}` };
  });

  // ------------------------------------------------------------------ staff report
  const sid = (await api(staff, '/auth/me')).json.data.user.id;
  await t('ME-3 summary: equals the web summary cards (no filter, status filter, date range)', async () => {
    const bad = [];
    for (const [wp, ap] of [[{}, ''], [{ status: '1' }, '?status=1'], [{ start_date: '2000-01-01', end_date: '2100-01-01' }, '?start_date=2000-01-01&end_date=2100-01-01']]) {
      const w = (await staffWeb.table('/admin/staff-report-appointment', { staff_id: String(sid), ...wp })).summary;
      const s = (await api(staff, '/me/report/summary' + ap)).json.data.summary;
      const pairs = [['total_revenue', 'total_revenue'], ['total_appointments', 'total_appointments'], ['total_visits', 'total_visits'], ['total_tips', 'total_tips'], ['staff_total_service_tip', 'my_tips'], ['staff_total_service_commission', 'my_service_commission'], ['staff_total_product_commission', 'my_product_commission'], ['staff_total_earning', 'my_total_earning']];
      for (const [wk, ak] of pairs) if (num(w[wk]) !== num(s[ak])) bad.push(`${JSON.stringify(wp)} ${wk}: web ${w[wk]} api ${s[ak]}`);
    }
    return { ok: bad.length === 0, detail: bad.join('; ') };
  });
  await t('ME-3 summary: service fee equals the web note', async () => {
    const html = await (await staffWeb.req('GET', '/admin/staff-report')).text();
    const fee = (html.match(/\(\$([0-9.,]+)\) from each service amount/) || [])[1];
    const s = (await api(staff, '/me/report/summary')).json.data.summary;
    return { ok: num(fee) === s.service_fee, detail: `web ${fee} api ${s.service_fee}` };
  });
  await t('ME-4 daily earnings: same days and amounts as the web table', async () => {
    const w = (await staffWeb.table('/admin/staff-report-earning', { id: String(sid) })).data
      .map((r) => `${r.appointment_date.split('-').reverse().join('-')}|${num(r.service_commission)}|${num(r.service_tip_earn)}|${num(r.product_commision_earn)}|${num(r.total_earning)}`);
    const r = await apiAll(staff, '/me/report/earnings');
    const a = r.items.map((x) => `${x.date}|${x.service_commission}|${x.tips}|${x.product_commission}|${x.total_earning}`);
    return { ok: r.status === 200 && sameSet(w, a) && w.length >= 2, detail: `${w.length} days: ${a.join(' ; ')}` };
  });
  await t('ME-5 services: same services and amounts as the web table', async () => {
    const w = (await staffWeb.table('/admin/staff-report-assign-service', { id: String(sid) })).data
      .map((r) => `${unesc(r.service_name)}|${r.appointmentCount}|${num(r.total_service_commission)}|${num(r.total_service_tip)}|${num(r.totalRevenue)}`);
    const r = await apiAll(staff, '/me/report/services');
    const a = r.items.map((x) => `${unesc(x.service_name)}|${x.appointment_count}|${x.commission}|${x.tips}|${x.total_earning}`);
    return { ok: r.status === 200 && sameSet(w, a) && w.length >= 1, detail: `${w.length} services: ${a.join(' ; ')}` };
  });
  await t('ME-6 appointments: same appointments and money as the web table (no filter, status, dates)', async () => {
    const bad = [];
    for (const [wp, ap] of [[{}, ''], [{ status: '1' }, '?status=1'], [{ start_date: '2026-10-20', end_date: '2026-10-22' }, '?start_date=2026-10-20&end_date=2026-10-22']]) {
      const w = (await staffWeb.table('/admin/staff-report-appointment', { staff_id: String(sid), ...wp })).data
        .map((r) => `${r.appointment_id}|${r.customer_name ?? ''}|${num(r.service_discount)}|${num(r.service_tip)}|${num(r.service_total_amt)}`);
      const r = await apiAll(staff, '/me/report/appointments' + ap);
      const a = r.items.map((x) => `${x.id}|${x.customer.name ?? ''}|${x.discount}|${x.tip}|${x.total}`);
      if (!sameSet(w, a)) bad.push(`${JSON.stringify(wp)}: web ${w.length} api ${a.length}`);
    }
    return { ok: bad.length === 0, detail: bad.join('; ') };
  });
  await t('ME-3..6 only for staff users: admin → 403; filters are validated (bad date → 422)', async () => {
    const a = (await api(admin, '/me/report/summary')).status;
    const bad = (await api(staff, '/me/report/summary?start_date=yesterday')).status;
    return { ok: a === 403 && bad === 422, detail: `admin ${a}, bad date ${bad}` };
  });

  const w = Math.max(...results.map((r) => r.name.length));
  console.log('\nPhase 3a parity (API vs web)\n');
  for (const r of results) console.log((r.ok ? '  PASS ' : '  FAIL ') + r.name.padEnd(w) + (r.detail ? '  ' + r.detail : ''));
  const failed = results.filter((r) => !r.ok).length;
  console.log(`\n${results.length - failed}/${results.length} passed` + (failed ? `, ${failed} FAILED` : ''));
  process.exit(failed ? 1 : 0);
}
run().catch((e) => { console.error(e); process.exit(1); });
