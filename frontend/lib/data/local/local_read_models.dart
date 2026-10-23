import '../../core/data_bus.dart';
import '../../core/format.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import 'local_gateway.dart';

/// Report / dashboard aggregation. With a backend these become report endpoints.
class LocalReportRepository implements ReportRepository {
  LocalReportRepository(this._g);
  final LocalGateway _g;

  Iterable<Invoice> _invoices(InvoiceType t, DateRange r) =>
      _g.db.invoices.values.where((i) => i.type == t && r.contains(i.date));

  Iterable<ReturnDoc> _returns(InvoiceType t, DateRange r) =>
      _g.db.returns.values.where((x) => x.type == t && r.contains(x.date));

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  List<DayValue> _series(DateRange r, double Function(DateTime day) valueOf) {
    final out = <DayValue>[];
    for (var d = _day(r.from); !d.isAfter(r.to); d = DateTime(d.year, d.month, d.day + 1)) {
      out.add(DayValue(d, r2(valueOf(d))));
    }
    return out;
  }

  @override
  Future<DashboardData> getDashboard() => _g.read(() {
        final today = DateRange.today();
        final week = DateRange.lastDays(7);
        final month = DateRange.lastDays(30);
        final yesterday = DateRange(today.from.subtract(const Duration(days: 1)), today.from.subtract(const Duration(milliseconds: 1)));

        final salesPerDay = <DateTime, double>{};
        final profitPerDay = <DateTime, double>{};
        final purchasesPerDay = <DateTime, double>{};
        for (final i in _invoices(InvoiceType.sale, week)) {
          final d = _day(i.date);
          salesPerDay[d] = (salesPerDay[d] ?? 0) + i.total;
          profitPerDay[d] = (profitPerDay[d] ?? 0) + i.profit;
        }
        for (final r in _returns(InvoiceType.sale, week)) {
          final d = _day(r.date);
          salesPerDay[d] = (salesPerDay[d] ?? 0) - r.total;
          profitPerDay[d] = (profitPerDay[d] ?? 0) - (r.total - r.cost);
        }
        for (final i in _invoices(InvoiceType.purchase, week)) {
          final d = _day(i.date);
          purchasesPerDay[d] = (purchasesPerDay[d] ?? 0) + i.total;
        }

        final todayKey = _day(today.from);
        final open = _g.db.openSession;
        final products = _g.db.products.values.where((p) => p.isActive).toList();
        final low = products.where((p) => p.isLowStock || p.isOutOfStock).toList()
          ..sort((a, b) => (a.stock / (a.minStock == 0 ? 1 : a.minStock)).compareTo(b.stock / (b.minStock == 0 ? 1 : b.minStock)));

        final top = <String, NamedValue>{};
        for (final i in _invoices(InvoiceType.sale, month)) {
          for (final l in i.lines) {
            final q = l.qty - l.returnedQty;
            final prev = top[l.productId];
            top[l.productId] = NamedValue(l.productName, (prev?.value ?? 0) + q * l.netUnitPrice * i.discountFactor,
                count: (prev?.count ?? 0) + q, id: l.productId);
          }
        }
        final topList = top.values.toList()..sort((a, b) => b.value.compareTo(a.value));

        List<Invoice> recent(InvoiceType t) =>
            (_g.db.invoices.values.where((i) => i.type == t).toList()..sort((a, b) => b.date.compareTo(a.date))).take(5).toList();

        final balances = _g.db.parties.values;
        return DashboardData(
          todaySales: r2(salesPerDay[todayKey] ?? 0),
          todaySalesCount: _invoices(InvoiceType.sale, today).length,
          todayPurchases: r2(purchasesPerDay[todayKey] ?? 0),
          todayProfit: r2(profitPerDay[todayKey] ?? 0),
          todayExpenses: r2(_g.db.txs.where((t) => t.type == TxType.expense && today.contains(t.date)).fold(0.0, (s, t) => s + t.amount)),
          cashBalance: open == null ? _g.engine.lastClosedCash : _g.engine.drawer(open).expected,
          drawerOpen: open != null,
          bankBalance: _g.engine.bankBalance,
          customerDebts: r2(balances.where((p) => p.isCustomer && p.balance > 0).fold(0.0, (s, p) => s + p.balance)),
          supplierDebts: r2(balances.where((p) => !p.isCustomer && p.balance > 0).fold(0.0, (s, p) => s + p.balance)),
          lowStock: low.take(6).toList(),
          outOfStockCount: products.where((p) => p.isOutOfStock).length,
          recentSales: recent(InvoiceType.sale),
          recentPurchases: recent(InvoiceType.purchase),
          salesByDay: _series(week, (d) => salesPerDay[d] ?? 0),
          purchasesByDay: _series(week, (d) => purchasesPerDay[d] ?? 0),
          profitByDay: _series(week, (d) => profitPerDay[d] ?? 0),
          topProducts: topList.take(5).toList(),
          yesterdaySales: r2(_invoices(InvoiceType.sale, yesterday).fold(0.0, (s, i) => s + i.total)),
        );
      });

  @override
  Future<TradeReport> getTradeReport(InvoiceType type, TradeReportFilter f) => _g.read(() {
        final cats = {for (final p in _g.db.products.values) p.id: p.categoryId};
        bool lineOk(String productId) =>
            (f.productId == null || productId == f.productId) &&
            (f.categoryId == null || cats[productId] == f.categoryId);
        final lineFiltered = f.productId != null || f.categoryId != null;

        final invoices = _invoices(type, f.range)
            .where((i) => (f.partyId == null || i.partyId == f.partyId) && (!lineFiltered || i.lines.any((l) => lineOk(l.productId))))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
        final returns = _returns(type, f.range).where((r) => f.partyId == null || r.partyId == f.partyId).toList();

        final byDay = <DateTime, List<double>>{}; // [value, count, profit]
        final byWeek = <DateTime, List<double>>{};
        final byMonth = <DateTime, List<double>>{};
        final byParty = <String, List<double>>{};
        final partyNames = <String, String>{};
        final byProduct = <String, List<double>>{};
        final productNames = <String, String>{};
        final byCategory = <String, List<double>>{};
        final byMethod = <String, List<double>>{};

        void add(Map<dynamic, List<double>> m, Object key, double value, double count, double extra) {
          final row = m.putIfAbsent(key, () => [0, 0, 0]);
          row[0] += value;
          row[1] += count;
          row[2] += extra;
        }

        var gross = 0.0, discounts = 0.0, cost = 0.0, paid = 0.0, due = 0.0;
        for (final i in invoices) {
          var value = 0.0, invCost = 0.0;
          for (final l in i.lines.where((l) => !lineFiltered || lineOk(l.productId))) {
            final v = l.total * i.discountFactor;
            final c = l.costPrice * l.qty;
            value += v;
            invCost += c;
            productNames[l.productId] = l.productName;
            add(byProduct, l.productId, v, l.qty, v - c);
            add(byCategory, cats[l.productId] ?? '-', v, l.qty, v - c);
          }
          gross += value;
          cost += invCost;
          discounts += i.totalDiscount;
          paid += i.paid;
          due += i.due;
          final d = _day(i.date);
          add(byDay, d, value, 1, value - invCost);
          add(byWeek, d.subtract(Duration(days: (d.weekday + 1) % 7)), value, 1, value - invCost);
          add(byMonth, DateTime(d.year, d.month), value, 1, value - invCost);
          final pk = i.partyId ?? '_walkin';
          partyNames[pk] = i.partyId == null ? 'عميل نقدي' : i.partyName;
          add(byParty, pk, value, 1, value - invCost);
          var initial = 0.0;
          for (final p in i.payments) {
            add(byMethod, p.method.label, p.amount, 1, 0);
            initial += p.amount;
          }
          if (i.total - initial > 0.009) add(byMethod, 'آجل', i.total - initial, 1, 0);
        }

        var returnsTotal = 0.0;
        for (final r in returns) {
          for (final l in r.lines.where((l) => !lineFiltered || lineOk(l.productId))) {
            returnsTotal += l.total;
            cost -= l.costPrice * l.qty;
          }
        }

        List<NamedValue> named(Map<dynamic, List<double>> m, String Function(dynamic key) label) {
          final list = m.entries
              .map((e) => NamedValue(label(e.key), r2(e.value[0]), count: e.value[1], extra: r2(e.value[2]), id: e.key is String ? e.key as String : null))
              .toList();
          return list;
        }

        List<NamedValue> sortedDesc(List<NamedValue> l) => l..sort((a, b) => b.value.compareTo(a.value));

        final dayList = <NamedValue>[];
        for (var d = _day(f.range.from); !d.isAfter(f.range.to); d = DateTime(d.year, d.month, d.day + 1)) {
          final row = byDay[d];
          dayList.add(NamedValue(Fmt.shortDate(d), r2(row?[0] ?? 0), count: row?[1] ?? 0, extra: r2(row?[2] ?? 0)));
        }
        final catNames = {for (final c in _g.db.categories.values) c.id: c.name};

        return TradeReport(
          type: type,
          invoicesCount: invoices.length,
          gross: r2(gross),
          discounts: r2(discounts),
          returns: r2(returnsTotal),
          cost: type == InvoiceType.sale ? r2(cost) : 0,
          paid: r2(paid),
          due: r2(due),
          byDay: dayList,
          byWeek: named(byWeek, (k) => 'أسبوع ${Fmt.shortDate(k as DateTime)}'),
          byMonth: named(byMonth, (k) => Fmt.monthYear(k as DateTime)),
          byParty: sortedDesc(named(byParty, (k) => partyNames[k]!)),
          byProduct: sortedDesc(named(byProduct, (k) => productNames[k]!)),
          byCategory: sortedDesc(named(byCategory, (k) => catNames[k] ?? 'بدون فئة')),
          byPaymentMethod: sortedDesc(named(byMethod, (k) => k as String)),
        );
      });

  @override
  Future<StockReport> getStockReport({DateRange? movementRange, String? productId, String? categoryId}) => _g.read(() {
        final products = _g.db.products.values.where((p) => p.isActive && (categoryId == null || p.categoryId == categoryId)).toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        final ids = products.map((p) => p.id).toSet();
        final range = movementRange ?? DateRange.lastDays(7);
        final moves = _g.db.stockMoves
            .where((m) => range.contains(m.date) && ids.contains(m.productId) && (productId == null || m.productId == productId))
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        return StockReport(
          products: products,
          categoryNames: {for (final c in _g.db.categories.values) c.id: c.name},
          movements: moves,
          productNames: {for (final p in _g.db.products.values) p.id: p.name},
        );
      });

  @override
  Future<FinancialReport> getFinancialReport(DateRange range) => _g.read(() {
        final sales = _invoices(InvoiceType.sale, range).toList();
        final saleReturns = _returns(InvoiceType.sale, range).toList();
        final txs = _g.db.txs.where((t) => range.contains(t.date)).toList();
        final expenses = txs.where((t) => t.type == TxType.expense);

        final byCat = <String, double>{};
        for (final e in expenses) {
          byCat[e.category ?? 'أخرى'] = (byCat[e.category ?? 'أخرى'] ?? 0) + e.amount;
        }
        final flowByType = <TxType, double>{};
        for (final t in txs) {
          flowByType[t.type] = (flowByType[t.type] ?? 0) + t.amount;
        }
        final flowDay = <DateTime, List<double>>{};
        for (final t in txs) {
          final row = flowDay.putIfAbsent(_day(t.date), () => [0, 0]);
          row[t.isIn ? 0 : 1] += t.amount;
        }
        final flowList = <NamedValue>[];
        for (var d = _day(range.from); !d.isAfter(range.to); d = DateTime(d.year, d.month, d.day + 1)) {
          final row = flowDay[d] ?? [0, 0];
          flowList.add(NamedValue(Fmt.shortDate(d), r2(row[0]), extra: r2(row[1])));
        }

        List<NamedValue> top(PartyType t) => (_g.db.parties.values.where((p) => p.type == t && p.balance > 0.009).toList()
              ..sort((a, b) => b.balance.compareTo(a.balance)))
            .take(5)
            .map((p) => NamedValue(p.name, p.balance, id: p.id))
            .toList();

        final open = _g.db.openSession;
        return FinancialReport(
          range: range,
          revenue: r2(sales.fold(0.0, (s, i) => s + i.total)),
          salesReturns: r2(saleReturns.fold(0.0, (s, r) => s + r.total)),
          cogs: r2(sales.fold(0.0, (s, i) => s + i.cost) - saleReturns.fold(0.0, (s, r) => s + r.cost)),
          expenses: r2(expenses.fold(0.0, (s, t) => s + t.amount)),
          expensesByCategory: (byCat.entries.map((e) => NamedValue(e.key, r2(e.value))).toList()..sort((a, b) => b.value.compareTo(a.value))),
          customerDebts: r2(_g.db.parties.values.where((p) => p.isCustomer && p.balance > 0).fold(0.0, (s, p) => s + p.balance)),
          supplierDebts: r2(_g.db.parties.values.where((p) => !p.isCustomer && p.balance > 0).fold(0.0, (s, p) => s + p.balance)),
          topDebtors: top(PartyType.customer),
          topCreditors: top(PartyType.supplier),
          cashIn: r2(txs.where((t) => t.isIn).fold(0.0, (s, t) => s + t.amount)),
          cashOut: r2(txs.where((t) => !t.isIn).fold(0.0, (s, t) => s + t.amount)),
          flowByType: flowByType,
          flowByDay: flowList,
          cashBalance: open == null ? _g.engine.lastClosedCash : _g.engine.drawer(open).expected,
          bankBalance: _g.engine.bankBalance,
        );
      });
}

/// Alerts are derived from live data; only the read-state is stored.
class LocalAlertRepository implements AlertRepository {
  LocalAlertRepository(this._g);
  final LocalGateway _g;

  @override
  Future<List<AppAlert>> getAlerts() => _g.read(() {
        final db = _g.db;
        final now = DateTime.now();
        final alerts = <AppAlert>[];
        final read = db.readAlerts;
        DateTime lastMove(String pid) =>
            db.stockMoves.lastWhere((m) => m.productId == pid, orElse: () => StockMovement(id: '', productId: pid, date: now, type: StockMoveType.opening, qty: 0, stockAfter: 0, user: '')).date;

        for (final p in db.products.values.where((p) => p.isActive)) {
          if (p.isOutOfStock) {
            final id = 'out_${p.id}';
            alerts.add(AppAlert(
              id: id,
              kind: AlertKind.outOfStock,
              title: 'نفد مخزون "${p.name}"',
              body: 'الرصيد الحالي ${Fmt.qty(p.stock)} ${p.unit}. أنشئ فاتورة شراء لإعادة التوريد.',
              date: lastMove(p.id),
              severity: AlertSeverity.critical,
              targetId: p.id,
              isRead: read.contains(id),
            ));
          } else if (p.isLowStock) {
            final id = 'low_${p.id}';
            alerts.add(AppAlert(
              id: id,
              kind: AlertKind.lowStock,
              title: 'مخزون منخفض: ${p.name}',
              body: 'المتبقي ${Fmt.qty(p.stock)} ${p.unit} (الحد الأدنى ${Fmt.qty(p.minStock)})',
              date: lastMove(p.id),
              severity: AlertSeverity.warning,
              targetId: p.id,
              isRead: read.contains(id),
            ));
          }
        }

        final dueBefore = now.subtract(Duration(days: db.settings.debtDueDays));
        for (final party in db.parties.values.where((p) => p.hasDebt)) {
          final oldest = (db.invoices.values.where((i) => i.partyId == party.id && i.due > 0.009).toList()
                ..sort((a, b) => a.date.compareTo(b.date)))
              .firstOrNull;
          if (party.isCustomer && party.overLimit) {
            final id = 'limit_${party.id}_${party.balance.round()}';
            alerts.add(AppAlert(
              id: id,
              kind: AlertKind.customerOverLimit,
              title: '${party.name} تجاوز حد الائتمان',
              body: 'الرصيد ${Fmt.money(party.balance)} • الحد ${Fmt.money(party.creditLimit)}',
              date: oldest?.date ?? now,
              severity: AlertSeverity.critical,
              targetId: party.id,
              isRead: read.contains(id),
            ));
          }
          if (oldest != null && oldest.date.isBefore(dueBefore)) {
            final days = now.difference(oldest.date).inDays;
            final id = '${party.isCustomer ? 'cdue' : 'sdue'}_${party.id}_${oldest.id}';
            alerts.add(AppAlert(
              id: id,
              kind: party.isCustomer ? AlertKind.customerDebtDue : AlertKind.supplierPaymentDue,
              title: party.isCustomer ? 'مديونية مستحقة على ${party.name}' : 'مستحق للمورد ${party.name}',
              body: 'فاتورة ${oldest.number} متأخرة $days يوماً • الرصيد الكلي ${Fmt.money(party.balance)}',
              date: oldest.date.add(Duration(days: db.settings.debtDueDays)),
              severity: AlertSeverity.warning,
              targetId: party.id,
              isRead: read.contains(id),
            ));
          }
        }

        for (final t in db.txs.where((t) =>
            t.type == TxType.expense && t.amount >= db.settings.largeExpenseThreshold && now.difference(t.date).inDays < 7)) {
          final id = 'exp_${t.id}';
          alerts.add(AppAlert(
            id: id,
            kind: AlertKind.largeExpense,
            title: 'مصروف كبير: ${Fmt.money(t.amount)}',
            body: '${t.category ?? ''} • ${t.note} • بواسطة ${t.user}',
            date: t.date,
            severity: AlertSeverity.info,
            targetId: t.id,
            isRead: read.contains(id),
          ));
        }

        final open = db.openSession;
        if (open != null) {
          final today = DateTime(now.year, now.month, now.day);
          final stale = open.openedAt.isBefore(today);
          if (stale || now.hour >= db.settings.closingReminderHour) {
            final id = 'close_${open.id}_${stale ? 'stale' : now.day}';
            alerts.add(AppAlert(
              id: id,
              kind: AlertKind.closingReminder,
              title: stale ? 'الوردية مفتوحة منذ ${Fmt.dayLabel(open.openedAt)}' : 'حان وقت إقفال اليومية',
              body: 'قم بجرد الخزنة وإقفال الوردية ${open.number}',
              date: stale ? open.openedAt : today.add(Duration(hours: db.settings.closingReminderHour)),
              severity: stale ? AlertSeverity.critical : AlertSeverity.info,
              targetId: open.id,
              isRead: read.contains(id),
            ));
          }
        }

        alerts.sort((a, b) {
          final s = b.severity.index.compareTo(a.severity.index);
          return s != 0 ? s : b.date.compareTo(a.date);
        });
        return alerts;
      });

  @override
  Future<void> markRead(String id) async {
    _g.db.readAlerts.add(id);
    _g.bus.emit({DataTopic.alerts});
  }

  @override
  Future<void> markAllRead() async {
    final all = await getAlerts();
    _g.db.readAlerts.addAll(all.map((a) => a.id));
    _g.bus.emit({DataTopic.alerts});
  }
}

class LocalSearchRepository implements SearchRepository {
  LocalSearchRepository(this._g);
  final LocalGateway _g;

  @override
  Future<List<SearchHit>> search(String query, SearchScope scope) => _g.read(() {
        final q = query.trim().toLowerCase();
        if (q.isEmpty) return const [];
        final db = _g.db;
        bool want(SearchScope s) => scope == SearchScope.all || scope == s;
        final hits = <SearchHit>[];
        if (want(SearchScope.products)) {
          hits.addAll(db.products.values
              .where((p) => p.name.toLowerCase().contains(q) || p.barcode.contains(q) || p.sku.toLowerCase().contains(q))
              .take(20)
              .map((p) => SearchHit(
                    kind: SearchHitKind.product,
                    id: p.id,
                    title: p.name,
                    subtitle: '${p.sku} • المخزون ${Fmt.qty(p.stock)} ${p.unit}',
                    trailing: Fmt.money(p.sellingPrice),
                  )));
        }
        for (final (scopeFor, type, kind) in [
          (SearchScope.customers, PartyType.customer, SearchHitKind.customer),
          (SearchScope.suppliers, PartyType.supplier, SearchHitKind.supplier),
        ]) {
          if (!want(scopeFor)) continue;
          hits.addAll(db.parties.values
              .where((p) => p.type == type && (p.name.toLowerCase().contains(q) || p.phone.contains(q) || p.company.toLowerCase().contains(q)))
              .take(20)
              .map((p) => SearchHit(
                    kind: kind,
                    id: p.id,
                    title: p.name,
                    subtitle: p.phone.isEmpty ? type.label : p.phone,
                    trailing: p.hasDebt ? Fmt.money(p.balance) : '',
                  )));
        }
        if (want(SearchScope.invoices)) {
          final inv = db.invoices.values
              .where((i) => i.number.toLowerCase().contains(q) || i.partyName.toLowerCase().contains(q))
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
          hits.addAll(inv.take(20).map((i) => SearchHit(
                kind: i.type == InvoiceType.sale ? SearchHitKind.sale : SearchHitKind.purchase,
                id: i.id,
                title: '${i.type.label} ${i.number}',
                subtitle: '${i.partyName} • ${Fmt.relative(i.date)}',
                trailing: Fmt.money(i.total),
              )));
        }
        return hits;
      });

  @override
  Future<List<String>> recentSearches() async => List.of(_g.db.recentSearches);

  @override
  Future<void> addRecent(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    _g.db.recentSearches
      ..remove(q)
      ..insert(0, q);
    if (_g.db.recentSearches.length > 10) _g.db.recentSearches.removeLast();
  }

  @override
  Future<void> removeRecent(String query) async => _g.db.recentSearches.remove(query);

  @override
  Future<void> clearRecent() async => _g.db.recentSearches.clear();
}
