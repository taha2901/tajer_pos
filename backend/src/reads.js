const F = require('./fmt');
const M = require('./model');
const { NotFoundError } = require('./errors');

const { r2, startOfDay, endOfDay, addDays } = F;
const vals = (m) => [...m.values()];
const byDateDesc = (a, b) => b.date - a.date;
const lc = (s) => String(s || '').toLowerCase();
const range = (from, to) => ({ from, to, has: (d) => d >= from && d <= to });
const lastDays = (n) => {
  const now = new Date();
  return range(startOfDay(addDays(now, -(n - 1))), endOfDay(now));
};
const dayKey = (d) => startOfDay(d).getTime();
const eachDay = (r, fn) => {
  for (let d = startOfDay(r.from); d <= r.to; d = addDays(d, 1)) fn(d);
};

/// Read side: lists, details, statistics, reports, alerts and search.
class Reads {
  constructor(db, engine) {
    this.db = db;
    this.engine = engine;
  }

  // ───────────────────────────── Products ─────────────────────────────

  products(q) {
    const s = lc(q.search).trim();
    const includeInactive = q.includeInactive !== 'false';
    const list = vals(this.db.products).filter((p) => {
      if (!includeInactive && !p.isActive) return false;
      if (q.categoryId && p.categoryId !== q.categoryId) return false;
      if (q.stockFilter === 'low' && !M.isLowStock(p)) return false;
      if (q.stockFilter === 'out' && !M.isOutOfStock(p)) return false;
      if (q.stockFilter === 'inactive' && p.isActive) return false;
      return !s || lc(p.name).includes(s) || p.barcode.includes(s) || lc(p.sku).includes(s);
    });
    const cmp = {
      name: (a, b) => a.name.localeCompare(b.name),
      newest: (a, b) => b.createdAt - a.createdAt,
      priceHigh: (a, b) => b.sellingPrice - a.sellingPrice,
      priceLow: (a, b) => a.sellingPrice - b.sellingPrice,
      stockLow: (a, b) => a.stock - b.stock,
      stockHigh: (a, b) => b.stock - a.stock,
    }[q.sort || 'name'];
    return list.sort(cmp);
  }

  product(id) {
    const p = this.db.products.get(id);
    if (!p) throw new NotFoundError('المنتج غير موجود أو تم حذفه');
    return p;
  }

  findByBarcode(code) {
    const c = String(code || '').trim();
    return vals(this.db.products).find((p) => p.barcode === c || lc(p.sku) === lc(c)) || null;
  }

  stockMovements(productId, type) {
    return vals(this.db.stockMoves).filter((m) => m.productId === productId && (!type || m.type === type)).sort(byDateDesc);
  }

  productStats(productId) {
    let soldQty = 0, soldAmount = 0, cost = 0, purchasedQty = 0, purchasedAmount = 0, returned = 0;
    for (const inv of vals(this.db.invoices)) {
      for (const l of inv.lines.filter((l) => l.productId === productId)) {
        const netQty = l.qty - (l.returnedQty || 0);
        const amount = netQty * M.netUnitPrice(l) * M.discountFactor(inv);
        if (inv.type === 'sale') {
          soldQty += netQty;
          soldAmount += amount;
          cost += netQty * l.costPrice;
          returned += l.returnedQty || 0;
        } else {
          purchasedQty += netQty;
          purchasedAmount += amount;
        }
      }
    }
    return {
      soldQty, soldAmount: r2(soldAmount), purchasedQty, purchasedAmount: r2(purchasedAmount), returnedQty: returned,
      profit: r2(soldAmount - cost), recentMovements: this.stockMovements(productId).slice(0, 5),
    };
  }

  // ───────────────────────────── Parties ─────────────────────────────

  parties(q) {
    const s = lc(q.search).trim();
    return vals(this.db.parties)
      .filter((p) => {
        if (p.type !== q.type) return false;
        const f = q.filter || 'all';
        if (f === 'withBalance' && !M.hasDebt(p)) return false;
        if (f === 'overLimit' && !M.overLimit(p)) return false;
        if (f === 'clear' && M.hasDebt(p)) return false;
        return !s || lc(p.name).includes(s) || p.phone.includes(s) || lc(p.company).includes(s);
      })
      .sort((a, b) => b.balance - a.balance);
  }

  party(id) {
    const p = this.db.parties.get(id);
    if (!p) throw new NotFoundError();
    return p;
  }

  partyStats(id) {
    const party = this.party(id);
    const invoices = vals(this.db.invoices).filter((i) => i.partyId === id);
    const entries = vals(this.db.ledger).filter((e) => e.partyId === id);
    const side = (e) => (M.isCustomer(party) ? e.credit - e.debit : e.debit - e.credit);
    const paid = entries.filter((e) => e.kind === 'payment' || e.kind === 'refund').reduce((s, e) => s + side(e), 0);
    const returns = vals(this.db.returns).filter((r) => r.partyId === id).reduce((s, r) => s + M.returnTotal(r), 0);
    return {
      invoicesCount: invoices.length,
      invoicesTotal: r2(invoices.reduce((s, i) => s + M.total(i), 0)),
      paidTotal: r2(paid),
      returnsTotal: r2(returns),
      lastActivity: entries.length ? new Date(Math.max(...entries.map((e) => e.date.getTime()))) : null,
    };
  }

  payments(partyId, type) {
    return vals(this.db.payments).filter((p) => (!partyId || p.partyId === partyId) && (!type || p.partyType === type)).sort(byDateDesc);
  }

  statement(id, from, to) {
    const party = this.party(id);
    const all = vals(this.db.ledger).filter((e) => e.partyId === id).sort((a, b) => a.date - b.date);
    let opening = 0;
    const entries = [];
    for (const e of all) {
      if (from && e.date < from) opening = e.balance;
      else if (!to || e.date <= to) entries.push(e);
    }
    return { party, from, to, openingBalance: opening, entries };
  }

  // ───────────────────────────── Invoices ─────────────────────────────

  invoices(q) {
    const s = lc(q.search).trim();
    return vals(this.db.invoices)
      .filter((i) => {
        if (i.type !== q.type) return false;
        if (q.partyId && i.partyId !== q.partyId) return false;
        if (q.from && i.date < q.from) return false;
        if (q.to && i.date > q.to) return false;
        const st = q.status || 'all';
        if (st === 'paid' && M.paymentStatus(i) !== 'paid') return false;
        if (st === 'due' && !(M.due(i) > 0.009)) return false;
        if (st === 'returned' && !M.hasReturns(i)) return false;
        return !s || lc(i.number).includes(s) || lc(i.partyName).includes(s) || lc(i.supplierRef).includes(s);
      })
      .sort(byDateDesc);
  }

  invoice(id) {
    const i = this.db.invoices.get(id);
    if (!i) throw new NotFoundError('الفاتورة غير موجودة');
    return i;
  }

  returns(q) {
    return vals(this.db.returns)
      .filter((r) => (!q.type || r.type === q.type) && (!q.invoiceId || r.invoiceId === q.invoiceId) && (!q.partyId || r.partyId === q.partyId))
      .sort(byDateDesc);
  }

  returnDoc(id) {
    const r = this.db.returns.get(id);
    if (!r) throw new NotFoundError('المرتجع غير موجود');
    return r;
  }

  // ───────────────────────────── Cash ─────────────────────────────

  cashOverview() {
    const open = this.db.openSession;
    return {
      drawer: open ? this.engine.drawer(open) : null,
      bankBalance: this.engine.bankBalance,
      lastClosedCash: this.engine.lastClosedCash,
      recentSessions: vals(this.db.sessions).filter((s) => s.closedAt).reverse().slice(0, 14),
    };
  }

  sessionSummary(id) {
    const s = this.db.sessions.get(id);
    if (!s) throw new NotFoundError();
    return this.engine.drawer(s);
  }

  transactions(q) {
    const s = lc(q.search).trim();
    return vals(this.db.txs)
      .filter(
        (t) =>
          (!q.account || t.account === q.account) &&
          (!q.type || t.type === q.type) &&
          (!q.sessionId || t.sessionId === q.sessionId) &&
          (!q.from || t.date >= q.from) &&
          (!q.to || t.date <= q.to) &&
          (!s || lc(t.note).includes(s) || lc(t.refNumber).includes(s) || lc(t.number).includes(s)),
      )
      .reverse();
  }

  sessions() {
    return vals(this.db.sessions).reverse();
  }

  // ───────────────────────────── Reports ─────────────────────────────

  _inv(type, r) {
    return vals(this.db.invoices).filter((i) => i.type === type && r.has(i.date));
  }

  _ret(type, r) {
    return vals(this.db.returns).filter((x) => x.type === type && r.has(x.date));
  }

  _cashBalance() {
    const open = this.db.openSession;
    return open ? this.engine.drawer(open).expected : this.engine.lastClosedCash;
  }

  dashboard() {
    const now = new Date();
    const today = range(startOfDay(now), endOfDay(now));
    const week = lastDays(7);
    const month = lastDays(30);
    const yesterday = range(addDays(today.from, -1), new Date(today.from.getTime() - 1));

    const sales = {}, profit = {}, purchases = {};
    for (const i of this._inv('sale', week)) {
      const d = dayKey(i.date);
      sales[d] = (sales[d] || 0) + M.total(i);
      profit[d] = (profit[d] || 0) + M.profit(i);
    }
    for (const r of this._ret('sale', week)) {
      const d = dayKey(r.date);
      sales[d] = (sales[d] || 0) - M.returnTotal(r);
      profit[d] = (profit[d] || 0) - (M.returnTotal(r) - M.returnCost(r));
    }
    for (const i of this._inv('purchase', week)) {
      const d = dayKey(i.date);
      purchases[d] = (purchases[d] || 0) + M.total(i);
    }
    const series = (m) => {
      const out = [];
      eachDay(week, (d) => out.push({ day: d, value: r2(m[d.getTime()] || 0) }));
      return out;
    };

    const tk = today.from.getTime();
    const products = vals(this.db.products).filter((p) => p.isActive);
    const ratio = (p) => p.stock / (p.minStock === 0 ? 1 : p.minStock);
    const low = products.filter((p) => M.isLowStock(p) || M.isOutOfStock(p)).sort((a, b) => ratio(a) - ratio(b));

    const top = {};
    for (const i of this._inv('sale', month)) {
      for (const l of i.lines) {
        const q = l.qty - (l.returnedQty || 0);
        const prev = top[l.productId] || { name: l.productName, value: 0, count: 0, extra: 0, id: l.productId };
        prev.value += q * M.netUnitPrice(l) * M.discountFactor(i);
        prev.count += q;
        top[l.productId] = prev;
      }
    }
    const recent = (t) => vals(this.db.invoices).filter((i) => i.type === t).sort(byDateDesc).slice(0, 5);
    const parties = vals(this.db.parties);

    return {
      todaySales: r2(sales[tk] || 0),
      todaySalesCount: this._inv('sale', today).length,
      todayPurchases: r2(purchases[tk] || 0),
      todayProfit: r2(profit[tk] || 0),
      todayExpenses: r2(vals(this.db.txs).filter((t) => t.type === 'expense' && today.has(t.date)).reduce((s, t) => s + t.amount, 0)),
      cashBalance: this._cashBalance(),
      drawerOpen: !!this.db.openSession,
      bankBalance: this.engine.bankBalance,
      customerDebts: r2(parties.filter((p) => M.isCustomer(p) && p.balance > 0).reduce((s, p) => s + p.balance, 0)),
      supplierDebts: r2(parties.filter((p) => !M.isCustomer(p) && p.balance > 0).reduce((s, p) => s + p.balance, 0)),
      lowStock: low.slice(0, 6),
      outOfStockCount: products.filter(M.isOutOfStock).length,
      recentSales: recent('sale'),
      recentPurchases: recent('purchase'),
      salesByDay: series(sales),
      purchasesByDay: series(purchases),
      profitByDay: series(profit),
      topProducts: Object.values(top).sort((a, b) => b.value - a.value).slice(0, 5),
      yesterdaySales: r2(this._inv('sale', yesterday).reduce((s, i) => s + M.total(i), 0)),
    };
  }

  tradeReport(type, f) {
    const r = range(f.from, f.to);
    const cats = new Map(vals(this.db.products).map((p) => [p.id, p.categoryId]));
    const lineOk = (pid) => (!f.productId || pid === f.productId) && (!f.categoryId || cats.get(pid) === f.categoryId);
    const lineFiltered = !!(f.productId || f.categoryId);

    const invoices = this._inv(type, r)
      .filter((i) => (!f.partyId || i.partyId === f.partyId) && (!lineFiltered || i.lines.some((l) => lineOk(l.productId))))
      .sort((a, b) => a.date - b.date);
    const returns = this._ret(type, r).filter((x) => !f.partyId || x.partyId === f.partyId);

    const maps = { day: new Map(), week: new Map(), month: new Map(), party: new Map(), product: new Map(), category: new Map(), method: new Map() };
    const partyNames = {}, productNames = {};
    const add = (m, key, value, count, extra) => {
      const row = m.get(key) || [0, 0, 0];
      row[0] += value;
      row[1] += count;
      row[2] += extra;
      m.set(key, row);
    };

    let gross = 0, discounts = 0, cost = 0, paid = 0, due = 0;
    for (const i of invoices) {
      let value = 0, invCost = 0;
      const factor = M.discountFactor(i);
      for (const l of i.lines.filter((l) => !lineFiltered || lineOk(l.productId))) {
        const v = M.lineTotal(l) * factor;
        const c = l.costPrice * l.qty;
        value += v;
        invCost += c;
        productNames[l.productId] = l.productName;
        add(maps.product, l.productId, v, l.qty, v - c);
        add(maps.category, cats.get(l.productId) || '-', v, l.qty, v - c);
      }
      gross += value;
      cost += invCost;
      discounts += M.totalDiscount(i);
      paid += i.paid;
      due += M.due(i);
      const d = startOfDay(i.date);
      add(maps.day, d.getTime(), value, 1, value - invCost);
      // Week starts on Saturday (as in the app).
      add(maps.week, addDays(d, -((d.getDay() + 1) % 7)).getTime(), value, 1, value - invCost);
      add(maps.month, new Date(d.getFullYear(), d.getMonth()).getTime(), value, 1, value - invCost);
      const pk = i.partyId || '_walkin';
      partyNames[pk] = i.partyId ? i.partyName : 'عميل نقدي';
      add(maps.party, pk, value, 1, value - invCost);
      let initial = 0;
      for (const p of i.payments) {
        add(maps.method, M.METHOD_LABEL[p.method], p.amount, 1, 0);
        initial += p.amount;
      }
      if (M.total(i) - initial > 0.009) add(maps.method, 'آجل', M.total(i) - initial, 1, 0);
    }

    let returnsTotal = 0;
    for (const x of returns) {
      for (const l of x.lines.filter((l) => !lineFiltered || lineOk(l.productId))) {
        returnsTotal += l.qty * l.unitPrice;
        cost -= l.costPrice * l.qty;
      }
    }

    const named = (m, label, withId) =>
      [...m.entries()].map(([k, v]) => ({ name: label(k), value: r2(v[0]), count: v[1], extra: r2(v[2]), id: withId ? k : null }));
    const desc = (l) => l.sort((a, b) => b.value - a.value);

    const byDay = [];
    eachDay(r, (d) => {
      const row = maps.day.get(d.getTime());
      byDay.push({ name: F.shortDate(d), value: r2(row?.[0] || 0), count: row?.[1] || 0, extra: r2(row?.[2] || 0), id: null });
    });
    const catNames = Object.fromEntries(vals(this.db.categories).map((c) => [c.id, c.name]));

    return {
      type,
      invoicesCount: invoices.length,
      gross: r2(gross),
      discounts: r2(discounts),
      returns: r2(returnsTotal),
      cost: type === 'sale' ? r2(cost) : 0,
      paid: r2(paid),
      due: r2(due),
      byDay,
      byWeek: named(maps.week, (k) => `أسبوع ${F.shortDate(new Date(k))}`),
      byMonth: named(maps.month, (k) => F.monthYear(new Date(k))),
      byParty: desc(named(maps.party, (k) => partyNames[k], true)),
      byProduct: desc(named(maps.product, (k) => productNames[k], true)),
      byCategory: desc(named(maps.category, (k) => catNames[k] || 'بدون فئة', true)),
      byPaymentMethod: desc(named(maps.method, (k) => k, true)),
    };
  }

  stockReport(q) {
    const products = vals(this.db.products)
      .filter((p) => p.isActive && (!q.categoryId || p.categoryId === q.categoryId))
      .sort((a, b) => a.name.localeCompare(b.name));
    const ids = new Set(products.map((p) => p.id));
    const r = q.from && q.to ? range(q.from, q.to) : lastDays(7);
    const movements = vals(this.db.stockMoves)
      .filter((m) => r.has(m.date) && ids.has(m.productId) && (!q.productId || m.productId === q.productId))
      .sort(byDateDesc);
    return {
      products,
      categoryNames: Object.fromEntries(vals(this.db.categories).map((c) => [c.id, c.name])),
      movements,
      productNames: Object.fromEntries(vals(this.db.products).map((p) => [p.id, p.name])),
    };
  }

  financialReport(from, to) {
    const r = range(from, to);
    const sales = this._inv('sale', r);
    const saleReturns = this._ret('sale', r);
    const txs = vals(this.db.txs).filter((t) => r.has(t.date));
    const expenses = txs.filter((t) => t.type === 'expense');

    const byCat = {};
    for (const e of expenses) byCat[e.category || 'أخرى'] = (byCat[e.category || 'أخرى'] || 0) + e.amount;
    const flowByType = {};
    for (const t of txs) flowByType[t.type] = (flowByType[t.type] || 0) + t.amount;
    const flowDay = {};
    for (const t of txs) {
      const k = dayKey(t.date);
      const row = flowDay[k] || [0, 0];
      row[M.txIsIn(t.type) ? 0 : 1] += t.amount;
      flowDay[k] = row;
    }
    const flowByDay = [];
    eachDay(r, (d) => {
      const row = flowDay[d.getTime()] || [0, 0];
      flowByDay.push({ name: F.shortDate(d), value: r2(row[0]), count: 0, extra: r2(row[1]), id: null });
    });
    const parties = vals(this.db.parties);
    const top = (t) =>
      parties
        .filter((p) => p.type === t && p.balance > 0.009)
        .sort((a, b) => b.balance - a.balance)
        .slice(0, 5)
        .map((p) => ({ name: p.name, value: p.balance, count: 0, extra: 0, id: p.id }));

    return {
      from,
      to,
      revenue: r2(sales.reduce((s, i) => s + M.total(i), 0)),
      salesReturns: r2(saleReturns.reduce((s, x) => s + M.returnTotal(x), 0)),
      cogs: r2(sales.reduce((s, i) => s + M.cost(i), 0) - saleReturns.reduce((s, x) => s + M.returnCost(x), 0)),
      expenses: r2(expenses.reduce((s, t) => s + t.amount, 0)),
      expensesByCategory: Object.entries(byCat).map(([k, v]) => ({ name: k, value: r2(v), count: 0, extra: 0, id: null })).sort((a, b) => b.value - a.value),
      customerDebts: r2(parties.filter((p) => M.isCustomer(p) && p.balance > 0).reduce((s, p) => s + p.balance, 0)),
      supplierDebts: r2(parties.filter((p) => !M.isCustomer(p) && p.balance > 0).reduce((s, p) => s + p.balance, 0)),
      topDebtors: top('customer'),
      topCreditors: top('supplier'),
      cashIn: r2(txs.filter((t) => M.txIsIn(t.type)).reduce((s, t) => s + t.amount, 0)),
      cashOut: r2(txs.filter((t) => !M.txIsIn(t.type)).reduce((s, t) => s + t.amount, 0)),
      flowByType,
      flowByDay,
      cashBalance: this._cashBalance(),
      bankBalance: this.engine.bankBalance,
    };
  }

  // ───────────────────────────── Alerts ─────────────────────────────

  /// Derived from live data; only the read-state is stored.
  alerts() {
    const db = this.db;
    const now = new Date();
    const read = db.readAlerts;
    const out = [];
    const lastMoveByProduct = {};
    for (const m of db.stockMoves.values()) lastMoveByProduct[m.productId] = m.date;
    const push = (a) => out.push({ ...a, isRead: read.has(a.id) });

    for (const p of vals(db.products).filter((p) => p.isActive)) {
      const date = lastMoveByProduct[p.id] || now;
      if (M.isOutOfStock(p)) {
        push({ id: `out_${p.id}`, kind: 'outOfStock', title: `نفد مخزون "${p.name}"`, body: `الرصيد الحالي ${F.qty(p.stock)} ${p.unit}. أنشئ فاتورة شراء لإعادة التوريد.`, date, severity: 'critical', targetId: p.id });
      } else if (M.isLowStock(p)) {
        push({ id: `low_${p.id}`, kind: 'lowStock', title: `مخزون منخفض: ${p.name}`, body: `المتبقي ${F.qty(p.stock)} ${p.unit} (الحد الأدنى ${F.qty(p.minStock)})`, date, severity: 'warning', targetId: p.id });
      }
    }

    const dueDays = db.settings.debtDueDays;
    const dueBefore = addDays(now, -dueDays);
    for (const party of vals(db.parties).filter(M.hasDebt)) {
      const oldest = vals(db.invoices).filter((i) => i.partyId === party.id && M.due(i) > 0.009).sort((a, b) => a.date - b.date)[0];
      const cust = M.isCustomer(party);
      if (cust && M.overLimit(party)) {
        push({ id: `limit_${party.id}_${Math.round(party.balance)}`, kind: 'customerOverLimit', title: `${party.name} تجاوز حد الائتمان`, body: `الرصيد ${F.money(party.balance)} • الحد ${F.money(party.creditLimit)}`, date: oldest?.date || now, severity: 'critical', targetId: party.id });
      }
      if (oldest && oldest.date < dueBefore) {
        const days = Math.floor((now - oldest.date) / 86400000);
        push({
          id: `${cust ? 'cdue' : 'sdue'}_${party.id}_${oldest.id}`,
          kind: cust ? 'customerDebtDue' : 'supplierPaymentDue',
          title: cust ? `مديونية مستحقة على ${party.name}` : `مستحق للمورد ${party.name}`,
          body: `فاتورة ${oldest.number} متأخرة ${days} يوماً • الرصيد الكلي ${F.money(party.balance)}`,
          date: addDays(oldest.date, dueDays),
          severity: 'warning',
          targetId: party.id,
        });
      }
    }

    for (const t of vals(db.txs).filter((t) => t.type === 'expense' && t.amount >= db.settings.largeExpenseThreshold && now - t.date < 7 * 86400000)) {
      push({ id: `exp_${t.id}`, kind: 'largeExpense', title: `مصروف كبير: ${F.money(t.amount)}`, body: `${t.category || ''} • ${t.note} • بواسطة ${t.user}`, date: t.date, severity: 'info', targetId: t.id });
    }

    const open = db.openSession;
    if (open) {
      const today = startOfDay(now);
      const stale = open.openedAt < today;
      const hour = db.settings.closingReminderHour;
      if (stale || now.getHours() >= hour) {
        push({
          id: `close_${open.id}_${stale ? 'stale' : now.getDate()}`,
          kind: 'closingReminder',
          title: stale ? `الوردية مفتوحة منذ ${F.dayLabel(open.openedAt)}` : 'حان وقت إقفال اليومية',
          body: `قم بجرد الخزنة وإقفال الوردية ${open.number}`,
          date: stale ? open.openedAt : new Date(today.getFullYear(), today.getMonth(), today.getDate(), hour),
          severity: stale ? 'critical' : 'info',
          targetId: open.id,
        });
      }
    }

    const sev = (s) => M.SEVERITY.indexOf(s);
    return out.sort((a, b) => sev(b.severity) - sev(a.severity) || b.date - a.date);
  }

  // ───────────────────────────── Search ─────────────────────────────

  search(query, scope = 'all') {
    const q = lc(query).trim();
    if (!q) return [];
    const want = (s) => scope === 'all' || scope === s;
    const hits = [];
    if (want('products')) {
      vals(this.db.products)
        .filter((p) => lc(p.name).includes(q) || p.barcode.includes(q) || lc(p.sku).includes(q))
        .slice(0, 20)
        .forEach((p) => hits.push({ kind: 'product', id: p.id, title: p.name, subtitle: `${p.sku} • المخزون ${F.qty(p.stock)} ${p.unit}`, trailing: F.money(p.sellingPrice) }));
    }
    for (const [s, type, kind] of [['customers', 'customer', 'customer'], ['suppliers', 'supplier', 'supplier']]) {
      if (!want(s)) continue;
      vals(this.db.parties)
        .filter((p) => p.type === type && (lc(p.name).includes(q) || p.phone.includes(q) || lc(p.company).includes(q)))
        .slice(0, 20)
        .forEach((p) => hits.push({ kind, id: p.id, title: p.name, subtitle: p.phone || M.PARTY_LABEL[type], trailing: M.hasDebt(p) ? F.money(p.balance) : '' }));
    }
    if (want('invoices')) {
      vals(this.db.invoices)
        .filter((i) => lc(i.number).includes(q) || lc(i.partyName).includes(q))
        .sort(byDateDesc)
        .slice(0, 20)
        .forEach((i) => hits.push({ kind: i.type, id: i.id, title: `${M.INVOICE[i.type].label} ${i.number}`, subtitle: `${i.partyName} • ${F.relative(i.date)}`, trailing: F.money(M.total(i)) }));
    }
    return hits;
  }
}

module.exports = { Reads };
