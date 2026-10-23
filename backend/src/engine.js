const crypto = require('crypto');
const { BusinessError, NotFoundError, Codes } = require('./errors');
const F = require('./fmt');
const M = require('./model');

const EPS = 0.009;
const { r2 } = F;

/// The business rules of the POS. Each public method is one atomic operation:
/// validate everything first, then apply every side effect (stock, party
/// ledger, money movements), each carrying a reference.
class Engine {
  constructor(db) {
    this.db = db;
    this.user = null; // set per request
  }

  get _user() {
    return this.user?.name || 'النظام';
  }

  // ───────────────────────────── Users ─────────────────────────────

  // Accepts the username or the email.
  login(username, pin) {
    const key = String(username || '').trim().toLowerCase();
    const u = [...this.db.users.values()].find((x) => x.username === key || (x.email && x.email === key));
    if (!u || this.db.pins[u.username] !== pin) throw new BusinessError('اسم المستخدم أو كلمة المرور غير صحيحة');
    return { user: u, token: this._issueToken(u) };
  }

  register(name, username, pin, email) {
    const fullName = String(name || '').trim().replace(/\s+/g, ' ');
    const uname = String(username || '').trim().toLowerCase();
    const mail = String(email || '').trim().toLowerCase();
    const pass = String(pin || '');
    if (!/^[\p{L} ]{3,40}$/u.test(fullName)) throw new BusinessError('الاسم من 3 إلى 40 حرف (حروف فقط بدون أرقام أو رموز)');
    if (!/^[a-z][a-z0-9_.]{3,19}$/.test(uname)) throw new BusinessError('اسم المستخدم من 4 إلى 20 حرف، يبدأ بحرف إنجليزي (حروف وأرقام و _ . فقط)');
    if (!/^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$/.test(mail)) throw new BusinessError('البريد الإلكتروني غير صحيح');
    if (!/^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^A-Za-z0-9])\S{8,}$/.test(pass)) {
      throw new BusinessError('كلمة المرور 8 أحرف على الأقل وتحتوي على حرف كبير وحرف صغير ورقم ورمز');
    }
    const all = [...this.db.users.values()];
    if (all.some((x) => x.username === uname)) throw new BusinessError('اسم المستخدم مستخدم بالفعل');
    if (all.some((x) => x.email === mail)) throw new BusinessError('البريد الإلكتروني مستخدم بالفعل');
    const u = this.db.put('users', { id: this.db.id('u'), name: fullName, username: uname, email: mail });
    this.db.pins[uname] = pass;
    return { user: u, token: this._issueToken(u) };
  }

  _issueToken(u) {
    const token = crypto.randomBytes(24).toString('hex');
    this.db.tokens[token] = u.id;
    this.db.touchMeta();
    return token;
  }

  logout(token) {
    delete this.db.tokens[token];
    this.db.touchMeta();
  }

  userForToken(token) {
    const id = token && this.db.tokens[token];
    return id ? this.db.users.get(id) || null : null;
  }

  // ───────────────────────────── Catalog ─────────────────────────────

  addCategory(name) {
    const n = String(name || '').trim();
    if (!n) throw new BusinessError('اسم الفئة مطلوب');
    if ([...this.db.categories.values()].some((c) => c.name === n)) throw new BusinessError('الفئة موجودة بالفعل');
    return this.db.put('categories', { id: this.db.id('c'), name: n });
  }

  _validateProduct(i, excludeId) {
    if (!String(i.name || '').trim()) throw new BusinessError('اسم المنتج مطلوب');
    if (!this.db.categories.has(i.categoryId)) throw new BusinessError('اختر فئة المنتج');
    if (i.purchasePrice < 0 || !(i.sellingPrice > 0)) throw new BusinessError('أدخل سعر الشراء وسعر البيع بشكل صحيح');
    for (const p of this.db.products.values()) {
      if (p.id === excludeId) continue;
      if (i.barcode && p.barcode === i.barcode) throw new BusinessError(`الباركود مستخدم بالفعل للمنتج "${p.name}"`);
      if (i.sku && p.sku === i.sku) throw new BusinessError(`كود SKU مستخدم بالفعل للمنتج "${p.name}"`);
    }
  }

  createProduct(i, at) {
    this._validateProduct(i);
    if ((i.openingStock || 0) < 0) throw new BusinessError('الرصيد الافتتاحي لا يمكن أن يكون سالباً');
    const now = at || new Date();
    const p = this.db.put('products', {
      id: this.db.id('p'),
      name: i.name.trim(),
      barcode: i.barcode || this.generateBarcode(),
      sku: i.sku || this.generateSku(i.categoryId),
      categoryId: i.categoryId,
      unit: i.unit,
      purchasePrice: i.purchasePrice,
      sellingPrice: i.sellingPrice,
      wholesalePrice: i.wholesalePrice > 0 ? i.wholesalePrice : i.sellingPrice,
      halfWholesalePrice: i.halfWholesalePrice > 0 ? i.halfWholesalePrice : i.sellingPrice,
      stock: 0,
      minStock: i.minStock || 0,
      supplierId: i.supplierId || null,
      description: i.description || '',
      imagePath: i.imagePath || null,
      isActive: i.isActive !== false,
      createdAt: now,
    });
    if (i.openingStock > 0) this._moveStock(p.id, i.openingStock, 'opening', { at: now, note: 'رصيد أول المدة' });
    return this.db.products.get(p.id);
  }

  updateProduct(id, i) {
    const p = this._product(id);
    this._validateProduct(i, id);
    Object.assign(p, {
      name: i.name.trim(),
      barcode: i.barcode || p.barcode,
      sku: i.sku || p.sku,
      categoryId: i.categoryId,
      unit: i.unit,
      purchasePrice: i.purchasePrice,
      sellingPrice: i.sellingPrice,
      wholesalePrice: i.wholesalePrice > 0 ? i.wholesalePrice : i.sellingPrice,
      halfWholesalePrice: i.halfWholesalePrice > 0 ? i.halfWholesalePrice : i.sellingPrice,
      minStock: i.minStock || 0,
      supplierId: i.supplierId || null,
      description: i.description || '',
      imagePath: i.imagePath || null,
      isActive: i.isActive !== false,
    });
    return this.db.put('products', p);
  }

  deleteProduct(id) {
    this._product(id);
    const used =
      [...this.db.stockMoves.values()].some((m) => m.productId === id && m.type !== 'opening') ||
      [...this.db.invoices.values()].some((inv) => inv.lines.some((l) => l.productId === id));
    if (used) throw new BusinessError('لا يمكن حذف منتج له حركات بيع أو شراء. يمكنك إيقافه بدلاً من ذلك.', Codes.hasTransactions);
    this.db.remove('products', id);
    for (const m of [...this.db.stockMoves.values()]) if (m.productId === id) this.db.remove('stockMoves', m.id);
  }

  setActive(id, active) {
    const p = this._product(id);
    p.isActive = !!active;
    return this.db.put('products', p);
  }

  adjustStock(id, newStock, reason, note = '', at) {
    const p = this._product(id);
    if (newStock < 0) throw new BusinessError('الكمية لا يمكن أن تكون سالبة');
    const delta = newStock - p.stock;
    if (Math.abs(delta) < 0.0001) throw new BusinessError('الكمية الجديدة مساوية للرصيد الحالي');
    const label = M.ADJUST_REASON[reason] || reason;
    const ref = this.db.number('ADJ', { pad: 4 });
    this._moveStock(id, delta, 'adjustment', { at, refNumber: ref, note: note ? `${label} — ${note}` : label });
    return this.db.products.get(id);
  }

  generateBarcode() {
    for (;;) {
      let body = '622';
      for (let i = 0; i < 9; i++) body += Math.floor(Math.random() * 10);
      let sum = 0;
      for (let i = 0; i < 12; i++) sum += Number(body[i]) * (i % 2 === 0 ? 1 : 3);
      const code = body + ((10 - (sum % 10)) % 10);
      if (![...this.db.products.values()].some((p) => p.barcode === code)) return code;
    }
  }

  generateSku(categoryId) {
    const idx = [...this.db.categories.keys()].indexOf(categoryId) + 1;
    const prefix = `C${String(Math.min(Math.max(idx, 1), 99)).padStart(2, '0')}`;
    const products = [...this.db.products.values()];
    let n = products.filter((p) => p.sku.startsWith(prefix)).length + 1;
    for (;;) {
      const sku = `${prefix}-${String(n).padStart(4, '0')}`;
      if (!products.some((p) => p.sku === sku)) return sku;
      n++;
    }
  }

  _moveStock(productId, qty, type, { at, refId = null, refNumber = null, note = '' } = {}) {
    const p = this._product(productId);
    p.stock = p.stock + qty;
    this.db.put('products', p);
    this.db.put('stockMoves', {
      id: this.db.id('m'),
      productId,
      date: at || new Date(),
      type,
      qty,
      stockAfter: p.stock,
      refId,
      refNumber,
      note,
      user: this._user,
    });
  }

  // ───────────────────────────── Parties ─────────────────────────────

  _validateParty(i) {
    if (!String(i.name || '').trim()) throw new BusinessError('الاسم مطلوب');
    if (i.phone && i.phone.length < 8) throw new BusinessError('رقم الهاتف غير صحيح');
    if ((i.creditLimit || 0) < 0) throw new BusinessError('حد الائتمان لا يمكن أن يكون سالباً');
  }

  createParty(i, at) {
    this._validateParty(i);
    const now = at || new Date();
    const p = this.db.put('parties', {
      id: this.db.id(i.type === 'customer' ? 'cu' : 'su'),
      type: i.type,
      name: i.name.trim(),
      phone: i.phone || '',
      address: i.address || '',
      company: i.company || '',
      priceTier: i.priceTier || 'retail',
      creditLimit: i.creditLimit || 0,
      balance: 0,
      notes: i.notes || '',
      createdAt: now,
    });
    const ob = i.openingBalance || 0;
    if (Math.abs(ob) > EPS) {
      const cust = i.type === 'customer';
      const amount = Math.abs(ob);
      const increases = ob > 0;
      this._post(p.id, 'opening', 'رصيد افتتاحي', {
        debit: cust === increases ? amount : 0,
        credit: cust === increases ? 0 : amount,
        at: now,
      });
    }
    return this.db.parties.get(p.id);
  }

  updateParty(id, i) {
    const p = this._party(id);
    this._validateParty(i);
    Object.assign(p, {
      name: i.name.trim(),
      phone: i.phone || '',
      address: i.address || '',
      company: i.company || '',
      priceTier: i.priceTier || 'retail',
      creditLimit: i.creditLimit || 0,
      notes: i.notes || '',
    });
    return this.db.put('parties', p);
  }

  deleteParty(id) {
    const p = this._party(id);
    const hasDocs = [...this.db.invoices.values()].some((i) => i.partyId === id) || [...this.db.payments.values()].some((x) => x.partyId === id);
    if (hasDocs || Math.abs(p.balance) > EPS) {
      throw new BusinessError(`لا يمكن حذف ${M.PARTY_LABEL[p.type]} له فواتير أو رصيد مفتوح.`, Codes.hasTransactions);
    }
    this.db.remove('parties', id);
    for (const e of [...this.db.ledger.values()]) if (e.partyId === id) this.db.remove('ledger', e.id);
  }

  adjustBalance(id, amount, note = '', at) {
    const p = this._party(id);
    if (Math.abs(amount) < EPS) throw new BusinessError('أدخل مبلغ التسوية');
    const ref = this.db.number('ADJ', { pad: 4 });
    const debitSide = M.isCustomer(p) === amount > 0;
    this._post(id, 'adjustment', note ? `تسوية: ${note}` : 'تسوية رصيد', {
      debit: debitSide ? Math.abs(amount) : 0,
      credit: debitSide ? 0 : Math.abs(amount),
      at,
      refNumber: ref,
    });
    return this.db.parties.get(id);
  }

  _post(partyId, kind, description, { debit = 0, credit = 0, at, refId = null, refNumber = null } = {}) {
    const p = this._party(partyId);
    const delta = M.isCustomer(p) ? debit - credit : credit - debit;
    p.balance = r2(p.balance + delta);
    this.db.put('parties', p);
    this.db.put('ledger', {
      id: this.db.id('l'),
      partyId,
      date: at || new Date(),
      kind,
      description,
      debit: r2(debit),
      credit: r2(credit),
      balance: p.balance,
      refId,
      refNumber,
    });
  }

  // ───────────────────────────── Invoices ─────────────────────────────

  createInvoice(d, at) {
    const now = at || new Date();
    const isSale = d.type === 'sale';
    const meta = M.INVOICE[d.type];
    if (!meta) throw new BusinessError('نوع الفاتورة غير صحيح');
    const lines = d.lines || [];
    const payments = d.payments || [];
    const discount = d.discount || 0;

    // 1. Validate
    if (!lines.length) throw new BusinessError('أضف منتجاً واحداً على الأقل');
    for (const l of lines) {
      this._product(l.productId);
      if (!(l.qty > 0)) throw new BusinessError('الكمية يجب أن تكون أكبر من صفر');
      if (l.unitPrice < 0) throw new BusinessError('السعر غير صحيح');
      l.discount = l.discount || 0;
      if (l.discount < 0 || l.discount > l.qty * l.unitPrice + EPS) throw new BusinessError('خصم الصنف أكبر من قيمته');
    }
    const sub = r2(lines.reduce((s, l) => s + M.lineTotal(l), 0));
    if (discount < 0 || discount > sub + EPS) throw new BusinessError('الخصم أكبر من الإجمالي');
    const tot = r2(sub - discount);
    if (payments.some((p) => p.amount < 0)) throw new BusinessError('مبلغ دفع غير صحيح');
    const paid = r2(payments.reduce((s, p) => s + p.amount, 0));
    if (paid > tot + EPS) throw new BusinessError('المبلغ المدفوع أكبر من إجمالي الفاتورة');
    const dueAmt = r2(tot - paid);

    let party = null;
    if (d.partyId) {
      party = this._party(d.partyId);
      if (party.type !== meta.partyType) throw new BusinessError('نوع الطرف غير مناسب للفاتورة');
    } else if (!isSale) {
      throw new BusinessError('اختر المورد');
    }
    if (dueAmt > EPS && !party) throw new BusinessError('البيع الآجل يتطلب اختيار عميل مسجل');

    if (isSale && party && dueAmt > EPS && party.creditLimit > 0 && !d.overrideCreditLimit) {
      const nb = party.balance + dueAmt;
      if (nb > party.creditLimit + EPS) {
        throw new BusinessError(`تجاوز حد الائتمان: رصيد العميل سيصبح ${F.money(nb)} والحد ${F.money(party.creditLimit)}`, Codes.creditLimit);
      }
    }

    if (isSale && !this.db.settings.allowNegativeStock) {
      const need = {};
      for (const l of lines) need[l.productId] = (need[l.productId] || 0) + l.qty;
      for (const [pid, q] of Object.entries(need)) {
        const p = this._product(pid);
        if (q > p.stock + 0.0001) {
          throw new BusinessError(`الكمية المطلوبة من "${p.name}" (${F.qty(q)}) أكبر من المتاح (${F.qty(p.stock)})`, Codes.insufficientStock);
        }
      }
    }

    const cashPaid = payments.filter((p) => p.method === 'cash').reduce((s, p) => s + p.amount, 0);
    if (cashPaid > EPS) {
      const session = this._requireSession();
      if (!isSale) this._requireCash(session, cashPaid);
    }

    // 2. Apply
    const id = this.db.id(isSale ? 'si' : 'pi');
    const number = this.db.number(meta.prefix, { start: isSale ? 1000 : 500 });
    const factor = sub === 0 ? 1 : tot / sub;

    const invLines = lines.map((l) => {
      const p = this._product(l.productId);
      const netUnit = l.qty === 0 ? 0 : (M.lineTotal(l) / l.qty) * factor;
      return {
        productId: p.id,
        productName: p.name,
        unit: p.unit,
        qty: l.qty,
        unitPrice: l.unitPrice,
        discount: l.discount,
        costPrice: isSale ? p.purchasePrice : r2(netUnit),
        returnedQty: 0,
      };
    });

    const invoice = this.db.put('invoices', {
      id,
      number,
      type: d.type,
      date: now,
      partyId: party?.id || null,
      partyName: party?.name || 'عميل نقدي',
      priceTier: d.priceTier || 'retail',
      lines: invLines,
      discount: r2(discount),
      paid,
      payments: payments.filter((p) => p.amount > EPS).map((p) => ({ method: p.method, amount: p.amount, reference: p.reference || '' })),
      returnedAmount: 0,
      user: this._user,
      note: d.note || '',
      supplierRef: d.supplierRef || '',
    });

    for (const l of invLines) {
      if (isSale) {
        this._moveStock(l.productId, -l.qty, 'sale', { at: now, refId: id, refNumber: number });
      } else {
        this._moveStock(l.productId, l.qty, 'purchase', { at: now, refId: id, refNumber: number });
        const p = this.db.products.get(l.productId);
        p.purchasePrice = l.costPrice; // purchase price follows the latest cost
        this.db.put('products', p);
      }
    }

    if (party) {
      const ref = { at: now, refId: id, refNumber: number };
      if (isSale) {
        this._post(party.id, 'invoice', 'فاتورة بيع', { debit: tot, ...ref });
        if (paid > EPS) this._post(party.id, 'payment', 'مدفوع مع الفاتورة', { credit: paid, ...ref });
      } else {
        this._post(party.id, 'invoice', 'فاتورة شراء', { credit: tot, ...ref });
        if (paid > EPS) this._post(party.id, 'payment', 'مدفوع مع الفاتورة', { debit: paid, ...ref });
      }
    }

    for (const p of invoice.payments) {
      this._addTx(isSale ? 'sale' : 'purchase', M.methodAccount(p.method), p.amount, {
        at: now,
        refId: id,
        refNumber: number,
        note: `${meta.label} — ${invoice.partyName}${p.reference ? ` • مرجع ${p.reference}` : ''}`,
      });
    }
    return invoice;
  }

  createReturn(d, at) {
    const now = at || new Date();
    const inv = this.db.invoices.get(d.invoiceId);
    if (!inv) throw new NotFoundError('الفاتورة غير موجودة');
    const isSale = inv.type === 'sale';
    const refundMethod = d.refundMethod || 'cash';

    const qty = {};
    for (const [k, v] of Object.entries(d.qtyByProduct || {})) if (v > 0) qty[k] = v;
    if (!Object.keys(qty).length) throw new BusinessError('حدد كمية مرتجعة لصنف واحد على الأقل');
    for (const [pid, q] of Object.entries(qty)) {
      const line = inv.lines.find((l) => l.productId === pid);
      if (!line) throw new BusinessError('الصنف غير موجود في الفاتورة');
      if (q > M.returnableQty(line) + 0.0001) {
        throw new BusinessError(`أقصى كمية يمكن إرجاعها من "${line.productName}" هي ${F.qty(M.returnableQty(line))}`);
      }
      if (!isSale && !this.db.settings.allowNegativeStock) {
        const p = this._product(pid);
        if (q > p.stock + 0.0001) {
          throw new BusinessError(`لا يمكن إرجاع ${F.qty(q)} من "${p.name}" — المتاح بالمخزن ${F.qty(p.stock)}`, Codes.insufficientStock);
        }
      }
    }

    const s = M.settlement(inv, qty);
    if (s.cashRefund > EPS && refundMethod === 'cash') {
      const session = this._requireSession();
      if (isSale) this._requireCash(session, s.cashRefund);
    }

    const id = this.db.id(isSale ? 'sr' : 'pr');
    const number = this.db.number(isSale ? 'SR' : 'PR', { pad: 4 });
    const factor = M.discountFactor(inv);
    const lines = [];
    for (const l of inv.lines) {
      const q = qty[l.productId] || 0;
      if (q <= 0) continue;
      lines.push({ productId: l.productId, productName: l.productName, unit: l.unit, qty: q, unitPrice: r2(M.netUnitPrice(l) * factor), costPrice: l.costPrice });
      l.returnedQty = (l.returnedQty || 0) + q;
    }
    inv.returnedAmount = r2((inv.returnedAmount || 0) + s.total);
    inv.paid = r2(inv.paid - s.cashRefund);
    this.db.put('invoices', inv);

    const doc = this.db.put('returns', {
      id,
      number,
      type: inv.type,
      invoiceId: inv.id,
      invoiceNumber: inv.number,
      partyId: inv.partyId,
      partyName: inv.partyName,
      date: now,
      lines,
      creditApplied: s.creditApplied,
      cashRefund: s.cashRefund,
      refundMethod,
      user: this._user,
      reason: d.reason || '',
    });

    for (const l of lines) {
      this._moveStock(l.productId, isSale ? l.qty : -l.qty, isSale ? 'saleReturn' : 'purchaseReturn', {
        at: now, refId: id, refNumber: number, note: `من ${inv.number}`,
      });
    }

    if (inv.partyId) {
      const desc = `مرتجع من ${inv.number}`;
      const ref = { at: now, refId: id, refNumber: number };
      if (isSale) {
        this._post(inv.partyId, 'returnDoc', desc, { credit: s.total, ...ref });
        if (s.cashRefund > EPS) this._post(inv.partyId, 'refund', 'رد مبلغ للعميل', { debit: s.cashRefund, ...ref });
      } else {
        this._post(inv.partyId, 'returnDoc', desc, { debit: s.total, ...ref });
        if (s.cashRefund > EPS) this._post(inv.partyId, 'refund', 'استرداد مبلغ من المورد', { credit: s.cashRefund, ...ref });
      }
    }

    if (s.cashRefund > EPS) {
      this._addTx(isSale ? 'saleRefund' : 'purchaseRefund', M.methodAccount(refundMethod), s.cashRefund, {
        at: now, refId: id, refNumber: number, note: `مرتجع ${inv.number} — ${inv.partyName}`,
      });
    }
    return doc;
  }

  // ───────────────────────────── Payments ─────────────────────────────

  addPayment(i, at) {
    const now = at || new Date();
    const party = this._party(i.partyId);
    const amount = r2(i.amount || 0);
    if (amount <= 0) throw new BusinessError('أدخل مبلغاً أكبر من صفر');
    if (i.method === 'cash') {
      const session = this._requireSession();
      if (!M.isCustomer(party)) this._requireCash(session, amount);
    }
    const cust = M.isCustomer(party);
    const id = this.db.id('pay');
    const number = this.db.number(cust ? 'RC' : 'PV', { pad: 4 });
    const before = party.balance;
    const note = i.note || '';
    const ref = { at: now, refId: id, refNumber: number };
    const label = M.METHOD_LABEL[i.method];

    if (cust) this._post(party.id, 'payment', `تحصيل ${label}${note ? ` — ${note}` : ''}`, { credit: amount, ...ref });
    else this._post(party.id, 'payment', `سداد ${label}${note ? ` — ${note}` : ''}`, { debit: amount, ...ref });

    // FIFO allocation to the oldest open invoices.
    let left = amount;
    const open = [...this.db.invoices.values()].filter((x) => x.partyId === party.id && M.due(x) > EPS).sort((a, b) => a.date - b.date);
    for (const inv of open) {
      if (left <= EPS) break;
      const take = Math.min(left, M.due(inv));
      inv.paid = r2(inv.paid + take);
      this.db.put('invoices', inv);
      left = r2(left - take);
    }

    this._addTx(cust ? 'customerPayment' : 'supplierPayment', M.methodAccount(i.method), amount, { ...ref, note: party.name });

    return this.db.put('payments', {
      id,
      number,
      partyType: party.type,
      partyId: party.id,
      partyName: party.name,
      amount,
      method: i.method,
      date: now,
      user: this._user,
      note,
      balanceBefore: before,
      balanceAfter: this.db.parties.get(party.id).balance,
    });
  }

  // ───────────────────────────── Cash ─────────────────────────────

  openSession(opening, at) {
    if (this.db.openSession) throw new BusinessError('الخزنة مفتوحة بالفعل');
    if (opening < 0) throw new BusinessError('رصيد الافتتاح لا يمكن أن يكون سالباً');
    return this.db.put('sessions', {
      id: this.db.id('ses'),
      number: this.db.number('SH', { pad: 4 }),
      openedAt: at || new Date(),
      openedBy: this._user,
      openingBalance: r2(opening),
      closedAt: null,
      closedBy: null,
      expectedCash: null,
      countedCash: null,
      note: '',
    });
  }

  closeSession(counted, note = '', at) {
    const s = this.db.openSession;
    if (!s) throw new BusinessError('لا توجد وردية مفتوحة');
    if (counted < 0) throw new BusinessError('المبلغ الفعلي لا يمكن أن يكون سالباً');
    Object.assign(s, { expectedCash: r2(this.drawer(s).expected), closedAt: at || new Date(), closedBy: this._user, countedCash: r2(counted), note });
    return this.db.put('sessions', s);
  }

  drawer(s) {
    const txs = [...this.db.txs.values()].filter((t) => t.sessionId === s.id);
    const byType = {};
    for (const t of txs) byType[t.type] = r2((byType[t.type] || 0) + t.amount);
    let tin = 0, tout = 0;
    for (const [k, v] of Object.entries(byType)) M.txIsIn(k) ? (tin += v) : (tout += v);
    return { session: s, byType, transactions: txs.reverse(), expected: s.openingBalance + tin - tout };
  }

  get bankBalance() {
    return r2([...this.db.txs.values()].filter((t) => t.account === 'bank').reduce((s, t) => s + M.txSigned(t), 0));
  }

  get lastClosedCash() {
    const all = [...this.db.sessions.values()];
    for (let i = all.length - 1; i >= 0; i--) if (all[i].closedAt) return all[i].countedCash || 0;
    return 0;
  }

  addManualTx(i, at) {
    if (!M.MANUAL_TX.includes(i.type)) throw new BusinessError('نوع حركة غير مسموح');
    if (!(i.amount > 0)) throw new BusinessError('أدخل مبلغاً أكبر من صفر');
    if (i.type === 'expense' && !i.category) throw new BusinessError('اختر بند المصروف');
    const account = i.account || 'cash';
    if (account === 'cash') {
      const s = this._requireSession();
      if (!M.txIsIn(i.type)) this._requireCash(s, i.amount);
    } else if (!M.txIsIn(i.type) && i.amount > this.bankBalance + EPS) {
      throw new BusinessError(`رصيد البنك غير كافٍ (${F.money(this.bankBalance)})`, Codes.insufficientCash);
    }
    const note = String(i.note || '').trim() || i.category || M.txLabel(i.type);
    return this._addTx(i.type, account, i.amount, { at, refNumber: i.reference || null, note, category: i.category || null });
  }

  _addTx(type, account, amount, { at, refId = null, refNumber = null, note = '', category = null } = {}) {
    return this.db.put('txs', {
      id: this.db.id('t'),
      number: this.db.number('TX', { pad: 5 }),
      date: at || new Date(),
      type,
      account,
      amount: r2(amount),
      user: this._user,
      sessionId: account === 'cash' ? this.db.openSession?.id || null : null,
      refId,
      refNumber,
      note,
      category,
    });
  }

  _requireSession() {
    const s = this.db.openSession;
    if (!s) throw new BusinessError('الخزنة مغلقة. افتح وردية أولاً لتسجيل حركات نقدية.', Codes.drawerClosed);
    return s;
  }

  _requireCash(s, amount) {
    const available = this.drawer(s).expected;
    if (amount > available + EPS) {
      throw new BusinessError(`النقدية بالخزنة غير كافية. المتاح ${F.money(available)} والمطلوب ${F.money(amount)}`, Codes.insufficientCash);
    }
  }

  // ───────────────────────────── Helpers ─────────────────────────────

  _product(id) {
    const p = this.db.products.get(id);
    if (!p) throw new NotFoundError('المنتج غير موجود');
    return p;
  }

  _party(id) {
    const p = this.db.parties.get(id);
    if (!p) throw new NotFoundError('الطرف غير موجود');
    return p;
  }
}

module.exports = { Engine, EPS };
