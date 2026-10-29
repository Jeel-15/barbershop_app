#!/usr/bin/env node
/**
 * Parity test, Phase 1: does the API return the same data as the web admin?
 *
 *   node parity_phase1.js <webBase> <apiBase> <adminEmail> <adminPw> <staffEmail> <staffPw>
 *   e.g. node parity_phase1.js http://localhost/rosen_barber/public http://localhost/rosen_barber/public/api/v1 a@x.com pw s@x.com pw
 *
 * It signs in to the web (session + CSRF) and to the API (token) as the same user,
 * calls the web's DataTables endpoints and the matching API endpoints with the same
 * filters, and compares record counts, ids, order, status, staff and service lines,
 * the dashboard cards and the per-status counts. Needs Node 20+.
 */
const [webBase, apiBase, adminEmail, adminPw, staffEmail, staffPw] = process.argv.slice(2);
if (!staffPw) { console.error('usage: node parity_phase1.js <webBase> <apiBase> <adminEmail> <adminPw> <staffEmail> <staffPw>'); process.exit(2); }

const results = [];
const rec = (name, ok, detail = '') => results.push({ name, ok, detail });

class Web {
  constructor() { this.jar = {}; this.csrf = null; }
  cookieHeader() { return Object.entries(this.jar).map(([k, v]) => `${k}=${v}`).join('; '); }
  store(res) {
    for (const c of res.headers.getSetCookie?.() || []) {
      const [pair] = c.split(';'); const i = pair.indexOf('=');
      this.jar[pair.slice(0, i)] = pair.slice(i + 1);
    }
  }
  async req(method, path, { form, ajax } = {}) {
    const headers = { Cookie: this.cookieHeader() };
    let body;
    if (form) { headers['Content-Type'] = 'application/x-www-form-urlencoded'; body = new URLSearchParams(form).toString(); }
    if (ajax) { headers['X-Requested-With'] = 'XMLHttpRequest'; headers['X-CSRF-TOKEN'] = this.csrf; headers.Accept = 'application/json'; }
    const res = await fetch(webBase + path, { method, headers, body, redirect: 'manual' });
    this.store(res);
    return res;
  }
  async login(email, pw) {
    const page = await (await this.req('GET', '/admin/login')).text();
    const token = (page.match(/name="_token" value="([^"]+)"/) || [])[1];
    const res = await this.req('POST', '/admin/post-login', { form: { _token: token, email, password: pw } });
    if (res.status !== 302) throw new Error('web login failed for ' + email + ' (http ' + res.status + ')');
    const dash = await (await this.req('GET', '/admin/dashboard')).text();
    this.csrf = (dash.match(/name="csrf-token" content="([^"]+)"/) || [])[1];
    this.dashboardHtml = dash;
  }
  async table(path, filters = {}, q = '') {
    const form = { draw: 1, start: 0, length: 1000, 'search[value]': q, ...filters };
    const res = await this.req('POST', path, { form, ajax: true });
    return res.json();
  }
  async page(path) { return (await this.req('GET', path)).text(); }
}

async function api(token, path) {
  const res = await fetch(apiBase + path, { headers: { Accept: 'application/json', Authorization: 'Bearer ' + token } });
  return { status: res.status, json: await res.json() };
}
async function apiAll(token, path) {
  const items = []; let page = 1, total = 0;
  for (;;) {
    const sep = path.includes('?') ? '&' : '?';
    const r = await api(token, `${path}${sep}per_page=50&page=${page}`);
    if (r.status !== 200) throw new Error(`API ${path} -> ${r.status} ${JSON.stringify(r.json).slice(0, 150)}`);
    items.push(...r.json.data.items); total = r.json.meta.total;
    if (!r.json.meta.has_more) break; page++;
  }
  return { items, total };
}
async function apiLogin(email, pw) {
  const res = await fetch(apiBase + '/auth/login', { method: 'POST', headers: { Accept: 'application/json', 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: pw, device_name: 'parity' }) });
  const j = await res.json();
  if (!j.data?.token) throw new Error('api login failed for ' + email + ': ' + JSON.stringify(j));
  return j.data.token;
}

const unesc = (s) => String(s).replace(/&#0?39;/g, "'").replace(/&amp;/g, '&').replace(/&quot;/g, '"').replace(/&lt;/g, '<').replace(/&gt;/g, '>');
const sameSet = (a, b) => a.length === b.length && [...a].sort().join('|') === [...b].sort().join('|');
const money = (s) => Number(String(s).replace(/[$,\s]/g, '')).toFixed(2);

function compareRows(web, apiItems, { ordered }) {
  const problems = [];
  const wIds = web.data.map((r) => String(r.appointment_id));
  const aIds = apiItems.map((r) => String(r.id));
  if (ordered ? wIds.join(',') !== aIds.join(',') : !sameSet(wIds, aIds)) problems.push(`ids differ web=[${wIds}] api=[${aIds}]`);
  const aById = new Map(apiItems.map((r) => [String(r.id), r]));
  for (const w of web.data) {
    const a = aById.get(String(w.appointment_id));
    if (!a) continue;
    if (Number(w.status) !== a.status) problems.push(`#${a.id} status ${w.status} vs ${a.status}`);
    const wSlot = String(w.slot_time || '').trim();
    if (wSlot && wSlot !== a.slot_label) problems.push(`#${a.id} slot "${wSlot}" vs "${a.slot_label}"`);
    const wNames = String(w.staff_names || '').split(',').map((s) => s.trim()).filter(Boolean);
    if (!sameSet(wNames, a.staff_names)) problems.push(`#${a.id} staff_names [${wNames}] vs [${a.staff_names}]`);
    const wLines = unesc(w.staff_service_lines || '').split(' | ').map((s) => s.trim()).filter(Boolean);
    if (!sameSet(wLines, a.lines)) problems.push(`#${a.id} lines [${wLines}] vs [${a.lines}]`);
    if (w.customer_name && w.customer_name !== a.customer.name) problems.push(`#${a.id} customer "${w.customer_name}" vs "${a.customer.name}"`);
    const wSvc = String(w.service_ids || '').split(',').filter(Boolean);
    if (!sameSet(wSvc, a.service_ids.map(String))) problems.push(`#${a.id} service_ids [${wSvc}] vs [${a.service_ids}]`);
    const wStaff = String(w.staff_ids || '').split(',').filter(Boolean);
    if (!sameSet(wStaff, a.staff_ids.map(String))) problems.push(`#${a.id} staff_ids [${wStaff}] vs [${a.staff_ids}]`);
  }
  return problems;
}

function cards(html) {
  const out = {};
  const re = /<div class="bc-stat-label">\s*([^<]+?)\s*<\/div>\s*<p class="bc-stat-value">\s*([^<]*?)\s*<\/p>/g;
  let m; while ((m = re.exec(html))) out[m[1]] = m[2];
  return out;
}

async function runRole(label, email, pw, isStaff) {
  const web = new Web(); await web.login(email, pw);
  const tok = await apiLogin(email, pw);

  // ---- Appointments list (APPT-1) vs admin/appointment-action
  const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'America/Edmonton' });
  const scenarios = [
    ['no filter', {}, '', ''],
    ['status=0', { status: 0 }, '', '&status=0'],
    ['status=3', { status: 3 }, '', '&status=3'],
    ['status=2', { status: 2 }, '', '&status=2'],
    ['status=4', { status: 4 }, '', '&status=4'],
    ['staff_id=49', { staff_id: 49 }, '', '&staff_id=49'],
    ['staff_id=51', { staff_id: 51 }, '', '&staff_id=51'],
    ['date range', { start_date: today, end_date: '2099-01-01' }, '', `&start_date=${today}&end_date=2099-01-01`],
    ['only start_date (web ignores it)', { start_date: today }, '', `&start_date=${today}`],
    ['day_type=Morning', { day_type: 'Morning' }, '', '&day_type=Morning'],
    ['day_type=Afternoon', { day_type: 'Afternoon' }, '', '&day_type=Afternoon'],
    ['day_type=Evening', { day_type: 'Evening' }, '', '&day_type=Evening'],
    ['search "API TEST"', {}, 'API TEST', '&q=' + encodeURIComponent('API TEST')],
    ['search staff name "Mutaz"', {}, 'Mutaz', '&q=Mutaz'],
    ['search id "3"', {}, '3', '&q=3'],
  ];
  for (const [name, wf, wq, aq] of scenarios) {
    try {
      const w = await web.table('/admin/appointment-action', wf, wq);
      const a = await apiAll(tok, '/appointments?' + aq.replace(/^&/, ''));
      const problems = compareRows(w, a.items, { ordered: true });
      if (Number(w.recordsFiltered) !== a.total) problems.unshift(`total web=${w.recordsFiltered} api=${a.total}`);
      rec(`[${label}] appointments list: ${name} (${a.total} rows)`, problems.length === 0, problems.slice(0, 3).join(' | '));
    } catch (e) { rec(`[${label}] appointments list: ${name}`, false, e.message); }
  }

  // ---- Dashboard today / upcoming (DASH-2/3)
  for (const [name, webPath, apiPath] of [['today', '/admin/get-today-appointment', '/dashboard/today'], ['upcoming', '/admin/get-upcoming-appointment', '/dashboard/upcoming']]) {
    for (const q of ['', 'API TEST', 'Mike']) {
      try {
        const w = await web.table(webPath, {}, q);
        const a = await apiAll(tok, `${apiPath}?q=${encodeURIComponent(q)}`);
        const problems = compareRows(w, a.items, { ordered: false });
        if (Number(w.recordsFiltered) !== a.total) problems.unshift(`total web=${w.recordsFiltered} api=${a.total}`);
        rec(`[${label}] dashboard ${name}${q ? ' q="' + q + '"' : ''} (${a.total} rows)`, problems.length === 0, problems.slice(0, 3).join(' | '));
      } catch (e) { rec(`[${label}] dashboard ${name}`, false, e.message); }
    }
  }

  // ---- Per-status counts (APPT-2) vs Appointments page
  try {
    const html = await web.page('/admin/appointment');
    const c = cards(html);
    const r = await api(tok, '/appointments/counts');
    const k = r.json.data.counts;
    const pairs = [['All', k.all], ['Confirm', k.confirmed], ['Complete', k.completed], ['Cancel', k.cancelled], ['Reschedule', k.rescheduled]];
    const bad = pairs.filter(([l, v]) => Number(c[l]) !== v).map(([l, v]) => `${l} web=${c[l]} api=${v}`);
    rec(`[${label}] appointment counts (${pairs.map(([l, v]) => l + ':' + v).join(' ')})`, bad.length === 0, bad.join(' | '));
  } catch (e) { rec(`[${label}] appointment counts`, false, e.message); }

  // ---- Dashboard cards (DASH-1)
  try {
    const c = cards(web.dashboardHtml);
    const r = await api(tok, '/dashboard/summary');
    const d = r.json.data;
    const pairs = [
      ['Upcoming Appointments', d.appointments.upcoming], ['Customers', d.customers],
      ['Completed', d.appointments.completed], ['Cancelled', d.appointments.cancelled],
      ['Confirmed', d.appointments.confirmed], ['Scheduled', d.appointments.rescheduled],
    ];
    const bad = pairs.filter(([l, v]) => c[l] !== undefined && Number(c[l]) !== v).map(([l, v]) => `${l} web=${c[l]} api=${v}`);
    rec(`[${label}] dashboard card labels the web shows: ${Object.keys(c).join(', ')}`, true);
    const m = (l, v) => { if (c[l] !== undefined && money(c[l]) !== money(v)) bad.push(`${l} web=${c[l]} api=${v}`); };
    m('Total Revenue', d.money.revenue); m('Tips Received', d.money.tips);
    if (d.money.commission !== undefined) m('Commission', d.money.commission);
    rec(`[${label}] dashboard cards (${d.scope}: revenue ${d.money.revenue}, tips ${d.money.tips}${d.money.commission ? ', commission ' + d.money.commission : ''})`, bad.length === 0, bad.join(' | '));
  } catch (e) { rec(`[${label}] dashboard cards`, false, e.message); }

  // ---- Detail (APPT-3) vs admin/appointment.get-appointment-details
  try {
    const list = await apiAll(tok, '/appointments');
    const problems = [];
    for (const row of list.items.slice(0, 40)) {
      const w = await (await web.req('POST', '/admin/appointment.get-appointment-details', { form: { appointment_id: row.id }, ajax: true })).json();
      const d = (await api(tok, '/appointments/' + row.id)).json.data.appointment;
      if (w.status !== 1) { // web 404s when the appointment has no customer join; the API must still answer
        if (!d) problems.push(`#${row.id} api missing`);
        continue;
      }
      const wg = w.services_grouped.map((g) => `${g.service_id}x${g.qty}=${Number(g.line_total).toFixed(2)}`).sort().join(',');
      const ag = d.services_grouped.map((g) => `${g.service_id}x${g.qty}=${g.line_total}`).sort().join(',');
      if (wg !== ag) problems.push(`#${row.id} services_grouped ${wg} vs ${ag}`);
      const ws = w.staff_grouped.map((g) => `${g.staff_name}:${g.services.map((s) => s.service_name + 'x' + s.qty).sort().join('+')}`).sort().join(',');
      const as = d.staff_grouped.map((g) => `${g.staff_name}:${g.services.map((s) => s.service_name + 'x' + s.qty).sort().join('+')}`).sort().join(',');
      if (ws !== as) problems.push(`#${row.id} staff_grouped ${ws} vs ${as}`);
      const wTotal = Number(w.appointment.total_amt) > 0 ? Number(w.appointment.total_amt) : w.services_grouped.reduce((s, g) => s + Number(g.line_total), 0);
      if (wTotal.toFixed(2) !== d.total) problems.push(`#${row.id} total ${wTotal.toFixed(2)} vs ${d.total}`);
      if (w.appointment.status !== d.status) problems.push(`#${row.id} status ${w.appointment.status} vs ${d.status}`);
    }
    rec(`[${label}] appointment detail x${Math.min(list.items.length, 40)} (services, staff groups, totals)`, problems.length === 0, problems.slice(0, 3).join(' | '));
  } catch (e) { rec(`[${label}] appointment detail`, false, e.message); }
}

(async () => {
  await runRole('admin', adminEmail, adminPw, false);
  await runRole('staff', staffEmail, staffPw, true);

  const w = Math.max(...results.map((r) => r.name.length));
  console.log('\nPhase 1 parity: web vs API\n');
  for (const r of results) console.log((r.ok ? '  PASS ' : '  FAIL ') + r.name.padEnd(w) + (r.detail ? '  ' + r.detail : ''));
  const failed = results.filter((r) => !r.ok).length;
  console.log(`\n${results.length - failed}/${results.length} passed` + (failed ? `, ${failed} FAILED` : ''));
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
