// Repository contracts. The UI depends only on these.
//
// Today they're implemented by `data/local/*` (in-memory + PosEngine).
// To connect a backend, implement them with API calls and swap the bindings
// in `app/di.dart` — no screen or cubit needs to change.

import '../models/models.dart';

abstract interface class AuthRepository {
  Future<AppUser> login(String username, String pin);
  Future<void> logout();
  Future<AppUser?> currentUser();

  /// Creates a new account and signs it in.
  Future<AppUser> register({required String name, required String username, required String email, required String pin});

  /// Demo accounts shown on the login screen.
  List<({String username, String pin, String name})> get demoAccounts;
}

abstract interface class SettingsRepository {
  Future<AppSettings> load();
  Future<AppSettings> save(AppSettings settings);
  Future<void> resetDemoData();
}

abstract interface class ProductRepository {
  Future<List<Product>> getProducts([ProductQuery query = const ProductQuery()]);
  Future<Product> getProduct(String id);
  Future<Product?> findByBarcode(String code);
  Future<Product> create(ProductInput input);
  Future<Product> update(String id, ProductInput input);

  /// Throws [BusinessException] if the product has transactions — deactivate instead.
  Future<void> delete(String id);
  Future<Product> setActive(String id, bool active);
  Future<Product> adjustStock(String id, {required double newStock, required StockAdjustReason reason, String note = ''});
  Future<List<StockMovement>> getStockMovements(String productId, {StockMoveType? type});
  Future<ProductStats> getStats(String productId);
  Future<List<Category>> getCategories();
  Future<Category> addCategory(String name);
  Future<String> generateBarcode();
  Future<String> generateSku(String categoryId);
}

abstract interface class PartyRepository {
  Future<List<Party>> getParties(PartyQuery query);
  Future<Party> getParty(String id);
  Future<Party> create(PartyInput input);
  Future<Party> update(String id, PartyInput input);
  Future<void> delete(String id);
  Future<PartyStats> getStats(String id);

  /// Receipt from a customer or payment to a supplier.
  Future<PartyPayment> addPayment(PaymentInput input);
  Future<List<PartyPayment>> getPayments({String? partyId, PartyType? type});
  Future<Party> adjustBalance(String id, {required double amount, required String note});
  Future<Statement> getStatement(String id, {DateTime? from, DateTime? to});
}

abstract interface class InvoiceRepository {
  Future<Invoice> create(InvoiceDraft draft);
  Future<List<Invoice>> getInvoices(InvoiceQuery query);
  Future<Invoice> getInvoice(String id);
  Future<Invoice> setFeedback(String invoiceId, {required int rating, required String feedback});
  Future<ReturnDoc> createReturn(ReturnDraft draft);
  Future<List<ReturnDoc>> getReturns({InvoiceType? type, String? invoiceId, String? partyId});
  Future<ReturnDoc> getReturn(String id);
}

abstract interface class CashRepository {
  Future<CashOverview> getOverview();
  Future<CashSession?> currentSession();
  Future<double> suggestedOpening();
  Future<CashSession> openSession(double openingBalance);
  Future<CashSession> closeSession({required double countedCash, String note = ''});
  Future<DrawerSummary> getSessionSummary(String sessionId);
  Future<MoneyTx> addTransaction(MoneyTxInput input);
  Future<List<MoneyTx>> getTransactions(TxQuery query);
  Future<List<CashSession>> getSessions();
}

abstract interface class ReportRepository {
  Future<DashboardData> getDashboard();
  Future<TradeReport> getTradeReport(InvoiceType type, TradeReportFilter filter);
  Future<StockReport> getStockReport({DateRange? movementRange, String? productId, String? categoryId});
  Future<FinancialReport> getFinancialReport(DateRange range);
}

abstract interface class AlertRepository {
  Future<List<AppAlert>> getAlerts();
  Future<void> markRead(String id);
  Future<void> markAllRead();
}

abstract interface class SearchRepository {
  Future<List<SearchHit>> search(String query, SearchScope scope);
  Future<List<String>> recentSearches();
  Future<void> addRecent(String query);
  Future<void> removeRecent(String query);
  Future<void> clearRecent();
}
