const F = require('./fmt');
const M = require('./model');

const DEMO_USERS = [
  { name: 'أحمد', username: 'admin', pin: '1234' },
  { name: 'سارة', username: 'cashier', pin: '0000' },
];

/// Seeded PRNG so every reset produces the same dataset.
function rng(seed) {
  let s = seed >>> 0;
  const next = () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
  return { double: next, int: (n) => Math.floor(next() * n), bool: () => next() < 0.5 };
}

const shuffle = (arr, r) => {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = r.int(i + 1);
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
};

/// Builds a realistic, internally consistent dataset by replaying ~30 days of
/// operations through the engine (so balances, stock and drawer all agree).
class Seeder {
  constructor(db, engine) {
    this.db = db;
    this.engine = engine;
    this.r = rng(7);
    this.bySupplierCat = {};
  }

  ensureUsers() {
    for (const u of DEMO_USERS) {
      if ([...this.db.users.values()].some((x) => x.username === u.username)) continue;
      this.db.put('users', { id: this.db.id('u'), name: u.name, username: u.username });
      this.db.pins[u.username] = u.pin;
    }
    this.db.touchMeta();
  }

  run() {
    this.ensureUsers();
    const users = DEMO_USERS.map((d) => [...this.db.users.values()].find((u) => u.username === d.username));
    this.users = users;
    const prevUser = this.engine.user;
    const keepNeg = this.db.settings.allowNegativeStock;
    this.db.clearBusiness();
    this.db.settings.allowNegativeStock = false;
    const t0 = F.startOfDay(F.addDays(new Date(), -30));
    t0.setHours(8);
    this.engine.user = users[0];

    this._catalog(t0);
    this._parties(t0);
    this._history();
    this._finalTouches();

    this.db.settings.allowNegativeStock = keepNeg;
    this.engine.user = prevUser;
  }

  _catalog(at) {
    const cats = ['مشروبات', 'ألبان وأجبان', 'بقالة جافة', 'معلبات', 'منظفات', 'حلويات وسناكس', 'عناية شخصية'].map((n) => this.engine.addCategory(n));
    // name, category index, unit, cost, price, min, opening
    const items = [
      ['بيبسي 1 لتر', 0, 'زجاجة', 17, 22, 24, 120],
      ['كوكاكولا كانز 330 مل', 0, 'علبة', 9, 12, 24, 96],
      ['مياه معدنية 1.5 لتر', 0, 'زجاجة', 6, 8, 36, 200],
      ['عصير مانجو 1 لتر', 0, 'علبة', 28, 35, 12, 60],
      ['شاي العروسة 250 جم', 0, 'باكو', 38, 48, 15, 80],
      ['نسكافيه كلاسيك 50 جم', 0, 'علبة', 62, 78, 10, 30],
      ['لبن كامل الدسم 1 لتر', 1, 'علبة', 34, 40, 20, 90],
      ['جبنة فيتا 500 جم', 1, 'علبة', 42, 52, 12, 50],
      ['زبادي طبيعي', 1, 'علبة', 7, 9, 30, 120],
      ['زبدة 200 جم', 1, 'قطعة', 105, 125, 8, 18],
      ['أرز مصري 1 كجم', 2, 'كيلو', 30, 36, 25, 150],
      ['سكر أبيض 1 كجم', 2, 'كيلو', 28, 33, 25, 150],
      ['زيت عباد الشمس 1 لتر', 2, 'زجاجة', 70, 82, 15, 70],
      ['مكرونة 400 جم', 2, 'باكو', 13, 16, 30, 160],
      ['دقيق فاخر 1 كجم', 2, 'كيلو', 22, 27, 15, 60],
      ['عدس أصفر 1 كجم', 2, 'كيلو', 48, 58, 10, 40],
      ['تونة قطع 140 جم', 3, 'علبة', 42, 52, 15, 70],
      ['فول مدمس 400 جم', 3, 'علبة', 16, 20, 20, 90],
      ['صلصة طماطم 320 جم', 3, 'علبة', 18, 23, 15, 70],
      ['سردين بالزيت', 3, 'علبة', 25, 32, 10, 22],
      ['سائل أطباق 650 مل', 4, 'زجاجة', 33, 40, 10, 45],
      ['مسحوق غسيل أوتوماتيك 1 كجم', 4, 'باكو', 85, 105, 8, 35],
      ['كلور 1 لتر', 4, 'زجاجة', 22, 28, 10, 40],
      ['مناديل 10 باكو', 4, 'كرتونة', 55, 68, 6, 25],
      ['شيبس عائلي', 5, 'كيس', 9, 12, 30, 140],
      ['كرواسون محشو', 5, 'قطعة', 8, 10, 30, 120],
      ['بسكويت سادة', 5, 'باكو', 4, 5, 40, 200],
      ['شوكولاتة بالحليب', 5, 'قطعة', 22, 28, 15, 60],
      ['صابون 120 جم', 6, 'قطعة', 18, 23, 15, 60],
      ['شامبو 400 مل', 6, 'زجاجة', 95, 115, 6, 14],
      ['معجون أسنان 100 مل', 6, 'أنبوبة', 35, 43, 10, 40],
    ];
    for (const [name, cat, unit, cost, price, min, opening] of items) {
      const margin = price - cost;
      this.engine.createProduct(
        {
          name, barcode: '', sku: '', categoryId: cats[cat].id, unit, purchasePrice: cost, sellingPrice: price,
          wholesalePrice: Math.round(cost + margin * 0.4), halfWholesalePrice: Math.round(cost + margin * 0.7),
          minStock: min, openingStock: opening, description: '',
        },
        at,
      );
    }
  }

  _parties(at) {
    const customers = [
      ['محمد عبد الله', '01012345678', 'مدينة نصر - الحي السابع', 'retail', 3000],
      ['سوبر ماركت النور', '01123456789', 'شارع مكرم عبيد', 'wholesale', 30000],
      ['أحمد حسن', '01234567890', 'الحي العاشر', 'retail', 2000],
      ['كافيتريا الصفا', '01098765432', 'شارع الطيران', 'halfWholesale', 10000],
      ['منى إبراهيم', '01187654321', 'عمارات العبور', 'retail', 1500],
      ['مطعم أبو علي', '01276543210', 'شارع عباس العقاد', 'wholesale', 20000],
      ['محمود السيد', '01065432109', 'الحي الثامن', 'retail', 0],
      ['بقالة الأمل', '01154321098', 'المنطقة السادسة', 'halfWholesale', 8000],
      ['ياسر فتحي', '01243210987', 'زهراء مدينة نصر', 'retail', 2500],
      ['هالة مصطفى', '01032109876', 'شارع يوسف عباس', 'retail', 1000],
    ];
    for (const [name, phone, address, priceTier, creditLimit] of customers) {
      this.engine.createParty({ type: 'customer', name, phone, address, priceTier, creditLimit }, at);
    }
    const suppliers = [
      ['شركة النيل للتوزيع', 'النيل للتجارة والتوزيع', '0223456789', 'العبور - المنطقة الصناعية', [0, 3]],
      ['موزع الألبان المتحد', 'المتحدة للألبان', '0224567890', 'مدينة السادس من أكتوبر', [1]],
      ['مؤسسة الفجر للمواد الغذائية', 'الفجر للأغذية', '0225678901', 'روض الفرج', [2]],
      ['الشركة المصرية للمنظفات', 'المصرية للمنظفات', '0226789012', 'العاشر من رمضان', [4, 6]],
      ['مصنع الأمل للسناكس', 'الأمل للصناعات الغذائية', '0227890123', 'مدينة بدر', [5]],
    ];
    const catIds = [...this.db.categories.keys()];
    for (const [name, company, phone, address, cats] of suppliers) {
      const s = this.engine.createParty({ type: 'supplier', name, company, phone, address, creditLimit: 100000 }, at);
      for (const c of cats) this.bySupplierCat[catIds[c]] = s.id;
    }
    for (const p of this.db.products.values()) {
      p.supplierId = this.bySupplierCat[p.categoryId] || null;
      this.db.put('products', p);
    }
  }

  _history() {
    const r = this.r;
    const now = new Date();
    const parties = [...this.db.parties.values()];
    const customers = parties.filter(M.isCustomer).map((p) => p.id);
    const suppliers = parties.filter((p) => !M.isCustomer(p)).map((p) => p.id);
    const minutes = (d, m) => new Date(d.getTime() + m * 60000);

    for (let d = 30; d >= 0; d--) {
      const day = F.startOfDay(F.addDays(now, -d));
      const isToday = d === 0;
      const dayStart = minutes(day, 9 * 60);
      const dayEnd = isToday ? minutes(now, -3) : minutes(day, 21 * 60 + 30);
      const effStart = dayEnd > dayStart ? dayStart : day;
      const span = Math.min(Math.max(Math.floor((dayEnd - effStart) / 60000), 10), 1000);
      const at = () => minutes(effStart, 5 + r.int(span - 5));

      const events = [];
      if (d === 30) {
        events.push([minutes(effStart, 1), (t) => this.engine.addManualTx({ type: 'deposit', amount: 60000, account: 'bank', note: 'رأس مال - حساب البنك' }, t)]);
      }
      const salesCount = isToday ? 7 : 6 + r.int(8);
      for (let i = 0; i < salesCount; i++) events.push([at(), (t) => this._randomSale(t, customers)]);
      if (d % 4 === 2 || d === 29) events.push([at(), (t) => this._randomPurchase(t, suppliers)]);
      if (r.double() < 0.45) events.push([at(), (t) => this._customerPayment(t, customers)]);
      if (d % 5 === 1) events.push([at(), (t) => this._supplierPayment(t, suppliers)]);
      if (d % 6 === 3) events.push([at(), (t) => this._randomReturn(t)]);
      if (d % 9 === 4) events.push([at(), (t) => this._randomPurchaseReturn(t)]);
      events.push([at(), (t) => this._expense(t, 'ضيافة', 40 + r.int(120))]);
      if (d % 7 === 0) events.push([at(), (t) => this._expense(t, 'كهرباء ومياه', 650)]);
      if (d === 25) events.push([at(), (t) => this._expense(t, 'إيجار', 6000, true)]);
      if (d === 12) events.push([at(), (t) => this._expense(t, 'رواتب', 9000, true)]);
      if (d % 7 === 5) events.push([at(), (t) => this.engine.addManualTx({ type: 'withdrawal', amount: 2500, note: 'مسحوبات المالك' }, t)]);

      events.sort((a, b) => a[0] - b[0]);
      const openAt = minutes(events[0][0], -20);
      this.engine.user = this.users[0];
      this.engine.openSession(d === 30 ? 3000 : this.engine.lastClosedCash, openAt < day ? day : openAt);

      for (const [t, run] of events) {
        this.engine.user = this.users[r.int(10) < 6 ? 1 : 0];
        this._safely(() => run(t));
      }

      if (!isToday) {
        this.engine.user = this.users[0];
        const expected = this.engine.drawer(this.db.openSession).expected;
        const diff = r.int(10) === 0 ? -(r.int(4) * 5) : 0;
        this.engine.closeSession(expected + diff, diff === 0 ? '' : 'عجز بسيط', minutes(day, 22 * 60));
      }
    }
  }

  _safely(fn) {
    try {
      fn();
    } catch (_) {
      // Rule violations during random generation are simply skipped.
    }
  }

  _pickLines(tier, bulk) {
    const products = shuffle([...this.db.products.values()].filter((p) => p.stock > 3), this.r);
    const n = 1 + this.r.int(bulk ? 6 : 4);
    return products.slice(0, n).map((p) => {
      const q = Math.min(Math.max(1 + this.r.int(bulk ? 12 : 3), 1), p.stock - 1);
      return { productId: p.id, qty: q, unitPrice: M.priceFor(p, tier), discount: 0 };
    });
  }

  _randomSale(t, customers) {
    const r = this.r;
    const walkIn = r.double() < 0.55;
    const customer = walkIn ? null : this.db.parties.get(customers[r.int(customers.length)]);
    const tier = customer?.priceTier || 'retail';
    const lines = this._pickLines(tier, tier !== 'retail');
    if (!lines.length) return;
    const sub = lines.reduce((s, l) => s + M.lineTotal(l), 0);
    const discount = sub > 500 && r.bool() ? Math.round(sub * 0.02) : 0;
    const tot = sub - discount;
    let payments;
    const x = r.double();
    if (!customer) payments = [{ method: x < 0.8 ? 'cash' : 'card', amount: tot }];
    else if (x < 0.4) payments = [{ method: 'cash', amount: tot }];
    else if (x < 0.55) payments = [{ method: 'card', amount: tot }];
    else {
      const paid = Math.round(tot * (r.int(6) / 10));
      payments = paid > 0 ? [{ method: 'cash', amount: paid }] : [];
    }
    const draft = (pays) => ({ type: 'sale', partyId: customer?.id || null, priceTier: tier, lines: lines.map((l) => ({ ...l })), discount, payments: pays });
    try {
      this.engine.createInvoice(draft(payments), t);
    } catch (_) {
      // Likely credit limit: settle fully in cash instead.
      this._safely(() => this.engine.createInvoice(draft([{ method: 'cash', amount: tot }]), t));
    }
  }

  _randomPurchase(t, suppliers) {
    const r = this.r;
    const sid = suppliers[r.int(suppliers.length)];
    const products = shuffle([...this.db.products.values()].filter((p) => p.supplierId === sid), r);
    if (!products.length) return;
    const lines = products.slice(0, 2 + r.int(4)).map((p) => ({ productId: p.id, qty: (2 + r.int(5)) * 12, unitPrice: p.purchasePrice, discount: 0 }));
    const tot = lines.reduce((s, l) => s + M.lineTotal(l), 0);
    const x = r.double();
    const payments = x < 0.3 ? [{ method: 'bank', amount: tot }] : x < 0.75 ? [{ method: 'bank', amount: Math.round(tot * 0.4) }] : [];
    this.engine.createInvoice({ type: 'purchase', partyId: sid, lines, payments, supplierRef: `INV-${2000 + r.int(8000)}` }, t);
  }

  _customerPayment(t, customers) {
    const debtors = customers.map((id) => this.db.parties.get(id)).filter((p) => p.balance > 50);
    if (!debtors.length) return;
    const c = debtors[this.r.int(debtors.length)];
    const amount = Math.round((c.balance * (0.3 + this.r.double() * 0.7)) / 10) * 10;
    this.engine.addPayment({ partyId: c.id, amount: Math.min(Math.max(amount, 10), c.balance), method: this.r.bool() ? 'cash' : 'bank' }, t);
  }

  _supplierPayment(t, suppliers) {
    const creditors = suppliers.map((id) => this.db.parties.get(id)).filter((p) => p.balance > 100);
    if (!creditors.length) return;
    const s = creditors[this.r.int(creditors.length)];
    const amount = Math.round((s.balance * 0.5) / 100) * 100;
    if (amount <= 0) return;
    this.engine.addPayment({ partyId: s.id, amount, method: 'bank', note: 'دفعة تحت الحساب' }, t);
  }

  _randomReturn(t) {
    const c = [...this.db.invoices.values()].filter((i) => i.type === 'sale' && !M.hasReturns(i) && (t - i.date) / 86400000 < 5 && i.date < t);
    if (!c.length) return;
    const inv = c[this.r.int(c.length)];
    this.engine.createReturn({ invoiceId: inv.id, qtyByProduct: { [inv.lines[0].productId]: 1 }, reason: 'عيب في المنتج' }, t);
  }

  _randomPurchaseReturn(t) {
    const c = [...this.db.invoices.values()].filter((i) => i.type === 'purchase' && !M.hasReturns(i) && i.date < t);
    if (!c.length) return;
    const inv = c[c.length - 1];
    this.engine.createReturn({ invoiceId: inv.id, qtyByProduct: { [inv.lines[0].productId]: 6 }, reason: 'تالف عند الاستلام', refundMethod: 'bank' }, t);
  }

  _expense(t, category, amount, bank = false) {
    this._safely(() => this.engine.addManualTx({ type: 'expense', amount, category, account: bank ? 'bank' : 'cash' }, t));
  }

  _finalTouches() {
    // Make sure the demo shows low-stock and out-of-stock alerts.
    this.engine.user = this.users[0];
    const ago = new Date(Date.now() - 2 * 60000);
    const byName = Object.fromEntries([...this.db.products.values()].map((p) => [p.name, p]));
    const setTo = (name, q) => {
      const p = byName[name];
      if (p && Math.abs(p.stock - q) > 0.001) this.engine.adjustStock(p.id, q, 'count', 'جرد دوري', ago);
    };
    setTo('كوكاكولا كانز 330 مل', 0);
    setTo('شامبو 400 مل', 3);
    setTo('زبدة 200 جم', 5);
    setTo('سردين بالزيت', 6);
  }
}

module.exports = { Seeder, DEMO_USERS };
