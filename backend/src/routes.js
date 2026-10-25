const express = require('express');
const { Seeder } = require('./seeder');
const { ShoppingList } = require('./shopping');

const SETTINGS_KEYS = ['storeName', 'storePhone', 'storeAddress', 'invoiceFooter', 'allowNegativeStock', 'largeExpenseThreshold', 'debtDueDays', 'closingReminderHour', 'themeMode'];

const date = (v) => (v ? new Date(v) : null);
const num = (v) => Number(v || 0);

function buildRouter({ db, engine, reads }) {
  const r = express.Router();

  /// Read handler: runs [fn] and returns its result as JSON.
  const get = (path, fn) => r.get(path, (req, res, next) => {
    try {
      res.json(fn(req));
    } catch (e) {
      next(e);
    }
  });

  /// Write handler: runs [fn] atomically, persists to MongoDB, then responds.
  const write = (method, path, fn) => r[method](path, async (req, res, next) => {
    try {
      const result = fn(req);
      await db.flush();
      res.json(result === undefined ? { ok: true } : result);
    } catch (e) {
      next(e);
    }
  });

  r.get('/health', (_req, res) => res.json({ ok: true, name: 'tajer-backend' }));

  // ───────── Auth (public) ─────────
  write('post', '/auth/login', (req) => engine.login(req.body.username, req.body.pin));
  write('post', '/auth/register', (req) => engine.register(req.body.name, req.body.username, req.body.pin, req.body.email));

  get('/settings', () => db.settings);

  // Everything below requires a token.
  r.use((req, res, next) => {
    const token = (req.headers.authorization || '').replace(/^Bearer\s+/i, '');
    const user = engine.userForToken(token);
    if (!user) return res.status(401).json({ message: 'انتهت الجلسة. سجّل الدخول مرة أخرى.' });
    req.token = token;
    req.user = user;
    engine.user = user;
    next();
  });

  get('/auth/me', (req) => req.user);
  write('post', '/auth/logout', (req) => engine.logout(req.token));

  // ───────── Settings ─────────
  write('put', '/settings', (req) => {
    for (const k of SETTINGS_KEYS) if (req.body[k] !== undefined) db.settings[k] = req.body[k];
    db.touchMeta();
    return db.settings;
  });
  write('post', '/settings/reset-demo', () => new Seeder(db, engine).run());

  // ───────── Products ─────────
  get('/categories', () => [...db.categories.values()]);
  write('post', '/categories', (req) => engine.addCategory(req.body.name));
  get('/products', (req) => reads.products(req.query));
  get('/products/generate/barcode', () => ({ value: engine.generateBarcode() }));
  get('/products/generate/sku/:categoryId', (req) => ({ value: engine.generateSku(req.params.categoryId) }));
  get('/products/barcode/:code', (req) => ({ product: reads.findByBarcode(req.params.code) }));
  get('/products/:id', (req) => reads.product(req.params.id));
  get('/products/:id/movements', (req) => reads.stockMovements(req.params.id, req.query.type));
  get('/products/:id/stats', (req) => reads.productStats(req.params.id));
  write('post', '/products', (req) => engine.createProduct(req.body));
  write('put', '/products/:id', (req) => engine.updateProduct(req.params.id, req.body));
  write('delete', '/products/:id', (req) => engine.deleteProduct(req.params.id));
  write('post', '/products/:id/active', (req) => engine.setActive(req.params.id, req.body.active));
  write('post', '/products/:id/adjust', (req) => engine.adjustStock(req.params.id, num(req.body.newStock), req.body.reason, req.body.note || ''));

  // ───────── Parties ─────────
  get('/parties', (req) => reads.parties(req.query));
  get('/parties/:id', (req) => reads.party(req.params.id));
  get('/parties/:id/stats', (req) => reads.partyStats(req.params.id));
  get('/parties/:id/statement', (req) => reads.statement(req.params.id, date(req.query.from), date(req.query.to)));
  write('post', '/parties', (req) => engine.createParty(req.body));
  write('put', '/parties/:id', (req) => engine.updateParty(req.params.id, req.body));
  write('delete', '/parties/:id', (req) => engine.deleteParty(req.params.id));
  write('post', '/parties/:id/adjust', (req) => engine.adjustBalance(req.params.id, num(req.body.amount), req.body.note || ''));
  get('/payments', (req) => reads.payments(req.query.partyId, req.query.type));
  write('post', '/payments', (req) => engine.addPayment(req.body));

  // ───────── Invoices & returns ─────────
  get('/invoices', (req) => reads.invoices({ ...req.query, from: date(req.query.from), to: date(req.query.to) }));
  get('/invoices/:id', (req) => reads.invoice(req.params.id));
  write('post', '/invoices', (req) => engine.createInvoice(req.body));
  write('post', '/invoices/:id/feedback', (req) => engine.setFeedback(req.params.id, req.body.rating, req.body.feedback));
  get('/returns', (req) => reads.returns(req.query));
  get('/returns/:id', (req) => reads.returnDoc(req.params.id));
  write('post', '/returns', (req) => engine.createReturn(req.body));

  // ───────── Cash ─────────
  get('/cash/overview', () => reads.cashOverview());
  get('/cash/session', () => ({ session: db.openSession }));
  get('/cash/suggested-opening', () => ({ value: engine.lastClosedCash }));
  get('/cash/sessions', () => reads.sessions());
  get('/cash/sessions/:id/summary', (req) => reads.sessionSummary(req.params.id));
  write('post', '/cash/open', (req) => engine.openSession(num(req.body.openingBalance)));
  write('post', '/cash/close', (req) => engine.closeSession(num(req.body.countedCash), req.body.note || ''));
  get('/cash/transactions', (req) => reads.transactions({ ...req.query, from: date(req.query.from), to: date(req.query.to) }));
  write('post', '/cash/transactions', (req) => engine.addManualTx(req.body));

  // ───────── Reports ─────────
  get('/reports/dashboard', () => reads.dashboard());
  get('/reports/trade/:type', (req) => reads.tradeReport(req.params.type, { ...req.query, from: date(req.query.from), to: date(req.query.to) }));
  get('/reports/stock', (req) => reads.stockReport({ ...req.query, from: date(req.query.from), to: date(req.query.to) }));
  get('/reports/financial', (req) => reads.financialReport(date(req.query.from), date(req.query.to)));

  // ───────── Shortages list ─────────
  const shopping = new ShoppingList(db);
  get('/shopping', (req) => shopping.list(req.query));
  write('post', '/shopping', (req) => shopping.add(req.body, req.user));
  write('put', '/shopping/:id', (req) => shopping.update(req.params.id, req.body));
  write('post', '/shopping/remove', (req) => shopping.remove(req.body.ids || []));

  // ───────── Alerts ─────────
  get('/alerts', () => reads.alerts());
  write('post', '/alerts/read-all', () => {
    for (const a of reads.alerts()) db.readAlerts.add(a.id);
    db.touchMeta();
  });
  write('post', '/alerts/:id/read', (req) => {
    db.readAlerts.add(req.params.id);
    db.touchMeta();
  });

  // ───────── Search ─────────
  get('/search', (req) => reads.search(req.query.q, req.query.scope));
  get('/search/recent', () => db.recentSearches);
  write('post', '/search/recent', (req) => {
    const q = String(req.body.query || '').trim();
    if (!q) return;
    db.recentSearches = [q, ...db.recentSearches.filter((x) => x !== q)].slice(0, 10);
    db.touchMeta();
  });
  write('post', '/search/recent/remove', (req) => {
    db.recentSearches = db.recentSearches.filter((x) => x !== req.body.query);
    db.touchMeta();
  });
  write('delete', '/search/recent', () => {
    db.recentSearches = [];
    db.touchMeta();
  });

  return r;
}

module.exports = { buildRouter };
