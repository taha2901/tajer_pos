import '../../core/data_bus.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import 'api_client.dart';
import 'json.dart';

/// Shared plumbing for API repositories: change notifications after writes,
/// so every open screen refreshes (same topics as the local implementation).
class ApiGateway {
  ApiGateway(this.api, this.bus);
  final ApiClient api;
  final DataBus bus;

  Future<T> write<T>(Future<T> Function() body, Set<DataTopic> topics) async {
    final result = await body();
    bus.emit({...topics, DataTopic.alerts, DataTopic.search});
    return result;
  }
}

class ApiAuthRepository implements AuthRepository {
  ApiAuthRepository(this._g);
  final ApiGateway _g;
  ApiClient get _api => _g.api;

  Future<AppUser> _signIn(dynamic res) async {
    await _api.setToken(res['token'] as String);
    return userFrom(res['user']);
  }

  @override
  Future<AppUser> login(String username, String pin) async =>
      _signIn(await _api.post('/auth/login', {'username': username, 'pin': pin}));

  @override
  Future<AppUser> register({required String name, required String username, required String email, required String pin}) async =>
      _signIn(await _api.post('/auth/register', {'name': name, 'username': username, 'email': email, 'pin': pin}));

  @override
  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } catch (_) {
      // Sign out locally even if the server can't be reached.
    }
    await _api.setToken(null);
  }

  @override
  Future<AppUser?> currentUser() async {
    if (!_api.hasToken) return null;
    try {
      return userFrom(await _api.get('/auth/me'));
    } catch (_) {
      return null;
    }
  }

  @override
  List<({String username, String pin, String name})> get demoAccounts => const [];
}

class ApiSettingsRepository implements SettingsRepository {
  ApiSettingsRepository(this._g);
  final ApiGateway _g;
  AppSettings _last = const AppSettings();

  @override
  Future<AppSettings> load() async {
    // Before sign-in there is nothing to fetch; don't hold the splash on an unreachable address.
    if (!_g.api.hasToken) return _last;
    try {
      return _last = settingsFrom(await _g.api.get('/settings'), _last);
    } catch (_) {
      // Not signed in yet or server unreachable: start with defaults.
      return _last;
    }
  }

  @override
  Future<AppSettings> save(AppSettings settings) => _g.write(() async {
        return _last = settingsFrom(await _g.api.put('/settings', settingsToJson(settings)), settings);
      }, {DataTopic.settings});

  @override
  Future<void> resetDemoData() => _g.write(() => _g.api.post('/settings/reset-demo'), DataTopic.values.toSet());
}

class ApiProductRepository implements ProductRepository {
  ApiProductRepository(this._g);
  final ApiGateway _g;
  ApiClient get _api => _g.api;

  static const _topics = {DataTopic.products};

  @override
  Future<List<Product>> getProducts([ProductQuery q = const ProductQuery()]) async => listOf(
      await _api.get('/products', {
        'search': q.search,
        'categoryId': q.categoryId,
        'stockFilter': q.stockFilter.name,
        'sort': q.sort.name,
        'includeInactive': q.includeInactive,
      }),
      productFrom);

  @override
  Future<Product> getProduct(String id) async => productFrom(await _api.get('/products/$id'));

  @override
  Future<Product?> findByBarcode(String code) async {
    final res = await _api.get('/products/barcode/${Uri.encodeComponent(code.trim())}');
    return res['product'] == null ? null : productFrom(res['product']);
  }

  @override
  Future<Product> create(ProductInput input) =>
      _g.write(() async => productFrom(await _api.post('/products', productInputToJson(input))), _topics);

  @override
  Future<Product> update(String id, ProductInput input) =>
      _g.write(() async => productFrom(await _api.put('/products/$id', productInputToJson(input))), {..._topics, DataTopic.invoices});

  @override
  Future<void> delete(String id) => _g.write(() => _api.delete('/products/$id'), _topics);

  @override
  Future<Product> setActive(String id, bool active) =>
      _g.write(() async => productFrom(await _api.post('/products/$id/active', {'active': active})), _topics);

  @override
  Future<Product> adjustStock(String id, {required double newStock, required StockAdjustReason reason, String note = ''}) =>
      _g.write(
          () async => productFrom(await _api.post('/products/$id/adjust', {'newStock': newStock, 'reason': reason.name, 'note': note})),
          _topics);

  @override
  Future<List<StockMovement>> getStockMovements(String productId, {StockMoveType? type}) async =>
      listOf(await _api.get('/products/$productId/movements', {'type': type?.name}), movementFrom);

  @override
  Future<ProductStats> getStats(String productId) async => productStatsFrom(await _api.get('/products/$productId/stats'));

  @override
  Future<List<Category>> getCategories() async => listOf(await _api.get('/categories'), categoryFrom);

  @override
  Future<Category> addCategory(String name) =>
      _g.write(() async => categoryFrom(await _api.post('/categories', {'name': name})), _topics);

  @override
  Future<String> generateBarcode() async => (await _api.get('/products/generate/barcode'))['value'] as String;

  @override
  Future<String> generateSku(String categoryId) async => (await _api.get('/products/generate/sku/$categoryId'))['value'] as String;
}

class ApiPartyRepository implements PartyRepository {
  ApiPartyRepository(this._g);
  final ApiGateway _g;
  ApiClient get _api => _g.api;

  static const _topics = {DataTopic.parties};

  @override
  Future<List<Party>> getParties(PartyQuery q) async =>
      listOf(await _api.get('/parties', {'type': q.type.name, 'search': q.search, 'filter': q.filter.name}), partyFrom);

  @override
  Future<Party> getParty(String id) async => partyFrom(await _api.get('/parties/$id'));

  @override
  Future<Party> create(PartyInput input) =>
      _g.write(() async => partyFrom(await _api.post('/parties', partyInputToJson(input))), _topics);

  @override
  Future<Party> update(String id, PartyInput input) =>
      _g.write(() async => partyFrom(await _api.put('/parties/$id', partyInputToJson(input))), _topics);

  @override
  Future<void> delete(String id) => _g.write(() => _api.delete('/parties/$id'), _topics);

  @override
  Future<PartyStats> getStats(String id) async => partyStatsFrom(await _api.get('/parties/$id/stats'));

  @override
  Future<PartyPayment> addPayment(PaymentInput input) => _g.write(
      () async => paymentFrom(await _api.post('/payments', paymentInputToJson(input))), {..._topics, DataTopic.invoices, DataTopic.cash});

  @override
  Future<List<PartyPayment>> getPayments({String? partyId, PartyType? type}) async =>
      listOf(await _api.get('/payments', {'partyId': partyId, 'type': type?.name}), paymentFrom);

  @override
  Future<Party> adjustBalance(String id, {required double amount, required String note}) =>
      _g.write(() async => partyFrom(await _api.post('/parties/$id/adjust', {'amount': amount, 'note': note})), _topics);

  @override
  Future<Statement> getStatement(String id, {DateTime? from, DateTime? to}) async =>
      statementFrom(await _api.get('/parties/$id/statement', {'from': from, 'to': to}));
}

class ApiInvoiceRepository implements InvoiceRepository {
  ApiInvoiceRepository(this._g);
  final ApiGateway _g;
  ApiClient get _api => _g.api;

  static const _topics = {DataTopic.invoices, DataTopic.products, DataTopic.parties, DataTopic.cash};

  @override
  Future<Invoice> create(InvoiceDraft draft) =>
      _g.write(() async => invoiceFrom(await _api.post('/invoices', invoiceDraftToJson(draft))), _topics);

  @override
  Future<List<Invoice>> getInvoices(InvoiceQuery q) async => listOf(
      await _api.get('/invoices', {
        'type': q.type.name,
        'search': q.search,
        'from': q.from,
        'to': q.to,
        'partyId': q.partyId,
        'status': q.status.name,
      }),
      invoiceFrom);

  @override
  Future<Invoice> getInvoice(String id) async => invoiceFrom(await _api.get('/invoices/$id'));

  @override
  Future<ReturnDoc> createReturn(ReturnDraft draft) =>
      _g.write(() async => returnFrom(await _api.post('/returns', returnDraftToJson(draft))), _topics);

  @override
  Future<List<ReturnDoc>> getReturns({InvoiceType? type, String? invoiceId, String? partyId}) async =>
      listOf(await _api.get('/returns', {'type': type?.name, 'invoiceId': invoiceId, 'partyId': partyId}), returnFrom);

  @override
  Future<ReturnDoc> getReturn(String id) async => returnFrom(await _api.get('/returns/$id'));
}

class ApiCashRepository implements CashRepository {
  ApiCashRepository(this._g);
  final ApiGateway _g;
  ApiClient get _api => _g.api;

  static const _topics = {DataTopic.cash};

  @override
  Future<CashOverview> getOverview() async => cashOverviewFrom(await _api.get('/cash/overview'));

  @override
  Future<CashSession?> currentSession() async {
    final res = await _api.get('/cash/session');
    return res['session'] == null ? null : sessionFrom(res['session']);
  }

  @override
  Future<double> suggestedOpening() async => ((await _api.get('/cash/suggested-opening'))['value'] as num).toDouble();

  @override
  Future<CashSession> openSession(double openingBalance) =>
      _g.write(() async => sessionFrom(await _api.post('/cash/open', {'openingBalance': openingBalance})), _topics);

  @override
  Future<CashSession> closeSession({required double countedCash, String note = ''}) =>
      _g.write(() async => sessionFrom(await _api.post('/cash/close', {'countedCash': countedCash, 'note': note})), _topics);

  @override
  Future<DrawerSummary> getSessionSummary(String sessionId) async => drawerFrom(await _api.get('/cash/sessions/$sessionId/summary'));

  @override
  Future<MoneyTx> addTransaction(MoneyTxInput input) =>
      _g.write(() async => txFrom(await _api.post('/cash/transactions', txInputToJson(input))), _topics);

  @override
  Future<List<MoneyTx>> getTransactions(TxQuery q) async => listOf(
      await _api.get('/cash/transactions', {
        'account': q.account?.name,
        'type': q.type?.name,
        'from': q.from,
        'to': q.to,
        'sessionId': q.sessionId,
        'search': q.search,
      }),
      txFrom);

  @override
  Future<List<CashSession>> getSessions() async => listOf(await _api.get('/cash/sessions'), sessionFrom);
}

class ApiReportRepository implements ReportRepository {
  ApiReportRepository(this._g);
  final ApiGateway _g;
  ApiClient get _api => _g.api;

  @override
  Future<DashboardData> getDashboard() async => dashboardFrom(await _api.get('/reports/dashboard'));

  @override
  Future<TradeReport> getTradeReport(InvoiceType type, TradeReportFilter f) async => tradeReportFrom(await _api.get('/reports/trade/${type.name}', {
        'from': f.range.from,
        'to': f.range.to,
        'partyId': f.partyId,
        'productId': f.productId,
        'categoryId': f.categoryId,
      }));

  @override
  Future<StockReport> getStockReport({DateRange? movementRange, String? productId, String? categoryId}) async =>
      stockReportFrom(await _api.get('/reports/stock', {
        'from': movementRange?.from,
        'to': movementRange?.to,
        'productId': productId,
        'categoryId': categoryId,
      }));

  @override
  Future<FinancialReport> getFinancialReport(DateRange range) async =>
      financialReportFrom(await _api.get('/reports/financial', {'from': range.from, 'to': range.to}), range);
}

class ApiAlertRepository implements AlertRepository {
  ApiAlertRepository(this._g);
  final ApiGateway _g;

  @override
  Future<List<AppAlert>> getAlerts() async => listOf(await _g.api.get('/alerts'), alertFrom);

  @override
  Future<void> markRead(String id) async {
    await _g.api.post('/alerts/${Uri.encodeComponent(id)}/read');
    _g.bus.emit({DataTopic.alerts});
  }

  @override
  Future<void> markAllRead() async {
    await _g.api.post('/alerts/read-all');
    _g.bus.emit({DataTopic.alerts});
  }
}

class ApiSearchRepository implements SearchRepository {
  ApiSearchRepository(this._g);
  final ApiGateway _g;
  ApiClient get _api => _g.api;

  @override
  Future<List<SearchHit>> search(String query, SearchScope scope) async {
    if (query.trim().isEmpty) return const [];
    return listOf(await _api.get('/search', {'q': query, 'scope': scope.name}), searchHitFrom);
  }

  @override
  Future<List<String>> recentSearches() async => List<String>.from(await _api.get('/search/recent') as List);

  @override
  Future<void> addRecent(String query) => _api.post('/search/recent', {'query': query});

  @override
  Future<void> removeRecent(String query) => _api.post('/search/recent/remove', {'query': query});

  @override
  Future<void> clearRecent() => _api.delete('/search/recent');
}
