#!/usr/bin/env node
/**
 * Parity test, Phase 2 (read side): calendar events, availability, slot finder and
 * staff-by-service, API versus the web's own endpoints.
 *
 *   node parity_phase2.js <webBase> <apiBase> <adminEmail> <adminPw> <staffEmail> <staffPw>
 *
 * Needs the marked test data (APITEST-* appointments and the schedule of the test
 * barber) so that there is something to compare. Needs Node 20+.
 */
const [webBase, apiBase, adminEmail, adminPw, staffEmail, staffPw] = process.argv.slice(2);
if (!staffPw) { console.error('usage: node parity_phase2.js <webBase> <apiBase> <adminEmail> <adminPw> <staffEmail> <staffPw>'); process.exit(2); }

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
  }
  async publicCsrf() { const html = await (await this.req('GET', '/book')).text(); this.csrf = (html.match(/name="csrf-token" content="([^"]+)"/) || [])[1]; }
  async json(method, path, opts) { return (await this.req(method, path, opts)).json(); }
}
async function api(token, path) {
  const res = await fetch(apiBase + path, { headers: { Accept: 'application/json', Authorization: 'Bearer ' + token } });
  return { status: res.status, json: await res.json() };
}
async function apiLogin(email, pw) {
  const res = await fetch(apiBase + '/auth/login', { method: 'POST', headers: { Accept: 'application/json', 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: pw, device_name: 'parity2' }) });
  const j = await res.json(); if (!j.data?.token) throw new Error('api login failed ' + email); return j.data.token;
}
const ed = (n) => new Date(Date.now() + n * 86400000).toLocaleDateString('sv-SE', { timeZone: 'America/Edmonton' });
const sameSet = (a, b) => a.length === b.length && [...a].sort().join('|') === [...b].sort().join('|');
const unesc = (s) => String(s ?? '').replace(/&#0?39;/g, "'").replace(/&amp;/g, '&');

// ---- events ---------------------------------------------------------------------------------
function compareEvents(webEvents, apiEvents, from, to) {
  const inRange = (e) => { const d = String(e.start).slice(0, 10); return d >= from && d <= to; };
  const w = webEvents.filter(inRange);
  const problems = [];
  const wIds = w.map((e) => e.id), aIds = apiEvents.map((e) => e.id);
  if (!sameSet(wIds, aIds)) problems.push(`ids differ web=[${wIds}] api=[${aIds}]`);
  const aBy = new Map(apiEvents.map((e) => [e.id, e]));
  for (const e of w) {
    const a = aBy.get(e.id); if (!a) continue;
    const x = e.extendedProps || {};
    const chk = (label, wv, av) => { if (String(wv ?? '') !== String(av ?? '')) problems.push(`${e.id} ${label}: web "${wv}" vs api "${av}"`); };
    chk('resource', e.resourceId, a.resource_id); chk('title', unesc(e.title), unesc(a.title));
    chk('start', e.start, a.start); chk('end', e.end, a.end);
    if (a.type === 'appointment') {
      chk('appointment_id', x.appointment_id, a.appointment_id); chk('staffName', x.staffName, a.staff_name); chk('staffId', x.staffId, a.staff_id);
      chk('service_id', String(x.service_id || '').split(',').filter(Boolean).join(','), a.service_ids.join(','));
      chk('service_names', unesc(x.service_names), unesc(a.service_names)); chk('duration', x.duration, a.duration);
      chk('phone', x.phone, a.phone); chk('email', x.email, a.email); chk('notes', x.description, a.notes); chk('location', x.location, a.location);
      chk('assigned', x.assigned_staff_name, a.assigned_staff_name);
    } else chk('break staff', x.staffName, a.staff_name);
  }
  return { problems, count: w.length };
}

async function run() {
  const adminWeb = new Web(); await adminWeb.login(adminEmail, adminPw);
  const staffWeb = new Web(); await staffWeb.login(staffEmail, staffPw);
  const adminTok = await apiLogin(adminEmail, adminPw), staffTok = await apiLogin(staffEmail, staffPw);
  const from = ed(-3), to = ed(5);

  // ---- calendar events (CAL-1)
  for (const [label, web, tok, staffId] of [['admin all lanes', adminWeb, adminTok, ''], ['admin lane 51', adminWeb, adminTok, 51], ['admin lane 49', adminWeb, adminTok, 49], ['staff (own lane)', staffWeb, staffTok, '']]) {
    try {
      const wEv = await web.json('GET', '/admin/appointments/fetch' + (staffId !== '' ? `?staff_id=${staffId}` : ''));
      const r = await api(tok, `/calendar/events?from=${from}&to=${to}` + (staffId !== '' ? `&staff_id=${staffId}` : ''));
      const { problems, count } = compareEvents(wEv, r.json.data.events, from, to);
      rec(`calendar events: ${label} (${count} events)`, r.status === 200 && problems.length === 0, problems.slice(0, 3).join(' | '));
    } catch (e) { rec(`calendar events: ${label}`, false, e.message); }
  }
  try {
    const r = await api(adminTok, `/calendar/events?from=${from}&to=${to}`);
    const lanes = r.json.data.lanes.map((l) => l.id);
    const html = await (await adminWeb.req('GET', '/admin/incalender')).text();
    const webLanes = [...html.matchAll(/"id":"(\d+)","title"/g)].map((m) => Number(m[1]));
    rec(`calendar lanes (admin: barbers ${lanes})`, sameSet(lanes.map(String), webLanes.map(String)), `web [${webLanes}] api [${lanes}]`);
    const s = await api(staffTok, `/calendar/events?from=${from}&to=${to}`);
    const html2 = await (await staffWeb.req('GET', '/admin/incalender')).text();
    const webLanes2 = [...html2.matchAll(/"id":"(\d+)","title"/g)].map((m) => Number(m[1]));
    rec(`calendar lanes (staff: ${s.json.data.lanes.map((l) => l.id)})`, sameSet(s.json.data.lanes.map((l) => String(l.id)), webLanes2.map(String)), `web [${webLanes2}]`);
  } catch (e) { rec('calendar lanes', false, e.message); }

  // ---- availability (CAL-2)
  const norm = (staff) => { const o = {}; const src = Array.isArray(staff) ? {} : staff; for (const [id, v] of Object.entries(src)) o[id] = { off: !!v.is_day_off, hours: JSON.stringify(v.working_hours), breaks: JSON.stringify(v.breaks) }; return o; };
  const availBad = [];
  let availN = 0;
  for (let d = 0; d <= 8; d++) {
    for (const sid of ['', '49', '51']) {
      const date = ed(d);
      const w = await adminWeb.json('GET', `/admin/staff-availability?date=${date}&staff_id=${sid}`);
      const a = (await api(adminTok, `/calendar/availability?date=${date}` + (sid ? `&staff_id=${sid}` : ''))).json.data;
      availN++;
      const same = w.shop_open === a.shop_open && w.shop_close === a.shop_close && !!w.shop_day_off === a.shop_day_off && JSON.stringify(norm(w.staff)) === JSON.stringify(norm(a.staff));
      if (!same) availBad.push(`${date}/${sid || 'all'}`);
    }
  }
  rec(`availability: 9 days x 3 staff filters (${availN} comparisons)`, availBad.length === 0, availBad.slice(0, 4).join(', '));
  {
    const date = ed(2);
    const w = await staffWeb.json('GET', `/admin/staff-availability?date=${date}&staff_id=${''}`);
    const a = (await api(staffTok, `/calendar/availability?date=${date}`)).json.data;
    const only51 = Object.keys(a.staff).join(',') === '51';
    rec('availability: staff user sees only their own lane (web returns everyone when the filter is empty)', only51, `api lanes: ${Object.keys(a.staff)}; web lanes: ${Object.keys(w.staff || {})}`);
  }

  // ---- slot finder (APPT-7) vs the public engine
  const pub = new Web(); await pub.publicCsrf();
  const combos = [
    ['barber 49, Men\'s cut', [49], [25]], ['barber 51, Men\'s cut', [51], [25]], ['barber 51, 3 services', [51], [25, 26, 27]],
    ['barber 49, same service twice', [49], [25, 25]], ['two barbers, two services', [49, 51], [25, 26]],
    ['First available', [19], [25]], ['barber 49, long visit (4 services)', [49], [28, 29, 30, 31]],
  ];
  for (const [name, staff, svcs] of combos) {
    const bad = []; let n = 0;
    for (const d of [0, 1, 2, 3, 6]) {
      const date = ed(d); const [y, m, day] = date.split('-').map(Number);
      const dayName = new Date(Date.UTC(y, m - 1, day, 12)).toLocaleDateString('en-US', { weekday: 'long', timeZone: 'UTC' });
      const w = await pub.json('POST', '/get-slot-by-staff', { form: { selectedYear: y, selectedMonth: m - 1, selectedDay: day, staff_id: staff.join(','), service_id: svcs.join(','), day_name: dayName }, ajax: true });
      const a = (await api(adminTok, `/appointments/slots?date=${date}&staff_ids=${staff.join(',')}&service_ids=${svcs.join(',')}`)).json.data;
      n++;
      const wSlots = (w.slots || []).map((s) => `${s.start}-${s.end}`).join(',');
      const aSlots = a.slots.map((s) => `${s.start}-${s.end}`).join(',');
      const wGroups = (w.groups || []).map((g) => `${g.staff_id}:${g.staff_name}:${g.duration}:${(g.slots || []).map((s) => s.start).join('/')}`).join(';');
      const aGroups = a.groups.map((g) => `${g.staff_id}:${g.staff_name}:${g.duration}:${g.slots.map((s) => s.start).join('/')}`).join(';');
      if (wSlots !== aSlots || wGroups !== aGroups || (w.duration || 0) !== a.duration) bad.push(`${date}: slots web=${wSlots.length}c api=${aSlots.length}c`);
      if ((w.status === 0) === a.available && (w.slots || []).length) bad.push(`${date}: availability flag`);
    }
    rec(`slots: ${name} (${n} dates)`, bad.length === 0, bad.slice(0, 3).join(' | '));
  }

  // ---- staff by service (APPT-10)
  for (const svcs of [[25], [26, 27], [28, 29, 30], [999999]]) {
    const q = svcs.map((s) => 'service_ids[]=' + s).join('&');
    const w1 = await adminWeb.json('GET', '/admin/getstaffByService?' + encodeURI(q));
    const a = (await api(adminTok, `/appointments/staff-by-service?service_ids=${svcs.join(',')}`)).json;
    const w2 = await adminWeb.json('POST', '/admin/appointment.get-staff-by-service', { form: new URLSearchParams(svcs.map((s) => ['service_ids[]', s])), ajax: true });
    const aIds = (a.data?.staff || []).map((s) => String(s.id));
    const w1Ids = (w1.data || []).map((u) => String(u.id));
    const w2Ids = [...new Set((w2.staff || []).map((r) => String(r.staff_id)))];
    rec(`staff-by-service [${svcs}] → [${aIds}]`, sameSet(aIds, w1Ids) && sameSet(aIds, w2Ids), `web1 [${w1Ids}] web2 [${w2Ids}] api [${aIds}]`);
  }

  const w = Math.max(...results.map((r) => r.name.length));
  console.log('\nPhase 2 read parity: web vs API\n');
  for (const r of results) console.log((r.ok ? '  PASS ' : '  FAIL ') + r.name.padEnd(w) + (r.detail ? '  ' + r.detail : ''));
  const failed = results.filter((r) => !r.ok).length;
  console.log(`\n${results.length - failed}/${results.length} passed` + (failed ? `, ${failed} FAILED` : ''));
  process.exit(failed ? 1 : 0);
}
run().catch((e) => { console.error(e); process.exit(1); });
