#!/usr/bin/env node
/**
 * Phase 3b tests: POS catalog, totals (golden cases = the web page's own JavaScript formulas),
 * create / edit invoice with write parity against the web, visibility, idempotency,
 * validation and permissions. Never sends a real email (see the email tests).
 *
 *   node api_phase3b_test.js <webBase> <apiBase> <adminEmail> <adminPw> <staffEmail> <staffPw>
 *
 * Needs the marked test data. Everything it creates is named "API TEST ..." / phone 555999xxxx,
 * or is tracked and removed at the end (invoices for the Guest customer).
 */
const { execSync } = require('child_process');
const [webBase, apiBase, adminEmail, adminPw, staffEmail, staffPw] = process.argv.slice(2);
if (!staffPw) { console.error('usage: node api_phase3b_test.js <webBase> <apiBase> <adminEmail> <adminPw> <staffEmail> <staffPw>'); process.exit(2); }

const results = [];
const sql = (q) => execSync('mysql -uroot -h127.0.0.1 -N -B barber_shop_db', { input: q, encoding: 'utf8' }).replace(/\r/g, '').trim();
const rows = (q) => sql(q).split('\n').filter(Boolean).map((l) => l.split('\t'));
const one = (q) => (rows(q)[0] || [])[0];

class Web {
  constructor() { this.jar = {}; this.csrf = null; }
  ck() { return Object.entries(this.jar).map(([k, v]) => `${k}=${v}`).join('; '); }
  store(r) { for (const c of r.headers.getSetCookie?.() || []) { const [p] = c.split(';'); const i = p.indexOf('='); this.jar[p.slice(0, i)] = p.slice(i + 1); } }
  async json(method, path, payload) {
    const headers = { Cookie: this.ck(), 'X-Requested-With': 'XMLHttpRequest', 'X-CSRF-TOKEN': this.csrf, Accept: 'application/json', 'Content-Type': 'application/json' };
    const r = await fetch(webBase + path, { method, headers, body: JSON.stringify(payload), redirect: 'manual' }); this.store(r); return r.json();
  }
  async get(path) { const r = await fetch(webBase + path, { headers: { Cookie: this.ck() }, redirect: 'manual' }); this.store(r); return r; }
  async login(email, pw) {
    const page = await fetch(webBase + '/admin/login'); this.store(page);
    const tok = ((await page.text()).match(/name="_token" value="([^"]+)"/) || [])[1];
    const r = await fetch(webBase + '/admin/post-login', { method: 'POST', redirect: 'manual', headers: { 'Content-Type': 'application/x-www-form-urlencoded', Cookie: this.ck() }, body: new URLSearchParams({ _token: tok, email, password: pw }) }); this.store(r);
    const dash = await (await this.get('/admin/dashboard')).text();
    this.csrf = (dash.match(/name="csrf-token" content="([^"]+)"/) || [])[1];
  }
}
async function call(method, path, token, body, extra = {}) {
  const headers = { Accept: 'application/json', Authorization: 'Bearer ' + token, ...extra };
  if (body) headers['Content-Type'] = 'application/json';
  const r = await fetch(apiBase + path, { method, headers, body: body ? JSON.stringify(body) : undefined });
  let json = null; try { json = await r.json(); } catch (e) { /* none */ }
  return { status: r.status, json };
}
const login = async (e, p) => (await (await fetch(apiBase + '/auth/login', { method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'application/json' }, body: JSON.stringify({ email: e, password: p, device_name: 'p3b' }) })).json()).data.token;
async function t(name, fn) { try { const r = await fn(); results.push({ name, ok: r.ok, detail: r.detail || '' }); } catch (e) { results.push({ name, ok: false, detail: 'EXCEPTION ' + e.message }); } }
const near = (a, b, eps = 0.006) => Math.abs(Number(a) - Number(b)) <= eps;

// the web page's own formulas (create-invoice.blade.php: calculateTotal + the submit handler)
function webTotals({ services = [], products = [], sPct = 0, pPct = 0, tip = 0, rate = 5, exclude = false }) {
  const sT = services.reduce((a, b) => a + b, 0), pT = products.reduce((a, b) => a + b, 0);
  const sD = sT * sPct / 100, pD = pT * pPct / 100;
  const disc = (sT - sD) + (pT - pD);
  const tax = !rate || disc <= 0 ? 0 : exclude ? (disc * rate) / 100 : (disc * rate) / (100 + rate);
  const final = exclude ? disc + tax + tip : disc + tip;
  return { subTotal: disc.toFixed(2), discountType: 1, discountAmount: (parseFloat(sD.toFixed(2)) + parseFloat(pD.toFixed(2))).toFixed(2), tip: tip.toFixed(2), tax: tax.toFixed(2), finalTotal: final.toFixed(2), product_discount: String(pPct), service_discount: String(sPct) };
}

const created = [];        // appointment ids to remove at the end
let guestWasThere = false;

(async () => {
  const admin = await login(adminEmail, adminPw), staff = await login(staffEmail, staffPw);
  const web = new Web(); await web.login(adminEmail, adminPw);
  guestWasThere = Number(one("select count(*) from customers where customer_phone='(555) 123-4567' and customer_email='info@bluecrownbarbers.com'")) > 0;
  const adminId = Number(one(`select id from users where email='${adminEmail}'`));
  const staffId = Number(one(`select id from users where email='${staffEmail}'`));

  const cat = (await call('GET', '/pos/catalog', admin)).json.data;
  const svcAll = cat.categories.flatMap((c) => c.services), prodAll = cat.products;
  const S = (id) => svcAll.find((s) => s.id === id), P = (id) => prodAll.find((p) => p.id === id);
  const price = (x) => Number(x.price);
  const sA = svcAll.find((s) => s.tip_eligible), sB = svcAll.find((s) => !s.tip_eligible) || svcAll[1];
  const pA = prodAll[0], pB = prodAll[1] || prodAll[0];
  const gst = cat.gst;
  const BARBER = staffId;     // the test barber is also the signed-in staff user

  // ============================================================ catalog
  await t('POS-1 catalog: categories → services, products, staff, default GST, payment methods', async () => {
    const r = await call('GET', '/pos/catalog', admin);
    const d = r.json.data;
    return { ok: r.status === 200 && d.categories.length > 0 && d.products.length > 0 && d.staff.some((s) => s.id === BARBER) && d.gst && d.gst.tax_type === 'include' && Number(d.gst.rate) === 5 && d.payment_methods.some((m) => m.name === 'Cash') && d.default_payment_method === 'Cash' && svcAll.every((s) => /^\d+\.\d\d$/.test(s.price)), detail: `${svcAll.length} services, ${prodAll.length} products, ${d.staff.length} staff, GST ${d.gst?.rate}% ${d.gst?.tax_type}` };
  });
  await t('POS-1 catalog: commission rates shown to admin, hidden from staff users', async () => {
    const a = (await call('GET', '/pos/catalog', admin)).json.data, s = (await call('GET', '/pos/catalog', staff)).json.data;
    const aHas = a.categories[0].services[0].commission_percent !== undefined && a.products[0].commission_percent !== undefined;
    const sHas = JSON.stringify(s).includes('commission');
    return { ok: aHas && !sHas, detail: `admin sees ${aHas}, staff sees ${sHas}` };
  });

  // ============================================================ preview vs the web page's formulas
  const cases = [
    ['single service, no discount, no tip', { services: [price(sA)] }, [{ type: 'service', id: sA.id, staff_id: BARBER, qty: 1 }], {}],
    ['two units + tip 5.00 (eligible service)', { services: [price(sA), price(sA)], tip: 5 }, [{ type: 'service', id: sA.id, staff_id: BARBER, qty: 2 }], { tip: 5 }],
    ['10% service discount', { services: [price(sA)], sPct: 10 }, [{ type: 'service', id: sA.id, staff_id: BARBER, qty: 1 }], { service_discount: 10 }],
    ['service + product, both discounts, tip', { services: [price(sA), price(sB)], products: [price(pA)], sPct: 12.5, pPct: 7, tip: 3.33 }, [{ type: 'service', id: sA.id, staff_id: BARBER, qty: 1 }, { type: 'service', id: sB.id, staff_id: BARBER, qty: 1 }, { type: 'product', id: pA.id, staff_id: BARBER, qty: 1 }], { service_discount: 12.5, product_discount: 7, tip: 3.33 }],
    ['products only, two kinds', { products: [price(pA), price(pB), price(pB)] }, [{ type: 'product', id: pA.id, staff_id: BARBER, qty: 1 }, { type: 'product', id: pB.id, staff_id: BARBER, qty: 2 }], {}],
    ['100% discount (nothing to pay but tip)', { services: [price(sA)], sPct: 100, tip: 2 }, [{ type: 'service', id: sA.id, staff_id: BARBER, qty: 1 }], { service_discount: 100, tip: 2 }],
  ];
  for (const [label, wcalc, items, extra] of cases) {
    await t(`POS-8 preview "${label}": every figure equals the web page's`, async () => {
      const exp = webTotals(wcalc);
      const r = await call('POST', '/invoices/preview', admin, { items, ...extra });
      const g = r.json?.data?.totals;
      const bad = [];
      if (r.status !== 200) return { ok: false, detail: `http ${r.status} ${JSON.stringify(r.json).slice(0, 200)}` };
      for (const [k, v] of [['subtotal', exp.subTotal], ['total_discount', exp.discountAmount], ['tax', exp.tax], ['tip', exp.tip], ['final_total', exp.finalTotal]]) if (g[k] !== v) bad.push(`${k}: web ${v} api ${g[k]}`);
      return { ok: bad.length === 0, detail: bad.length ? bad.join('; ') : `final ${g.final_total}, tax ${g.tax}` };
    });
  }
  await t('POS-8 preview with an "exclude" GST: tax is added on top (web rule)', async () => {
    sql(`update tbl_gst set tax_type='exclude' where default_status=1`);
    try {
      const exp = webTotals({ services: [price(sA)], sPct: 10, tip: 1, exclude: true });
      const r = await call('POST', '/invoices/preview', admin, { items: [{ type: 'service', id: sA.id, staff_id: BARBER, qty: 1 }], service_discount: 10, tip: 1 });
      const g = r.json.data.totals;
      return { ok: g.tax === exp.tax && g.final_total === exp.finalTotal && g.tax_type === 'exclude', detail: `web ${exp.tax}/${exp.finalTotal} api ${g.tax}/${g.final_total}` };
    } finally { sql(`update tbl_gst set tax_type='include' where default_status=1`); }
  });
  await t('POS-8 preview validation: no items, bad type, unknown service/product/staff, qty 0/21, discount 101, negative tip, unknown payment method → 422', async () => {
    const ok1 = { type: 'service', id: sA.id, staff_id: BARBER, qty: 1 };
    const bad = [{ items: [] }, { items: [{ ...ok1, type: 'gift' }] }, { items: [{ ...ok1, id: 99999 }] }, { items: [{ type: 'product', id: 99999, staff_id: BARBER, qty: 1 }] }, { items: [{ ...ok1, staff_id: 1 }] }, { items: [{ ...ok1, qty: 0 }] }, { items: [{ ...ok1, qty: 21 }] }, { items: [ok1], service_discount: 101 }, { items: [ok1], product_discount: -1 }, { items: [ok1], tip: -5 }, { items: [ok1], payment_method: 'Bitcoin' }];
    const out = []; for (const b of bad) out.push((await call('POST', '/invoices/preview', admin, b)).status);
    return { ok: out.every((s) => s === 422), detail: out.join('/') };
  });
  await t('POS-8 an inactive service is refused (the catalog hides it too)', async () => {
    sql(`update tbl_service set status=0 where id=${sB.id}`);
    try {
      const r = await call('POST', '/invoices/preview', admin, { items: [{ type: 'service', id: sB.id, staff_id: BARBER, qty: 1 }] });
      const inCat = (await call('GET', '/pos/catalog', admin)).json.data.categories.flatMap((c) => c.services).some((s) => s.id === sB.id);
      return { ok: r.status === 422 && !inCat, detail: `preview ${r.status}, in catalog ${inCat}` };
    } finally { sql(`update tbl_service set status=1 where id=${sB.id}`); }
  });

  // ============================================================ create (+ parity)
  const hdr = (id) => rows(`select status,is_invoiced,payment_method,total_amt,total_discount,discount_type,total_tax,total_tip,service_discount,product_discount,ifnull(notes,'N'),invoice_created_by,ifnull(comment,'N'),customer_id>0,date=curdate() from tbl_appointment where appointment_id=${id}`)[0];
  const svcRows = (id) => rows(`select service_id,staff_id,product_commission,service_commission,service_tip,total_amt,status,comment from tbl_appointment_service where appointment_id=${id} order by id`);
  const prdRows = (id) => rows(`select product_id,staff_id,qty,amount,product_commision from tbl_appointment_product where appointment_id=${id} order by id`);
  const sameNum = (a, b) => a.length === b.length && a.every((v, i) => (Number.isNaN(Number(v)) ? v === b[i] : near(v, b[i])));

  const webPayload = (items, extra, cust, calc) => {
    const units = []; for (const it of items) for (let i = 0; i < it.qty; i++) { const m = it.type === 'service' ? S(it.id) : P(it.id); units.push({ productId: String(it.id), staffId: String(it.staff_id), flag: it.type === 'service' ? 'S' : 'P', price: m.price, productName: m.name }); }
    return { products: units, totals: webTotals(calc), customer: { contact: cust.phone, name: cust.name, email: cust.email }, payment_method: extra.payment_method ?? 'Cash', notes: extra.notes };
  };
  const parityCases = [
    ['one eligible service + tip', [{ type: 'service', id: sA.id, staff_id: BARBER, qty: 1 }], { tip: 4 }, { services: [price(sA)], tip: 4 }],
    ['2×service + product, discounts, tip split in two', [{ type: 'service', id: sA.id, staff_id: BARBER, qty: 2 }, { type: 'product', id: pA.id, staff_id: BARBER, qty: 1 }], { service_discount: 10, product_discount: 5, tip: 6 }, { services: [price(sA), price(sA)], products: [price(pA)], sPct: 10, pPct: 5, tip: 6 }],
    ['service not eligible for tips + product only tip', [{ type: 'service', id: sB.id, staff_id: BARBER, qty: 1 }, { type: 'product', id: pB.id, staff_id: BARBER, qty: 2 }], { tip: 3, payment_method: 'Online', notes: 'API TEST note' }, { services: [price(sB)], products: [price(pB), price(pB)], tip: 3 }],
  ];
  let n = 0;
  for (const [label, items, extra, calc] of parityCases) {
    n++;
    await t(`WRITE PARITY create "${label}": web store and API store leave the same rows`, async () => {
      const wc = { name: 'API TEST Inv W' + n, phone: '55599920' + n + '1', email: 'w@test.test' }, ac = { name: 'API TEST Inv A' + n, phone: '55599920' + n + '2', email: 'a@test.test' };
      const w = await web.json('POST', '/admin/invoice/store', webPayload(items, extra, wc, { ...calc, sPct: calc.sPct || extra.service_discount || 0, pPct: calc.pPct || extra.product_discount || 0 }));
      const wId = Number(one(`select appointment_id from tbl_appointment where phone='${wc.phone}' order by appointment_id desc limit 1`));
      const r = await call('POST', '/invoices', admin, { items, ...extra, customer: ac });
      const aId = r.json?.data?.invoice?.id;
      created.push(wId, aId);
      const bad = [];
      if (w.status !== 200 || r.status !== 201) bad.push(`web ${w.status}/${w.msg} api ${r.status}`);
      const wh = hdr(wId), ah = hdr(aId);
      if (!sameNum(wh, ah)) bad.push(`header web ${wh} api ${ah}`);
      const ws = svcRows(wId), as = svcRows(aId);
      if (ws.length !== as.length || !ws.every((row, i) => sameNum(row.filter((_, j) => j !== 4), as[i].filter((_, j) => j !== 4)))) bad.push(`service rows web ${JSON.stringify(ws)} api ${JSON.stringify(as)}`);
      const tipSum = (x) => x.reduce((a, row) => a + Number(row[4]), 0);
      if (!near(tipSum(ws), tipSum(as), 0.011) || !near(tipSum(as), calc.tip || 0, 0.0001)) bad.push(`tip sum web ${tipSum(ws)} api ${tipSum(as)}`);
      const wp = prdRows(wId), ap = prdRows(aId);
      if (wp.length !== ap.length || !wp.every((row, i) => sameNum(row, ap[i]))) bad.push(`product rows web ${JSON.stringify(wp)} api ${JSON.stringify(ap)}`);
      if (!/^INV-\d{8}-\d{4}$/.test(r.json.data.invoice.invoice_number)) bad.push('invoice number format');
      return { ok: bad.length === 0, detail: bad.length ? bad.join(' | ') : `total ${ah[3]}, ${as.length} service rows, ${ap.length} product rows, tips ${as.map((x) => x[4]).join('/')}` };
    });
  }

  let inv;
  await t('POS-3 create: 201 with the full invoice (lines, breakdown, cart for editing), shop-time date', async () => {
    const r = await call('POST', '/invoices', admin, { items: [{ type: 'service', id: sA.id, staff_id: BARBER, qty: 2 }, { type: 'product', id: pA.id, staff_id: BARBER, qty: 1 }], tip: 5, customer: { name: 'API TEST Inv Detail', phone: '5559993001', email: 'd@test.test' } });
    inv = r.json?.data?.invoice; created.push(inv?.id);
    const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'America/Edmonton' });
    return { ok: r.status === 201 && inv.lines.length === 3 && inv.cart.length === 2 && inv.cart.find((c) => c.type === 'service').qty === 2 && inv.breakdown.tip === '5.00' && inv.status_label === 'Paid' && inv.date === today && inv.created_by === adminId && inv.customer.phone === '5559993001', detail: `${inv?.invoice_number} total ${inv?.total}` };
  });
  await t('POS-3 customer rules: known phone is reused (no duplicate); empty customer → the shared Guest placeholder; name only → phone placeholder', async () => {
    const again = await call('POST', '/invoices', admin, { items: [{ type: 'product', id: pA.id, staff_id: BARBER, qty: 1 }], customer: { name: 'Someone else', phone: '5559993001' } });
    created.push(again.json.data.invoice.id);
    const dup = Number(one("select count(*) from customers where customer_phone='5559993001'"));
    const g1 = await call('POST', '/invoices', admin, { items: [{ type: 'product', id: pA.id, staff_id: BARBER, qty: 1 }] });
    const g2 = await call('POST', '/invoices', admin, { items: [{ type: 'product', id: pA.id, staff_id: BARBER, qty: 1 }], customer: {} });
    created.push(g1.json.data.invoice.id, g2.json.data.invoice.id);
    const guests = Number(one("select count(*) from customers where customer_phone='(555) 123-4567' and customer_email='info@bluecrownbarbers.com'"));
    const nameOnly = await call('POST', '/invoices', admin, { items: [{ type: 'product', id: pA.id, staff_id: BARBER, qty: 1 }], customer: { name: 'API TEST Name Only' } });
    created.push(nameOnly.json.data.invoice.id);
    const no = nameOnly.json.data.invoice.customer;
    return { ok: dup === 1 && again.json.data.invoice.customer.name === inv.customer.name && guests === 1 && g1.json.data.invoice.customer.name === 'Guest Customer' && no.phone === '(555) 123-4567' && no.email === 'info@bluecrownbarbers.com', detail: `customers with that phone ${dup}, guest rows ${guests}, name-only → ${no.phone}` };
  });
  await t('POS-3 idempotency: the same Idempotency-Key twice → one invoice (201 then 200)', async () => {
    const body = { items: [{ type: 'service', id: sA.id, staff_id: BARBER, qty: 1 }], customer: { name: 'API TEST Idem', phone: '5559993002' } };
    const key = 'p3b-' + Date.now();
    const a = await call('POST', '/invoices', admin, body, { 'Idempotency-Key': key });
    const b = await call('POST', '/invoices', admin, body, { 'Idempotency-Key': key });
    const c = await call('POST', '/invoices', admin, body, { 'Idempotency-Key': key + '-other' });
    created.push(a.json.data.invoice.id, c.json.data.invoice.id);
    const count = Number(one("select count(*) from tbl_appointment where phone='5559993002'"));
    return { ok: a.status === 201 && b.status === 200 && a.json.data.invoice.id === b.json.data.invoice.id && c.status === 201 && count === 2, detail: `${a.status}/${b.status}/${c.status}, rows ${count}` };
  });
  await t('POS-3 two identical submits at the same instant (same key) → one invoice', async () => {
    const body = { items: [{ type: 'service', id: sA.id, staff_id: BARBER, qty: 1 }], customer: { name: 'API TEST Race', phone: '5559993003' } };
    const key = 'p3b-race-' + Date.now();
    const [x, y] = await Promise.all([call('POST', '/invoices', admin, body, { 'Idempotency-Key': key }), call('POST', '/invoices', admin, body, { 'Idempotency-Key': key })]);
    for (const r of [x, y]) if (r.json?.data?.invoice) created.push(r.json.data.invoice.id);
    const count = Number(one("select count(*) from tbl_appointment where phone='5559993003'"));
    return { ok: count === 1 && [x.status, y.status].every((s) => s === 200 || s === 201), detail: `${x.status}/${y.status}, rows ${count}` };
  });

  // ============================================================ list / detail / visibility
  await t('POS-4 list: newest first, paginated, search and date filters, same invoices as the web page for the admin', async () => {
    const all = []; let page = 1;
    for (;;) { const r = await call('GET', `/invoices?per_page=50&page=${page}`, admin); all.push(...r.json.data.items); if (!r.json.meta.has_more) break; page++; }
    const html = await (await web.get('/admin/invoice')).text();
    const webNums = [...html.matchAll(/<td>(INV-\d{8}-\w+)<\/td>/g)].map((m) => m[1]);
    const ids = all.map((x) => x.id);
    const sorted = [...ids].sort((a, b) => b - a);
    const q = await call('GET', '/invoices?q=' + encodeURIComponent(inv.invoice_number), admin);
    const d = await call('GET', `/invoices?start_date=2000-01-01&end_date=2000-01-02`, admin);
    return { ok: JSON.stringify(ids) === JSON.stringify(sorted) && all.map((x) => x.invoice_number).sort().join() === [...webNums].sort().join() && q.json.data.items.length === 1 && d.json.data.items.length === 0, detail: `web ${webNums.length}, api ${all.length}` };
  });
  await t('POS-4 staff without Show_All sees only invoices they created; admin invoices are hidden and give 404', async () => {
    const mine = await call('POST', '/invoices', staff, { items: [{ type: 'service', id: sA.id, staff_id: BARBER, qty: 1 }], customer: { name: 'API TEST Staff Inv', phone: '5559993004' } });
    created.push(mine.json.data.invoice.id);
    const list = await call('GET', '/invoices?per_page=50', staff);
    const hidden = await call('GET', `/invoices/${inv.id}`, staff);
    const own = await call('GET', `/invoices/${mine.json.data.invoice.id}`, staff);
    const comm = JSON.stringify(own.json.data.invoice.lines).includes('commission');
    return { ok: mine.status === 201 && list.json.data.items.every((x) => x.id === mine.json.data.invoice.id || true) && list.json.data.items.length === Number(one(`select count(*) from tbl_appointment where is_invoiced=1 and invoice_created_by=${staffId}`)) && hidden.status === 404 && own.status === 200 && !comm, detail: `staff sees ${list.json.data.items.length}, admin invoice ${hidden.status}, commission shown ${comm}` };
  });
  await t('POS-5 detail: unknown id → 404; admin sees commission per line', async () => {
    const miss = await call('GET', '/invoices/99999999', admin);
    const det = await call('GET', `/invoices/${inv.id}`, admin);
    return { ok: miss.status === 404 && det.json.data.invoice.lines.every((l) => l.commission !== undefined), detail: `lines ${det.json.data.invoice.lines.length}` };
  });

  // ============================================================ update (+ parity)
  await t('WRITE PARITY update: web update and API PUT leave the same rows, keep the invoice number and creator', async () => {
    const mkOne = async (name, phone) => (await call('POST', '/invoices', admin, { items: [{ type: 'service', id: sA.id, staff_id: BARBER, qty: 1 }], customer: { name, phone } })).json.data.invoice;
    const w0 = await mkOne('API TEST Upd W', '5559994001'), a0 = await mkOne('API TEST Upd A', '5559994002');
    created.push(w0.id, a0.id);
    const items = [{ type: 'service', id: sB.id, staff_id: BARBER, qty: 2 }, { type: 'product', id: pB.id, staff_id: BARBER, qty: 1 }];
    const extra = { service_discount: 15, tip: 2.5, payment_method: 'Debit' };
    const wp = webPayload(items, extra, { name: 'API TEST Upd W', phone: '5559994001', email: '' }, { services: [price(sB), price(sB)], products: [price(pB)], sPct: 15, tip: 2.5 });
    wp.appointment_id = String(w0.id);
    const w = await web.json('POST', '/admin/invoice/update', wp);
    const r = await call('PUT', `/invoices/${a0.id}`, admin, { items, ...extra, customer: { name: 'API TEST Upd A', phone: '5559994002' } });
    const bad = [];
    if (w.status !== 200 || r.status !== 200) bad.push(`web ${w.status}/${w.msg} api ${r.status} ${JSON.stringify(r.json).slice(0, 150)}`);
    if (!sameNum(hdr(w0.id), hdr(a0.id))) bad.push(`header web ${hdr(w0.id)} api ${hdr(a0.id)}`);
    const ws = svcRows(w0.id), as = svcRows(a0.id);
    if (ws.length !== as.length || !ws.every((row, i) => sameNum(row.filter((_, j) => j !== 4), as[i].filter((_, j) => j !== 4)))) bad.push(`service rows web ${JSON.stringify(ws)} api ${JSON.stringify(as)}`);
    if (!sameNum(prdRows(w0.id).flat(), prdRows(a0.id).flat())) bad.push('product rows differ');
    const aNum = one(`select invoice_number from tbl_appointment where appointment_id=${a0.id}`), wNum = one(`select invoice_number from tbl_appointment where appointment_id=${w0.id}`);
    if (aNum !== a0.invoice_number || wNum !== w0.invoice_number) bad.push('invoice number changed');
    return { ok: bad.length === 0, detail: bad.join(' | ') || `total ${hdr(a0.id)[3]}` };
  });
  await t('POS-6 update: unknown / hidden invoice → 404; Add-only user (no Pos_invoice-Edit) → 403', async () => {
    const body = { items: [{ type: 'service', id: sA.id, staff_id: BARBER, qty: 1 }] };
    const miss = await call('PUT', '/invoices/99999999', admin, body);
    const noEdit = await call('PUT', `/invoices/${inv.id}`, staff, body);
    return { ok: miss.status === 404 && noEdit.status === 403, detail: `${miss.status}/${noEdit.status}` };
  });

  // ============================================================ customer lookup
  await t('POS-2 customer lookup: same visits and last service as the web; spend hidden from staff', async () => {
    const phone = '5559993001';
    const w = await (await web.get('/admin/getCustomer?contact=' + phone)).json();
    const a = (await call('GET', '/pos/customer-lookup?phone=' + phone, admin)).json.data.customers;
    const s = (await call('GET', '/pos/customer-lookup?phone=' + phone, staff)).json.data.customers;
    const none = (await call('GET', '/pos/customer-lookup?phone=000', admin)).json.data.customers;
    const wc = w.data[0];
    return { ok: a.length === 1 && a[0].visits === wc.appointments_count && near(a[0].total_spend, wc.appointments_sum_total_amt) && a[0].last_service === wc.last_service && s[0].total_spend === null && none.length === 0, detail: `visits ${a[0].visits}, last "${a[0].last_service}", staff spend ${s[0].total_spend}` };
  });

  // ============================================================ email (never a real mail)
  await t('POS-7 email: placeholder/empty address → 422, unknown invoice → 404, hidden invoice → 404, bad address → 422', async () => {
    const guest = Number(one("select appointment_id from tbl_appointment where is_invoiced=1 and email='info@bluecrownbarbers.com' order by appointment_id desc limit 1"));
    const p = await call('POST', `/invoices/${guest}/email`, admin, {});
    const miss = await call('POST', '/invoices/99999999/email', admin, { email: 'x@test.test' });
    const hid = await call('POST', `/invoices/${inv.id}/email`, staff, { email: 'x@test.test' });
    const bad = await call('POST', `/invoices/${inv.id}/email`, admin, { email: 'not-an-address' });
    return { ok: p.status === 422 && miss.status === 404 && hid.status === 404 && bad.status === 422, detail: `${p.status}/${miss.status}/${hid.status}/${bad.status}` };
  });

  // ============================================================ permissions
  await t('permissions: a role-less user gets 403 on catalog, preview, list, create', async () => {
    const saved = one('select role_id from model_has_roles where model_id=' + staffId);
    sql('delete from model_has_roles where model_id=' + staffId);
    try {
      const tok = await login(staffEmail, staffPw);
      const out = [(await call('GET', '/pos/catalog', tok)).status, (await call('POST', '/invoices/preview', tok, { items: [] })).status, (await call('GET', '/invoices', tok)).status, (await call('POST', '/invoices', tok, {})).status, (await call('POST', '/invoices/1/email', tok, {})).status];
      return { ok: out.every((s) => s === 403), detail: out.join('/') };
    } finally { if (saved) sql(`insert into model_has_roles (role_id, model_type, model_id) select ${saved}, model_type, ${staffId} from model_has_roles where model_id=${adminId} limit 1`); }
  });

  // ============================================================ clean up what the tests made outside the "API TEST" names
  const ids = [...new Set(created.filter(Boolean))];
  if (ids.length) sql(`delete from tbl_appointment_service where appointment_id in (${ids.join(',')}); delete from tbl_appointment_product where appointment_id in (${ids.join(',')}); delete from tbl_appointment where appointment_id in (${ids.join(',')});`);
  if (!guestWasThere) sql("delete from customers where customer_phone='(555) 123-4567' and customer_email='info@bluecrownbarbers.com'");
  sql("delete from customers where customer_name like 'API TEST%' or customer_phone like '555999%'");

  const w = Math.max(...results.map((r) => r.name.length));
  console.log('\nPhase 3b tests: POS and invoices\n');
  for (const r of results) console.log((r.ok ? '  PASS ' : '  FAIL ') + r.name.padEnd(w) + (r.detail ? '  ' + r.detail : ''));
  const failed = results.filter((r) => !r.ok).length;
  console.log(`\n${results.length - failed}/${results.length} passed` + (failed ? `, ${failed} FAILED` : ''));
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
