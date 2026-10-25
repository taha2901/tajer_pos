import '../../core/data_bus.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import 'local_gateway.dart';
import 'seeder.dart';

class LocalAuthRepository implements AuthRepository {
  LocalAuthRepository(this._g);
  final LocalGateway _g;

  @override
  List<({String username, String pin, String name})> get demoAccounts => [
        for (final u in demoUsers) (username: u.username, pin: demoPins[u.username]!, name: u.name),
      ];

  @override
  Future<AppUser> login(String username, String pin) => _g.read(() {
        final u = _g.db.users.where((x) => x.username == username.trim().toLowerCase()).firstOrNull;
        if (u == null || _g.db.pins[u.username] != pin) {
          throw const BusinessException('اسم المستخدم أو الرقم السري غير صحيح');
        }
        _g.db.currentUser = u;
        return u;
      });

  @override
  Future<AppUser> register({required String name, required String username, required String email, required String pin}) => _g.read(() {
        final uname = username.trim().toLowerCase();
        if (_g.db.users.any((x) => x.username == uname)) {
          throw const BusinessException('اسم المستخدم مستخدم بالفعل');
        }
        final u = AppUser(id: 'u${_g.db.users.length + 1}', name: name.trim(), username: uname, email: email.trim().toLowerCase());
        _g.db.users.add(u);
        _g.db.pins[uname] = pin;
        _g.db.currentUser = u;
        return u;
      });

  @override
  Future<void> logout() async => _g.db.currentUser = null;

  @override
  Future<AppUser?> currentUser() async => _g.db.currentUser;
}

class LocalSettingsRepository implements SettingsRepository {
  LocalSettingsRepository(this._g);
  final LocalGateway _g;

  @override
  Future<AppSettings> load() async => _g.db.settings;

  @override
  Future<AppSettings> save(AppSettings settings) async {
    _g.db.settings = settings;
    _g.bus.emit({DataTopic.settings, DataTopic.alerts});
    return settings;
  }

  @override
  Future<void> resetDemoData() async {
    final user = _g.db.currentUser;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    Seeder(_g.db, _g.engine).run();
    _g.db.currentUser = user;
    _g.bus.emit(DataTopic.values.toSet());
  }
}

class LocalProductRepository implements ProductRepository {
  LocalProductRepository(this._g);
  final LocalGateway _g;

  static const _topics = {DataTopic.products};

  @override
  Future<List<Product>> getProducts([ProductQuery q = const ProductQuery()]) => _g.read(() {
        final s = q.search.trim().toLowerCase();
        final list = _g.db.products.values.where((p) {
          if (!q.includeInactive && !p.isActive) return false;
          if (q.categoryId != null && p.categoryId != q.categoryId) return false;
          switch (q.stockFilter) {
            case ProductStockFilter.low:
              if (!p.isLowStock) return false;
            case ProductStockFilter.out:
              if (!p.isOutOfStock) return false;
            case ProductStockFilter.inactive:
              if (p.isActive) return false;
            case ProductStockFilter.all:
              break;
          }
          if (s.isEmpty) return true;
          return p.name.toLowerCase().contains(s) || p.barcode.contains(s) || p.sku.toLowerCase().contains(s);
        }).toList();
        int Function(Product, Product) cmp = switch (q.sort) {
          ProductSort.name => (a, b) => a.name.compareTo(b.name),
          ProductSort.newest => (a, b) => b.createdAt.compareTo(a.createdAt),
          ProductSort.priceHigh => (a, b) => b.sellingPrice.compareTo(a.sellingPrice),
          ProductSort.priceLow => (a, b) => a.sellingPrice.compareTo(b.sellingPrice),
          ProductSort.stockLow => (a, b) => a.stock.compareTo(b.stock),
          ProductSort.stockHigh => (a, b) => b.stock.compareTo(a.stock),
        };
        return list..sort(cmp);
      });

  @override
  Future<Product> getProduct(String id) =>
      _g.read(() => _g.db.products[id] ?? (throw const NotFoundException('المنتج غير موجود أو تم حذفه')));

  @override
  Future<Product?> findByBarcode(String code) async {
    final c = code.trim();
    return _g.db.products.values.where((p) => p.barcode == c || p.sku.toLowerCase() == c.toLowerCase()).firstOrNull;
  }

  @override
  Future<Product> create(ProductInput input) => _g.write(() => _g.engine.createProduct(input), _topics);

  @override
  Future<Product> update(String id, ProductInput input) =>
      _g.write(() => _g.engine.updateProduct(id, input), {..._topics, DataTopic.invoices});

  @override
  Future<void> delete(String id) => _g.write(() => _g.engine.deleteProduct(id), _topics);

  @override
  Future<Product> setActive(String id, bool active) => _g.write(() => _g.engine.setActive(id, active), _topics);

  @override
  Future<Product> adjustStock(String id, {required double newStock, required StockAdjustReason reason, String note = ''}) =>
      _g.write(() => _g.engine.adjustStock(id, newStock, reason, note), _topics);

  @override
  Future<List<StockMovement>> getStockMovements(String productId, {StockMoveType? type}) => _g.read(() {
        final list = _g.db.stockMoves.where((m) => m.productId == productId && (type == null || m.type == type)).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        return list;
      });

  @override
  Future<ProductStats> getStats(String productId) => _g.read(() {
        var soldQty = 0.0, soldAmount = 0.0, cost = 0.0, purchasedQty = 0.0, purchasedAmount = 0.0, returned = 0.0;
        for (final inv in _g.db.invoices.values) {
          for (final l in inv.lines.where((l) => l.productId == productId)) {
            final netQty = l.qty - l.returnedQty;
            final amount = netQty * l.netUnitPrice * inv.discountFactor;
            if (inv.type == InvoiceType.sale) {
              soldQty += netQty;
              soldAmount += amount;
              cost += netQty * l.costPrice;
              returned += l.returnedQty;
            } else {
              purchasedQty += netQty;
              purchasedAmount += amount;
            }
          }
        }
        final moves = _g.db.stockMoves.where((m) => m.productId == productId).toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        return ProductStats(
          soldQty: soldQty,
          soldAmount: r2(soldAmount),
          purchasedQty: purchasedQty,
          purchasedAmount: r2(purchasedAmount),
          returnedQty: returned,
          profit: r2(soldAmount - cost),
          recentMovements: moves.take(5).toList(),
        );
      });

  @override
  Future<List<Category>> getCategories() => _g.read(() => _g.db.categories.values.toList());

  @override
  Future<Category> addCategory(String name) => _g.write(() => _g.engine.addCategory(name), _topics);

  @override
  Future<String> generateBarcode() async => _g.engine.generateBarcode();

  @override
  Future<String> generateSku(String categoryId) async => _g.engine.generateSku(categoryId);
}

class LocalPartyRepository implements PartyRepository {
  LocalPartyRepository(this._g);
  final LocalGateway _g;

  static const _topics = {DataTopic.parties};

  @override
  Future<List<Party>> getParties(PartyQuery q) => _g.read(() {
        final s = q.search.trim().toLowerCase();
        final list = _g.db.parties.values.where((p) {
          if (p.type != q.type) return false;
          final ok = switch (q.filter) {
            PartyFilter.all => true,
            PartyFilter.withBalance => p.hasDebt,
            PartyFilter.overLimit => p.overLimit,
            PartyFilter.clear => !p.hasDebt,
          };
          if (!ok) return false;
          return s.isEmpty ||
              p.name.toLowerCase().contains(s) ||
              p.phone.contains(s) ||
              p.company.toLowerCase().contains(s);
        }).toList();
        return list..sort((a, b) => b.balance.compareTo(a.balance));
      });

  @override
  Future<Party> getParty(String id) => _g.read(() => _g.db.parties[id] ?? (throw const NotFoundException()));

  @override
  Future<Party> create(PartyInput input) => _g.write(() => _g.engine.createParty(input), _topics);

  @override
  Future<Party> update(String id, PartyInput input) => _g.write(() => _g.engine.updateParty(id, input), _topics);

  @override
  Future<void> delete(String id) => _g.write(() => _g.engine.deleteParty(id), _topics);

  @override
  Future<PartyStats> getStats(String id) => _g.read(() {
        final invoices = _g.db.invoices.values.where((i) => i.partyId == id).toList();
        final entries = _g.db.ledger.where((e) => e.partyId == id).toList();
        final party = _g.db.parties[id]!;
        double side(LedgerEntry e) => party.isCustomer ? e.credit - e.debit : e.debit - e.credit;
        final paid = entries.where((e) => e.kind == LedgerKind.payment || e.kind == LedgerKind.refund).fold(0.0, (s, e) => s + side(e));
        final returns = _g.db.returns.values.where((r) => r.partyId == id).fold(0.0, (s, r) => s + r.total);
        return PartyStats(
          invoicesCount: invoices.length,
          invoicesTotal: r2(invoices.fold(0.0, (s, i) => s + i.total)),
          paidTotal: r2(paid),
          returnsTotal: r2(returns),
          lastActivity: entries.isEmpty ? null : entries.map((e) => e.date).reduce((a, b) => a.isAfter(b) ? a : b),
        );
      });

  @override
  Future<PartyPayment> addPayment(PaymentInput input) =>
      _g.write(() => _g.engine.addPayment(input), {..._topics, DataTopic.invoices, DataTopic.cash});

  @override
  Future<List<PartyPayment>> getPayments({String? partyId, PartyType? type}) => _g.read(() {
        return _g.db.payments.values
            .where((p) => (partyId == null || p.partyId == partyId) && (type == null || p.partyType == type))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
      });

  @override
  Future<Party> adjustBalance(String id, {required double amount, required String note}) =>
      _g.write(() => _g.engine.adjustBalance(id, amount, note), _topics);

  @override
  Future<Statement> getStatement(String id, {DateTime? from, DateTime? to}) => _g.read(() {
        final party = _g.db.parties[id] ?? (throw const NotFoundException());
        final all = _g.db.ledger.where((e) => e.partyId == id).toList()..sort((a, b) => a.date.compareTo(b.date));
        var opening = 0.0;
        final entries = <LedgerEntry>[];
        for (final e in all) {
          if (from != null && e.date.isBefore(from)) {
            opening = e.balance;
          } else if (to == null || !e.date.isAfter(to)) {
            entries.add(e);
          }
        }
        return Statement(party: party, from: from, to: to, openingBalance: opening, entries: entries);
      });
}

class LocalInvoiceRepository implements InvoiceRepository {
  LocalInvoiceRepository(this._g);
  final LocalGateway _g;

  static const _topics = {DataTopic.invoices, DataTopic.products, DataTopic.parties, DataTopic.cash};

  @override
  Future<Invoice> create(InvoiceDraft draft) => _g.write(() => _g.engine.createInvoice(draft), _topics);

  @override
  Future<List<Invoice>> getInvoices(InvoiceQuery q) => _g.read(() {
        final s = q.search.trim().toLowerCase();
        final list = _g.db.invoices.values.where((i) {
          if (i.type != q.type) return false;
          if (q.partyId != null && i.partyId != q.partyId) return false;
          if (q.from != null && i.date.isBefore(q.from!)) return false;
          if (q.to != null && i.date.isAfter(q.to!)) return false;
          final statusOk = switch (q.status) {
            InvoiceStatusFilter.all => true,
            InvoiceStatusFilter.paid => i.paymentStatus == PaymentStatus.paid,
            InvoiceStatusFilter.due => i.due > 0.009,
            InvoiceStatusFilter.returned => i.hasReturns,
          };
          if (!statusOk) return false;
          return s.isEmpty ||
              i.number.toLowerCase().contains(s) ||
              i.partyName.toLowerCase().contains(s) ||
              i.supplierRef.toLowerCase().contains(s);
        }).toList();
        return list..sort((a, b) => b.date.compareTo(a.date));
      });

  @override
  Future<Invoice> getInvoice(String id) =>
      _g.read(() => _g.db.invoices[id] ?? (throw const NotFoundException('الفاتورة غير موجودة')));

  @override
  Future<Invoice> setFeedback(String invoiceId, {required int rating, required String feedback}) => _g.write(() {
        final inv = _g.db.invoices[invoiceId] ?? (throw const NotFoundException('الفاتورة غير موجودة'));
        return _g.db.invoices[invoiceId] = inv.copyWith(rating: rating, feedback: feedback.trim());
      }, {DataTopic.invoices});

  @override
  Future<ReturnDoc> createReturn(ReturnDraft draft) => _g.write(() => _g.engine.createReturn(draft), _topics);

  @override
  Future<List<ReturnDoc>> getReturns({InvoiceType? type, String? invoiceId, String? partyId}) => _g.read(() {
        return _g.db.returns.values
            .where((r) =>
                (type == null || r.type == type) &&
                (invoiceId == null || r.invoiceId == invoiceId) &&
                (partyId == null || r.partyId == partyId))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
      });

  @override
  Future<ReturnDoc> getReturn(String id) =>
      _g.read(() => _g.db.returns[id] ?? (throw const NotFoundException('المرتجع غير موجود')));
}

class LocalCashRepository implements CashRepository {
  LocalCashRepository(this._g);
  final LocalGateway _g;

  static const _topics = {DataTopic.cash};

  @override
  Future<CashOverview> getOverview() => _g.read(() {
        final open = _g.db.openSession;
        final closed = _g.db.sessions.where((s) => !s.isOpen).toList().reversed.take(14).toList();
        return CashOverview(
          drawer: open == null ? null : _g.engine.drawer(open),
          bankBalance: _g.engine.bankBalance,
          lastClosedCash: _g.engine.lastClosedCash,
          recentSessions: closed,
        );
      });

  @override
  Future<CashSession?> currentSession() async => _g.db.openSession;

  @override
  Future<double> suggestedOpening() async => _g.engine.lastClosedCash;

  @override
  Future<CashSession> openSession(double openingBalance) =>
      _g.write(() => _g.engine.openSession(openingBalance), _topics);

  @override
  Future<CashSession> closeSession({required double countedCash, String note = ''}) =>
      _g.write(() => _g.engine.closeSession(countedCash, note), _topics);

  @override
  Future<DrawerSummary> getSessionSummary(String sessionId) => _g.read(() {
        final s = _g.db.sessions.where((x) => x.id == sessionId).firstOrNull ?? (throw const NotFoundException());
        return _g.engine.drawer(s);
      });

  @override
  Future<MoneyTx> addTransaction(MoneyTxInput input) => _g.write(() => _g.engine.addManualTx(input), _topics);

  @override
  Future<List<MoneyTx>> getTransactions(TxQuery q) => _g.read(() {
        final s = q.search.trim().toLowerCase();
        return _g.db.txs
            .where((t) =>
                (q.account == null || t.account == q.account) &&
                (q.type == null || t.type == q.type) &&
                (q.sessionId == null || t.sessionId == q.sessionId) &&
                (q.from == null || !t.date.isBefore(q.from!)) &&
                (q.to == null || !t.date.isAfter(q.to!)) &&
                (s.isEmpty || t.note.toLowerCase().contains(s) || (t.refNumber ?? '').toLowerCase().contains(s) || t.number.toLowerCase().contains(s)))
            .toList()
            .reversed
            .toList();
      });

  @override
  Future<List<CashSession>> getSessions() => _g.read(() => _g.db.sessions.reversed.toList());
}

class LocalShoppingListRepository implements ShoppingListRepository {
  LocalShoppingListRepository(this._g);
  final LocalGateway _g;

  static const _topics = {DataTopic.shopping};

  /// Joins the current product name/unit/stock and supplier name.
  ShoppingItem _view(ShoppingItem it) {
    final p = it.productId == null ? null : _g.db.products[it.productId];
    final s = it.supplierId == null ? null : _g.db.parties[it.supplierId];
    return ShoppingItem(
      id: it.id,
      productId: it.productId,
      name: p?.name ?? it.name,
      unit: p?.unit ?? it.unit,
      qty: it.qty,
      stock: p?.stock,
      supplierId: s?.id,
      supplierName: s?.name,
      note: it.note,
      addedBy: it.addedBy,
      createdAt: it.createdAt,
    );
  }

  ShoppingItem _build(String id, ShoppingItemInput i, {required String addedBy, required DateTime createdAt}) {
    if (i.productId == null && i.name.trim().isEmpty) throw const BusinessException('اكتب اسم الصنف.');
    if (i.qty <= 0) throw const BusinessException('الكمية يجب أن تكون أكبر من صفر.');
    return ShoppingItem(
      id: id,
      productId: i.productId,
      name: i.name.trim(),
      unit: i.unit.trim(),
      qty: i.qty,
      supplierId: i.supplierId,
      note: i.note.trim(),
      addedBy: addedBy,
      createdAt: createdAt,
    );
  }

  @override
  Future<List<ShoppingItem>> getItems({String? supplierId}) => _g.read(() => [
        for (final it in _g.db.shopping.reversed)
          if (supplierId == null || it.supplierId == null || it.supplierId == supplierId) _view(it),
      ]);

  @override
  Future<ShoppingItem> add(ShoppingItemInput input) => _g.write(() {
        final list = _g.db.shopping;
        final idx = input.productId == null ? -1 : list.indexWhere((x) => x.productId == input.productId);
        if (idx >= 0) {
          final old = list[idx];
          list[idx] = _build(
            old.id,
            ShoppingItemInput(
              productId: old.productId,
              qty: old.qty + input.qty,
              supplierId: input.supplierId ?? old.supplierId,
              note: input.note.isEmpty ? old.note : input.note,
            ),
            addedBy: old.addedBy,
            createdAt: old.createdAt,
          );
          return _view(list[idx]);
        }
        final it = _build(_g.db.id('sh'), input, addedBy: _g.db.currentUser?.name ?? '', createdAt: DateTime.now());
        list.add(it);
        return _view(it);
      }, _topics);

  @override
  Future<ShoppingItem> update(String id, ShoppingItemInput input) => _g.write(() {
        final list = _g.db.shopping;
        final idx = list.indexWhere((x) => x.id == id);
        if (idx < 0) throw const NotFoundException();
        final old = list[idx];
        list[idx] = _build(id, input, addedBy: old.addedBy, createdAt: old.createdAt);
        return _view(list[idx]);
      }, _topics);

  @override
  Future<void> remove(List<String> ids) => _g.write(() => _g.db.shopping.removeWhere((x) => ids.contains(x.id)), _topics);
}
