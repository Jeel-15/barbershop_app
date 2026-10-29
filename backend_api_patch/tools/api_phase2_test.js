#!/usr/bin/env node
/**
 * Phase 2 behaviour tests (writes): booking from the calendar, edit, reschedule,
 * breaks, working hours, permissions, concurrency, and write-parity with the web.
 *
 *   node api_phase2_test.js <webBase> <apiBase> <adminEmail> <adminPw> <staffEmail> <staffPw>
 *
 * Needs the marked test data and a local MySQL reachable as `mysql -uroot barber_shop_db`.
 * Everything it creates is named "API TEST …" / phone 555999xxxx and is removed by the
 * test-data cleanup.
 */
const { execSync } = require('child_process');
const [webBase, apiBase, adminEmail, adminPw, staffEmail, staffPw] = process.argv.slice(2);
if (!staffPw) { console.error('usage: node api_phase2_test.js <webBase> <apiBase> <adminEmail> <adminPw> <staffEmail> <staffPw>'); process.exit(2); }

const results = [];
const rec = (name, ok, detail = '') => results.push({ name, ok, detail });
const sql = (q) => execSync('mysql -uroot -h127.0.0.1 -N -B barber_shop_db', { input: q, encoding: 'utf8' }).trim();
const rows = (q) => sql(q).replace(/\r/g, '').split('\n').filter(Boolean).map((l) => l.split('\t'));
const one = (q) => (rows(q)[0] || [])[0];
const ed = (n) => new Date(Date.now() + n * 86400000).toLocaleDateString('sv-SE', { timeZone: 'America/Edmonton' });

class Web {
  constructor() { this.jar = {}; this.csrf = null; }
  cookieHeader() { return Object.entries(this.jar).map(([k, v]) => `${k}=${v}`).join('; '); }
  store(res) { for (const c of res.headers.getSetCookie?.() || []) { const [pair] = c.split(';'); const i = pair.indexOf('='); this.jar[pair.slice(0, i)] = pair.slice(i + 1); } }
  async req(method, path, { form } = {}) {
    const headers = { Cookie: this.cookieHeader(), 'X-Requested-With': 'XMLHttpRequest', 'X-CSRF-TOKEN': this.csrf, Accept: 'application/json' };
    let body;
    if (form) { headers['Content-Type'] = 'application/x-www-form-urlencoded'; body = (form instanceof URLSearchParams ? form : new URLSearchParams(form)).toString(); }
    const res = await fetch(webBase + path, { method, headers, body, redirect: 'manual' });
    this.store(res); return res;
  }
  async login(email, pw) {
    const page = await (await fetch(webBase + '/admin/login', { headers: { Cookie: this.cookieHeader() } })).text();
    const probe = await fetch(webBase + '/admin/login'); this.store(probe);
    const html = await (await fetch(webBase + '/admin/login', { headers: { Cookie: this.cookieHeader() } })).text();
    const token = (html.match(/name="_token" value="([^"]+)"/) || [])[1];
    const res = await fetch(webBase + '/admin/post-login', { method: 'POST', redirect: 'manual', headers: { 'Content-Type': 'application/x-www-form-urlencoded', Cookie: this.cookieHeader() }, body: new URLSearchParams({ _token: token, email, password: pw }).toString() });
    this.store(res);
    if (res.status !== 302) throw new Error('web login failed ' + email);
    const dash = await (await fetch(webBase + '/admin/dashboard', { headers: { Cookie: this.cookieHeader() } })).text();
    this.csrf = (dash.match(/name="csrf-token" content="([^"]+)"/) || [])[1];
  }
}
async function call(method, path, { token, body } = {}) {
  const headers = { Accept: 'application/json' };
  if (token) headers.Authorization = 'Bearer ' + token;
  if (body) headers['Content-Type'] = 'application/json';
  const res = await fetch(apiBase + path, { method, headers, body: body ? JSON.stringify(body) : undefined });
  let json = null; try { json = await res.json(); } catch { /* none */ }
  return { status: res.status, json };
}
const login = async (e, p, d = 'p2') => (await call('POST', '/auth/login', { body: { email: e, password: p, device_name: d } })).json.data.token;
async function t(name, fn) { try { const r = await fn(); rec(name, r.ok, r.detail || ''); } catch (e) { rec(name, false, 'EXCEPTION ' + e.message); } }

const apptRow = (id) => rows(`select date,slot_start,slot_end,name,email,phone,ifnull(notes,''),status,comment from tbl_appointment where appointment_id=${id}`)[0]?.join('|');
const lineRows = (id) => rows(`select service_id,staff_id,ifnull(requested_staff_id,'N'),is_first_available,product_commission,service_commission,service_tip,total_amt,status,comment from tbl_appointment_service where appointment_id=${id} order by service_id,id`).map((r) => r.join('|')).join(' ; ');
const lastApptByName = (name) => Number(one(`select appointment_id from tbl_appointment where name='${name}' order by appointment_id desc limit 1`));

(async () => {
  const admin = await login(adminEmail, adminPw), staff = await login(staffEmail, staffPw);
  const adminWeb = new Web(); await adminWeb.login(adminEmail, adminPw);
  const staffWeb = new Web(); await staffWeb.login(staffEmail, staffPw);
  const D3 = ed(3), D4 = ed(4), D5 = ed(5), D6 = ed(6), D7 = ed(7), D8 = ed(8);
  const A1 = Number(one("select appointment_id from tbl_appointment where booking_code='APITEST-1'"));
  const A2 = Number(one("select appointment_id from tbl_appointment where booking_code='APITEST-2'"));
  const A4 = Number(one("select appointment_id from tbl_appointment where booking_code='APITEST-4'"));
  const A5 = Number(one("select appointment_id from tbl_appointment where booking_code='APITEST-5'"));
  const completedId = Number(one('select appointment_id from tbl_appointment where status=1 limit 1'));
  const mk = (over = {}) => ({ date: D3, time: '10:00', staff_id: 51, services: [{ id: 25, qty: 2 }, { id: 26, qty: 1 }], name: 'API TEST New', phone: '5559990001', email: 'new@test.test', notes: 'first visit', ...over });

  // ======================================================== slot finder + staff by service (validation)
  await t('APPT-7 slots: validation (missing/ past date / no barber) → 422', async () => {
    const a = await call('GET', '/appointments/slots', { token: admin });
    const b = await call('GET', `/appointments/slots?date=${ed(-1)}&staff_ids=51&service_ids=25`, { token: admin });
    const c = await call('GET', `/appointments/slots?date=${D3}&staff_ids=abc&service_ids=25`, { token: admin });
    return { ok: a.status === 422 && b.status === 422 && c.status === 422, detail: `${a.status}/${b.status}/${c.status}` };
  });
  await t('APPT-7 slots: typed slots with labels, groups per barber, duration = sum of services', async () => {
    const r = await call('GET', `/appointments/slots?date=${D3}&staff_ids=51&service_ids=25,26`, { token: staff });
    const d = r.json.data;
    return { ok: r.status === 200 && d.available && d.duration === 60 && /^\d\d:\d\d$/.test(d.slots[0].start) && /AM|PM/.test(d.slots[0].start_label) && d.groups.length >= 1, detail: `duration ${d.duration}, ${d.slots.length} slots, first ${d.slots[0]?.start_label}` };
  });
  await t('APPT-10 staff-by-service: validation and shape', async () => {
    const bad = await call('GET', '/appointments/staff-by-service', { token: admin });
    const ok = await call('GET', '/appointments/staff-by-service?service_ids=25,26', { token: admin });
    const s = ok.json.data.staff;
    return { ok: bad.status === 422 && ok.status === 200 && s.length >= 2 && s.every((x) => Number.isInteger(x.id) && x.name && x.profile_image_url && Array.isArray(x.offers_service_ids)), detail: `${s.length} barbers` };
  });

  // ======================================================== create (APPT-8)
  let created;
  await t('create: 201, detail with qty (2×Men\'s cut + Skin fade), 90 min window 10:00–11:30, Pending, booking code', async () => {
    const r = await call('POST', '/appointments', { token: admin, body: mk() });
    const a = r.json?.data?.appointment; created = a?.id;
    const q = a?.services_grouped?.find((g) => g.service_id === 25);
    return { ok: r.status === 201 && a.status === 0 && a.start === '10:00' && a.end === '11:30' && q?.qty === 2 && /^BCB-/.test(a.booking_code) && a.customer.phone === '5559990001' && a.total !== undefined, detail: `http ${r.status} #${created} ${a?.start}-${a?.end} ${a?.booking_code}` };
  });
  await t('create writes the rows the web writes (comment=name, 3 unit lines, requested=staff, zero commissions)', async () => {
    const lines = rows(`select staff_id,requested_staff_id,is_first_available,product_commission,service_commission,service_tip,total_amt,status,comment from tbl_appointment_service where appointment_id=${created}`);
    const a = rows(`select status,comment,name,notes from tbl_appointment where appointment_id=${created}`)[0];
    const newCust = Number(one("select count(*) from customers where customer_phone='5559990001'"));
    return { ok: lines.length === 3 && lines.every((l) => l.join('|') === '51|51|0|0|0|0|0|0|Appointment from calendar') && a[0] === '0' && a[1] === 'API TEST New' && newCust === 1, detail: `${lines.length} lines, customers ${newCust}, appt ${a.join('|')}, lines ${lines.map((l) => l.join('|')).join(' ; ')}` };
  });
  await t('create reuses the customer found by phone (no duplicate customer)', async () => {
    const r = await call('POST', '/appointments', { token: admin, body: mk({ time: '12:00', services: [{ id: 25, qty: 1 }] }) });
    const n = Number(one("select count(*) from customers where customer_phone='5559990001'"));
    return { ok: r.status === 201 && n === 1, detail: `http ${r.status}, customers=${n}` };
  });
  await t('overlap rules (same staff, same day, inclusive like the web): inside, touching end, touching start, covering → 409; 1 min apart → 201', async () => {
    const inside = await call('POST', '/appointments', { token: admin, body: mk({ time: '10:30', services: [{ id: 25, qty: 1 }] }) });
    const touchEnd = await call('POST', '/appointments', { token: admin, body: mk({ time: '11:30', services: [{ id: 25, qty: 1 }] }) });        // starts exactly when the first ends
    const touchStart = await call('POST', '/appointments', { token: admin, body: mk({ time: '09:30', services: [{ id: 25, qty: 1 }] }) });       // ends exactly when the first starts
    const cover = await call('POST', '/appointments', { token: admin, body: mk({ time: '09:00', services: [{ id: 25, qty: 4 }] }) });            // 120 min around it
    const apart = await call('POST', '/appointments', { token: admin, body: mk({ time: '16:01', services: [{ id: 25, qty: 1 }] }) });
    return { ok: [inside, touchEnd, touchStart, cover].every((r) => r.status === 409 && /already has an appointment/.test(r.json.message)) && apart.status === 201, detail: [inside, touchEnd, touchStart, cover, apart].map((r) => r.status).join('/') };
  });
  await t('another barber at the same time is fine', async () => {
    const r = await call('POST', '/appointments', { token: admin, body: mk({ staff_id: 49, name: 'API TEST Other barber', phone: '5559990002' }) });
    return { ok: r.status === 201, detail: `http ${r.status}` };
  });
  await t('"First available" lane: lines flagged is_first_available=1 and requested=the pseudo user (web rule)', async () => {
    const r = await call('POST', '/appointments', { token: admin, body: mk({ staff_id: 19, date: D8, time: '11:00', services: [{ id: 25, qty: 1 }], name: 'API TEST FA', phone: '5559990003' }) });
    const id = r.json?.data?.appointment?.id;
    const l = rows(`select staff_id,requested_staff_id,is_first_available from tbl_appointment_service where appointment_id=${id}`)[0];
    return { ok: r.status === 201 && l.join('|') === '19|19|1', detail: l?.join('|') };
  });
  await t('create validation: past date, no phone, qty 0 / 21, unknown service, non-staff id, crosses midnight, bad time, no services → 422', async () => {
    const cases = [mk({ date: ed(-1) }), (({ phone, ...r }) => r)(mk()), mk({ services: [{ id: 25, qty: 0 }] }), mk({ services: [{ id: 25, qty: 21 }] }), mk({ services: [{ id: 999999, qty: 1 }] }), mk({ staff_id: 1 }), mk({ time: '23:30' }), mk({ time: '25:00' }), mk({ services: [] })];
    const out = []; for (const b of cases) out.push((await call('POST', '/appointments', { token: admin, body: b })).status);
    return { ok: out.every((s) => s === 422), detail: out.join('/') };
  });
  await t('staff creates on their OWN calendar (201) but not for another barber (403)', async () => {
    const own = await call('POST', '/appointments', { token: staff, body: mk({ date: D4, time: '09:00', name: 'API TEST Staff own', phone: '5559990004', services: [{ id: 25, qty: 1 }] }) });
    const other = await call('POST', '/appointments', { token: staff, body: mk({ staff_id: 49, date: D4, time: '09:00', name: 'API TEST Staff other', phone: '5559990005' }) });
    return { ok: own.status === 201 && other.status === 403, detail: `own ${own.status}, other ${other.status}` };
  });
  await t('two phones booking the SAME slot at the same instant → exactly one 201, one 409', async () => {
    const a = call('POST', '/appointments', { token: admin, body: mk({ date: D7, time: '15:00', services: [{ id: 25, qty: 1 }], name: 'API TEST Race A', phone: '5559990006' }) });
    const b = call('POST', '/appointments', { token: staff, body: mk({ date: D7, time: '15:00', services: [{ id: 25, qty: 1 }], name: 'API TEST Race B', phone: '5559990007' }) });
    const [x, y] = await Promise.all([a, b]);
    const sts = [x.status, y.status].sort();
    const rowsAt = Number(one(`select count(*) from tbl_appointment a join tbl_appointment_service s on s.appointment_id=a.appointment_id where s.staff_id=51 and a.date='${D7}' and a.slot_start='15:00:00'`));
    return { ok: sts.join() === '201,409' && rowsAt === 1, detail: `statuses ${sts}, rows in that slot: ${rowsAt}` };
  });

  // ======================================================== create parity with the web
  await t('WRITE PARITY create: web appointMentBook vs API produce identical appointment + line rows', async () => {
    const form = new URLSearchParams({ appointment_date: `${D5}T14:00`, total_duration: '90', staff_id: '51', name: 'API TEST Parity W', phone: '5559990010', email: 'p@test.test' });
    form.append('service_id[]', '25'); form.append('service_id[]', '25'); form.append('service_id[]', '26');
    const w = await (await adminWeb.req('POST', '/admin/appointMentBook', { form })).json();
    const r = await call('POST', '/appointments', { token: admin, body: { date: D6, time: '14:00', staff_id: 51, services: [{ id: 25, qty: 2 }, { id: 26, qty: 1 }], name: 'API TEST Parity A', phone: '5559990011', email: 'p@test.test' } });
    const wId = lastApptByName('API TEST Parity W'), aId = r.json.data.appointment.id;
    const norm = (s) => s.replace(/Parity [WA]/g, 'Parity X').replace(D5, 'D').replace(D6, 'D').replace(/5559990010|5559990011/, 'PH');
    const wRow = norm(apptRow(wId)), aRow = norm(apptRow(aId));
    return { ok: w.status === 200 && r.status === 201 && wRow === aRow && lineRows(wId) === lineRows(aId), detail: `web="${wRow}" api="${aRow}" lines equal=${lineRows(wId) === lineRows(aId)}` };
  });

  // ======================================================== edit (APPT-9)
  await t('edit: status resets to Pending, contact + time + services replaced, 200', async () => {
    await call('POST', `/appointments/${created}/confirm`, { token: admin });
    const before = rows(`select status from tbl_appointment where appointment_id=${created}`)[0][0];
    const r = await call('PUT', `/appointments/${created}`, { token: admin, body: mk({ time: '13:00', services: [{ id: 27, qty: 1 }], name: 'API TEST Edited', phone: '5559990001', notes: 'changed' }) });
    const a = r.json?.data?.appointment;
    return { ok: before === '3' && r.status === 200 && a.status === 0 && a.start === '13:00' && a.end === '13:25' && a.services_grouped.length === 1 && a.services_grouped[0].service_id === 27 && a.customer.phone === '5559990001', detail: `was ${before}, now ${r.status} ${a?.status} ${a?.start}-${a?.end} svc ${JSON.stringify(a?.services_grouped?.map((g) => g.service_id))} cust ${a?.customer?.name}` };
  });
  await t('edit only replaces THIS barber\'s lane: the other barber\'s line on APITEST-2 survives', async () => {
    const before = Number(one(`select count(*) from tbl_appointment_service where appointment_id=${A2} and staff_id=49`));
    const r = await call('PUT', `/appointments/${A2}`, { token: admin, body: mk({ date: ed(2), time: '10:00', services: [{ id: 26, qty: 1 }], name: 'API TEST A2 edited', phone: '5559990012' }) });
    const after49 = Number(one(`select count(*) from tbl_appointment_service where appointment_id=${A2} and staff_id=49`));
    const after51 = Number(one(`select count(*) from tbl_appointment_service where appointment_id=${A2} and staff_id=51`));
    return { ok: r.status === 200 && before === 1 && after49 === 1 && after51 === 1, detail: `49: ${before}→${after49}, 51 lane now ${after51} line(s)` };
  });
  await t('edit refused for Completed / Cancelled (409), unknown (404), overlap with another booking (409)', async () => {
    const done = await call('PUT', `/appointments/${completedId}`, { token: admin, body: mk() });
    const canc = await call('PUT', `/appointments/${A5}`, { token: admin, body: mk() });
    const none = await call('PUT', '/appointments/99999999', { token: admin, body: mk() });
    const clash = await call('PUT', `/appointments/${created}`, { token: admin, body: mk({ date: D7, time: '15:00', services: [{ id: 25, qty: 1 }] }) });
    return { ok: done.status === 409 && canc.status === 409 && none.status === 404 && clash.status === 409, detail: [done, canc, none, clash].map((r) => r.status).join('/') };
  });
  await t('staff cannot edit another barber\'s appointment (404) nor move it to another lane (403)', async () => {
    const other = await call('PUT', `/appointments/${A4}`, { token: staff, body: mk({ time: '09:00', date: ed(0) }) });
    const lane = await call('PUT', `/appointments/${A1}`, { token: staff, body: mk({ staff_id: 49, date: ed(0), time: '16:00' }) });
    return { ok: other.status === 404 && lane.status === 403, detail: `${other.status}/${lane.status}` };
  });
  await t('WRITE PARITY edit: web vs API leave identical rows', async () => {
    const mkOne = async (name, date, phone) => (await call('POST', '/appointments', { token: admin, body: { date, time: '16:00', staff_id: 51, services: [{ id: 25, qty: 1 }], name, phone } })).json.data.appointment.id;
    const wId = await mkOne('API TEST Edit W', D5, '5559990020'), aId = await mkOne('API TEST Edit A', D6, '5559990021');
    await call('POST', `/appointments/${wId}/confirm`, { token: admin }); await call('POST', `/appointments/${aId}/confirm`, { token: admin });
    const form = new URLSearchParams({ appointment_id: String(wId), appointment_date: `${D5}T17:00`, total_duration: '55', staff_id: '51', name: 'API TEST Edit X', phone: '5559990020', email: 'e@test.test' });
    form.append('service_id[]', '26'); form.append('service_id[]', '27');
    const w = await (await adminWeb.req('POST', '/admin/appointMentBook', { form })).json();
    const r = await call('PUT', `/appointments/${aId}`, { token: admin, body: { date: D6, time: '17:00', staff_id: 51, services: [{ id: 26, qty: 1 }, { id: 27, qty: 1 }], name: 'API TEST Edit X', phone: '5559990020', email: 'e@test.test' } });
    const norm = (s) => s.replace(D5, 'D').replace(D6, 'D');
    return { ok: w.status === 200 && r.status === 200 && norm(apptRow(wId)) === norm(apptRow(aId)) && lineRows(wId) === lineRows(aId), detail: `web="${apptRow(wId)}" api="${apptRow(aId)}"` };
  });

  // ======================================================== reschedule (APPT-6)
  const offered = async (staffIds, svc, date) => (await call('GET', `/appointments/slots?date=${date}&staff_ids=${staffIds}&service_ids=${svc}`, { token: admin })).json.data.slots;
  await t('reschedule a Pending appointment to a slot the engine offers → 200, status Rescheduled (4), new date/time saved', async () => {
    const s = (await offered('51', '25', D4))[5];
    const r = await call('POST', `/appointments/${A1}/reschedule`, { token: admin, body: { date: D4, slot_start: s.start, slot_end: s.end } });
    const a = r.json?.data?.appointment;
    return { ok: r.status === 200 && a.status === 4 && a.date === D4 && a.start === s.start && a.end === s.end && apptRow(A1).includes(D4), detail: `→ ${a?.date} ${a?.start}-${a?.end} ${a?.status_label}` };
  });
  await t('a Rescheduled appointment cannot be rescheduled again (the web shows no button): 409', async () => {
    const s = (await offered('51', '25', D4))[7];
    const r = await call('POST', `/appointments/${A1}/reschedule`, { token: admin, body: { date: D4, slot_start: s.start, slot_end: s.end } });
    return { ok: r.status === 409, detail: r.json?.message };
  });
  await t('a Cancelled appointment CAN be rescheduled (web shows the button) → Rescheduled', async () => {
    const s = (await offered('51', '25', D4))[9];
    const r = await call('POST', `/appointments/${A5}/reschedule`, { token: admin, body: { date: D4, slot_start: s.start, slot_end: s.end } });
    return { ok: r.status === 200 && r.json.data.appointment.status === 4, detail: r.json?.message };
  });
  await t('reschedule refused: Confirmed (409), Completed (409), unknown (404), staff on someone else\'s (404)', async () => {
    const s = (await offered('51', '27', D4))[2] || { start: '10:00', end: '10:25' };
    const body = { date: D4, slot_start: s.start, slot_end: s.end };
    const conf = await call('POST', `/appointments/${A2}/reschedule`, { token: admin, body });   // A2 was reset to Pending by the edit test, confirm it first
    await call('POST', `/appointments/${A2}/confirm`, { token: admin });
    const conf2 = await call('POST', `/appointments/${A2}/reschedule`, { token: admin, body });
    const done = await call('POST', `/appointments/${completedId}/reschedule`, { token: admin, body });
    const none = await call('POST', '/appointments/99999999/reschedule', { token: admin, body });
    const other = await call('POST', `/appointments/${A4}/reschedule`, { token: staff, body });
    return { ok: conf2.status === 409 && done.status === 409 && none.status === 404 && other.status === 404, detail: `confirmed ${conf2.status}, completed ${done.status}, unknown ${none.status}, other's ${other.status}` };
  });
  await t('reschedule validation: a time the engine does not offer → 409; wrong end → 409; past date, bad format, end ≤ start → 422', async () => {
    const id = lastApptByName('API TEST Race A') || A4;
    const mine = (await call('POST', '/appointments', { token: admin, body: mk({ date: D8, time: '16:00', services: [{ id: 25, qty: 1 }], name: 'API TEST Resched', phone: '5559990030' }) })).json.data.appointment.id;
    const s = (await offered('51', '25', D4))[3];
    const notOffered = await call('POST', `/appointments/${mine}/reschedule`, { token: admin, body: { date: D4, slot_start: '03:00', slot_end: '03:30' } });
    const wrongEnd = await call('POST', `/appointments/${mine}/reschedule`, { token: admin, body: { date: D4, slot_start: s.start, slot_end: '23:00' } });
    const past = await call('POST', `/appointments/${mine}/reschedule`, { token: admin, body: { date: ed(-1), slot_start: s.start, slot_end: s.end } });
    const fmt = await call('POST', `/appointments/${mine}/reschedule`, { token: admin, body: { date: D4, slot_start: '9am', slot_end: s.end } });
    const order = await call('POST', `/appointments/${mine}/reschedule`, { token: admin, body: { date: D4, slot_start: s.end, slot_end: s.start } });
    return { ok: notOffered.status === 409 && wrongEnd.status === 409 && past.status === 422 && fmt.status === 422 && order.status === 422 && statusOfAppt(mine) === 0, detail: [notOffered, wrongEnd, past, fmt, order].map((r) => r.status).join('/') };
  });
  await t('reschedule: two appointments racing for the same slot → one 200, one 409', async () => {
    const mkAppt = async (n, ph) => (await call('POST', '/appointments', { token: admin, body: { date: D8, time: n === 'RA' ? '09:00' : '10:00', staff_id: 51, services: [{ id: 25, qty: 1 }], name: 'API TEST Race ' + n, phone: ph } })).json.data.appointment.id;
    const x = await mkAppt('RA', '5559990040'), y = await mkAppt('RB', '5559990041');
    const s = (await offered('51', '25', D4)).find((q) => q.start >= '15:00') || (await offered('51', '25', D4)).pop();
    const [rx, ry] = await Promise.all([call('POST', `/appointments/${x}/reschedule`, { token: admin, body: { date: D4, slot_start: s.start, slot_end: s.end } }), call('POST', `/appointments/${y}/reschedule`, { token: admin, body: { date: D4, slot_start: s.start, slot_end: s.end } })]);
    const sts = [rx.status, ry.status].sort();
    return { ok: sts.join() === '200,409', detail: `statuses ${sts}` };
  });
  await t('WRITE PARITY reschedule: web vs API leave identical rows (date, slot, status 4)', async () => {
    const mkOne = async (n, ph) => (await call('POST', '/appointments', { token: admin, body: { date: D8, time: n === 'W' ? '11:00' : '12:00', staff_id: 51, services: [{ id: 25, qty: 1 }], name: 'API TEST RS ' + n, phone: ph } })).json.data.appointment.id;
    const wId = await mkOne('W', '5559990050'), aId = await mkOne('A', '5559990051');
    const slots = await offered('51', '25', D3);
    const sW = slots[10], sA = slots[12];
    const w = await (await adminWeb.req('POST', '/admin/appointment.submit-reschedule-appointment', { form: { appointment_id: wId, date: D3, slot_start: sW.start, slot_end: sW.end, staff_id: '51', service_id: '25' } })).json();
    const r = await call('POST', `/appointments/${aId}/reschedule`, { token: admin, body: { date: D3, slot_start: sA.start, slot_end: sA.end } });
    const cut = (id, s) => rows(`select date,slot_start,slot_end,status from tbl_appointment where appointment_id=${id}`)[0].join('|').replace(s.start + ':00', 'S').replace(s.end + ':00', 'E');
    return { ok: w.status === 1 && r.status === 200 && cut(wId, sW) === cut(aId, sA), detail: `web="${cut(wId, sW)}" api="${cut(aId, sA)}"` };
  });

  // ======================================================== breaks (CAL-3)
  const today = ed(0);
  await t('CAL-3 break: 1 h from now → 201, ad-hoc row (type 2, slot 0), shows in events and availability', async () => {
    const r = await call('POST', '/calendar/breaks', { token: admin, body: { staff_id: 51, hour: 1, minute: 0 } });
    const row = rows(`select slot_id,staff_id,break_type,break_start,break_end from tbl_breaks where id=${r.json?.data?.break?.id}`)[0];
    const ev = (await call('GET', `/calendar/events?from=${today}&to=${today}&staff_id=51`, { token: admin })).json.data.events.filter((e) => e.type === 'break' && e.break_id === r.json.data.break.id);
    const av = (await call('GET', `/calendar/availability?date=${today}&staff_id=51`, { token: admin })).json.data.staff['51'].breaks;
    return { ok: r.status === 201 && row[0] === '0' && row[1] === '51' && row[2] === '2' && ev.length === 1 && av.length >= 1, detail: `row ${row.join('|')}, events ${ev.length}, availability breaks ${av.length}` };
  });
  await t('CAL-3 break: rest of the day → 00:00–23:59:59', async () => {
    const r = await call('POST', '/calendar/breaks', { token: admin, body: { staff_id: 51, rest_of_day: true } });
    const row = rows(`select break_start,break_end from tbl_breaks where id=${r.json.data.break.id}`)[0];
    return { ok: r.status === 201 && row[0] === '00:00:00' && row[1] === '23:59:59', detail: row.join('–') };
  });
  await t('a rest-of-day break removes that barber\'s slots for today (engine honours it)', async () => {
    const r = await call('GET', `/appointments/slots?date=${today}&staff_ids=51&service_ids=25`, { token: admin });
    return { ok: r.status === 200 && r.json.data.slots.length === 0, detail: `${r.json.data.slots.length} slots, message: ${r.json.data.message}` };
  });
  await t('break validation: zero length, hour 24, unknown barber → 422; staff on another barber → 403; staff on self → 201', async () => {
    const z = await call('POST', '/calendar/breaks', { token: admin, body: { staff_id: 51, hour: 0, minute: 0 } });
    const h = await call('POST', '/calendar/breaks', { token: admin, body: { staff_id: 51, hour: 24, minute: 0 } });
    const u = await call('POST', '/calendar/breaks', { token: admin, body: { staff_id: 1, hour: 1, minute: 0 } });
    const o = await call('POST', '/calendar/breaks', { token: staff, body: { staff_id: 49, hour: 1, minute: 0 } });
    const s = await call('POST', '/calendar/breaks', { token: staff, body: { staff_id: 51, hour: 0, minute: 15 } });
    return { ok: z.status === 422 && h.status === 422 && u.status === 422 && o.status === 403 && s.status === 201, detail: [z, h, u, o, s].map((r) => r.status).join('/') };
  });
  await t('WRITE PARITY break: web breakFormSubmit vs API store the same kind of row', async () => {
    const w = await (await adminWeb.req('POST', '/admin/breakFormSubmit', { form: { restoftheday: 0, hour: 0, minute: 30, break_staff_id: 49, break_type: 2 } })).json();
    const r = await call('POST', '/calendar/breaks', { token: admin, body: { staff_id: 49, hour: 0, minute: 30 } });
    const pair = rows(`select staff_id,break_type,slot_id,timestampdiff(minute,break_start,break_end) from tbl_breaks where staff_id=49 and break_type=2 and slot_id=0 order by id desc limit 2`).map((x) => x.join('|'));
    return { ok: (w.status === 1 || w.status === 200) && r.status === 201 && pair[0] === pair[1] && pair[0] === '49|2|0|30', detail: pair.join(' vs ') + ` webresp ${JSON.stringify(w)} api ${r.status} ${r.json?.message}` };
  });

  // ======================================================== working hours (ME-7..11)
  let day, block, other49;
  await t('ME-7 working hours: 7 days × 2 blocks, sorted; admin → 403', async () => {
    const r = await call('GET', '/me/working-hours', { token: staff });
    const a = await call('GET', '/me/working-hours', { token: admin });
    day = r.json.data.days[0]; block = day.blocks[0];
    other49 = rows("select b.id, s.id from tbl_breaks b join tbl_slots s on s.id=b.slot_id where s.staff_id=49 and b.break_type=1 limit 1")[0];
    return { ok: r.status === 200 && r.json.data.days.length === 7 && r.json.data.days.every((d) => d.blocks.length === 2 && d.blocks[0].start < d.blocks[1].start) && a.status === 403, detail: `${r.json.data.days.length} days, admin ${a.status}; first block ${block.start}-${block.end}` };
  });
  await t('ME-8 add block: overlap → 409 (web message), adjacent ok → 201, end ≤ start / bad format → 422, other barber\'s day → 404', async () => {
    const overlap = await call('POST', '/me/working-hours', { token: staff, body: { day_id: day.slot_id, start_time: '12:00', end_time: '15:00' } });
    const adj = await call('POST', '/me/working-hours', { token: staff, body: { day_id: day.slot_id, start_time: '13:00', end_time: '14:00' } });
    const order = await call('POST', '/me/working-hours', { token: staff, body: { day_id: day.slot_id, start_time: '20:00', end_time: '19:00' } });
    const fmt = await call('POST', '/me/working-hours', { token: staff, body: { day_id: day.slot_id, start_time: '8am', end_time: '9:00' } });
    const foreign = await call('POST', '/me/working-hours', { token: staff, body: { day_id: Number(other49[1]), start_time: '19:00', end_time: '20:00' } });
    block = adj.json?.data?.block;
    return { ok: overlap.status === 409 && /overlaps with an existing working hour/.test(overlap.json.message) && adj.status === 201 && order.status === 422 && fmt.status === 422 && foreign.status === 404, detail: [overlap, adj, order, fmt, foreign].map((r) => r.status).join('/') };
  });
  await t('ME-9 update block: overlap → 409, valid → 200, another barber\'s block → 404', async () => {
    const bad = await call('PUT', `/me/working-hours/${block.id}`, { token: staff, body: { start_time: '12:30', end_time: '14:00' } });
    const ok = await call('PUT', `/me/working-hours/${block.id}`, { token: staff, body: { start_time: '13:00', end_time: '13:45' } });
    const foreign = await call('PUT', `/me/working-hours/${other49[0]}`, { token: staff, body: { start_time: '07:00', end_time: '08:00' } });
    return { ok: bad.status === 409 && ok.status === 200 && ok.json.data.block.end === '13:45' && foreign.status === 404, detail: `${bad.status}/${ok.status}/${foreign.status}` };
  });
  await t('ME-10 delete blocks: the LAST block turns the day OFF, adding a block turns it ON again', async () => {
    const week = (await call('GET', '/me/working-hours', { token: staff })).json.data.days;
    const d = week[6];
    let lastResp;
    for (const b of d.blocks) lastResp = await call('DELETE', `/me/working-hours/${b.id}`, { token: staff });
    const off = Number(one(`select is_day_off from tbl_slots where id=${d.slot_id}`));
    const add = await call('POST', '/me/working-hours', { token: staff, body: { day_id: d.slot_id, start_time: '09:00', end_time: '12:00' } });
    const on = Number(one(`select is_day_off from tbl_slots where id=${d.slot_id}`));
    const foreign = await call('DELETE', `/me/working-hours/${other49[0]}`, { token: staff });
    return { ok: lastResp.json.data.is_day_off === true && off === 1 && add.status === 201 && on === 0 && foreign.status === 404 && Number(one(`select count(*) from tbl_breaks where id=${other49[0]}`)) === 1, detail: `after last delete off=${off}, after add off=${on}, foreign delete ${foreign.status}` };
  });
  await t('ME-11 day-off toggle: on/off, other barber\'s day → 404, bad value → 422', async () => {
    const d = (await call('GET', '/me/working-hours', { token: staff })).json.data.days[2];
    const on = await call('PUT', `/me/working-hours/days/${d.slot_id}/day-off`, { token: staff, body: { off: true } });
    const flag1 = Number(one(`select is_day_off from tbl_slots where id=${d.slot_id}`));
    const offAgain = await call('PUT', `/me/working-hours/days/${d.slot_id}/day-off`, { token: staff, body: { off: false } });
    const flag2 = Number(one(`select is_day_off from tbl_slots where id=${d.slot_id}`));
    const foreign = await call('PUT', `/me/working-hours/days/${other49[1]}/day-off`, { token: staff, body: { off: true } });
    const bad = await call('PUT', `/me/working-hours/days/${d.slot_id}/day-off`, { token: staff, body: { off: 'maybe' } });
    return { ok: on.status === 200 && flag1 === 1 && offAgain.status === 200 && flag2 === 0 && foreign.status === 404 && bad.status === 422, detail: `${on.status}/${offAgain.status}/${foreign.status}/${bad.status}` };
  });
  await t('WRITE PARITY working hours: web and API reject/accept the same, with the web\'s message', async () => {
    const week = (await call('GET', '/me/working-hours', { token: staff })).json.data.days;
    const dayW = week[3], dayA = week[4];
    const wOver = await (await staffWeb.req('POST', '/admin/working-hour', { form: { day_id: dayW.slot_id, start_time: '10:00', end_time: '11:00' } })).json();
    const aOver = await call('POST', '/me/working-hours', { token: staff, body: { day_id: dayA.slot_id, start_time: '10:00', end_time: '11:00' } });
    const wOk = await (await staffWeb.req('POST', '/admin/working-hour', { form: { day_id: dayW.slot_id, start_time: '19:00', end_time: '20:00' } })).json();
    const aOk = await call('POST', '/me/working-hours', { token: staff, body: { day_id: dayA.slot_id, start_time: '19:00', end_time: '20:00' } });
    const shape = (id) => rows(`select break_start,break_end,break_type,staff_id from tbl_breaks where slot_id=${id} and break_start='19:00:00'`)[0]?.join('|');
    return { ok: wOver.status === 0 && aOver.status === 409 && wOver.message === aOver.json.message && wOk.status === 1 && aOk.status === 201 && shape(dayW.slot_id) === shape(dayA.slot_id), detail: `web msg "${wOver.message}" | api msg "${aOver.json.message}" | rows ${shape(dayW.slot_id)} vs ${shape(dayA.slot_id)}` };
  });

  // ======================================================== permissions
  await t('a user without roles: 403 on calendar, slots, create, working hours; profile still works', async () => {
    const saved = one('select role_id from model_has_roles where model_id=51');
    const adminId = one(`select id from users where email='${adminEmail}'`);
    sql('delete from model_has_roles where model_id=51');
    try {
      const tok = await login(staffEmail, staffPw, 'norole2');
      const sts = [];
      sts.push((await call('GET', `/calendar/events?from=${today}&to=${today}`, { token: tok })).status);
      sts.push((await call('GET', `/appointments/slots?date=${D3}&staff_ids=51&service_ids=25`, { token: tok })).status);
      sts.push((await call('POST', '/appointments', { token: tok, body: mk() })).status);
      sts.push((await call('GET', '/me/working-hours', { token: tok })).status);
      sts.push((await call('POST', '/appointments/1/reschedule', { token: tok, body: { date: D3, slot_start: '10:00', slot_end: '10:30' } })).status);
      const profile = (await call('GET', '/me/profile', { token: tok })).status;
      return { ok: sts.every((s) => s === 403) && profile === 200, detail: `${sts.join('/')} profile ${profile}` };
    } finally {
      if (saved) sql(`insert into model_has_roles (role_id, model_type, model_id) select ${saved}, model_type, 51 from model_has_roles where model_id=${adminId} limit 1`);
    }
  });
  await t('calendar events: range required, > 62 days → 422; staff user is limited to their own lane even if they ask for another', async () => {
    const none = await call('GET', '/calendar/events', { token: admin });
    const big = await call('GET', `/calendar/events?from=${ed(0)}&to=${ed(100)}`, { token: admin });
    const r = await call('GET', `/calendar/events?from=${ed(-1)}&to=${ed(8)}&staff_id=49`, { token: staff });
    const foreign = r.json.data.events.filter((e) => e.resource_id !== '51');
    return { ok: none.status === 422 && big.status === 422 && r.status === 200 && foreign.length === 0 && r.json.data.lanes.length === 1, detail: `${none.status}/${big.status}, foreign events ${foreign.length}` };
  });

  const w = Math.max(...results.map((r) => r.name.length));
  console.log('\nPhase 2 behaviour + write-parity tests\n');
  for (const r of results) console.log((r.ok ? '  PASS ' : '  FAIL ') + r.name.padEnd(w) + (r.detail ? '  ' + r.detail : ''));
  const failed = results.filter((r) => !r.ok).length;
  console.log(`\n${results.length - failed}/${results.length} passed` + (failed ? `, ${failed} FAILED` : ''));
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });

function statusOfAppt(id) { return Number(one(`select status from tbl_appointment where appointment_id=${id}`)); }
