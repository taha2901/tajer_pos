// End-to-end check against a running backend: `flutter test test/api_e2e_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tajer/app/di.dart';
import 'package:tajer/data/remote/api_client.dart';
import 'package:tajer/domain/models/models.dart';

void main() {
  test('all repositories work against the server', () async {
    SharedPreferences.setMockInitialValues({'server_url': 'http://127.0.0.1:3000/api'});
    final d = AppDependencies.remote(ApiClient(await SharedPreferences.getInstance()));
    final user = await d.auth.login('admin', '1234');
    expect(user.username, 'admin');
    expect((await d.auth.currentUser())?.id, user.id);
    final st = await d.settings.load();
    await d.settings.save(st.copyWith(storeName: st.storeName));

    final dash = await d.reports.getDashboard();
    expect(dash.salesByDay.length, 7);
    final products = await d.products.getProducts();
    expect(products, isNotEmpty);
    final cats = await d.products.getCategories();
    final p = products.firstWhere((p) => p.stock > 5);
    await d.products.getProduct(p.id);
    expect((await d.products.findByBarcode(p.barcode))?.id, p.id);
    await d.products.getStats(p.id);
    await d.products.getStockMovements(p.id);
    final sku = await d.products.generateSku(cats.first.id);
    final bc = await d.products.generateBarcode();
    final np = await d.products.create(ProductInput(name: 'منتج اختبار ${DateTime.now().millisecondsSinceEpoch}', barcode: bc, sku: sku, categoryId: cats.first.id, unit: 'قطعة', purchasePrice: 5, sellingPrice: 8, wholesalePrice: 0, halfWholesalePrice: 0, minStock: 1, openingStock: 10));
    await d.products.setActive(np.id, false);
    await d.products.delete(np.id);
    await d.products.adjustStock(p.id, newStock: p.stock + 1, reason: StockAdjustReason.count);

    final customers = await d.parties.getParties(const PartyQuery(PartyType.customer));
    final c = customers.first;
    await d.parties.getStats(c.id);
    await d.parties.getStatement(c.id, from: DateTime.now().subtract(const Duration(days: 10)), to: DateTime.now());
    await d.parties.getPayments(partyId: c.id);

    if (await d.cash.currentSession() == null) await d.cash.openSession(await d.cash.suggestedOpening());
    final inv = await d.invoices.create(InvoiceDraft(type: InvoiceType.sale, partyId: c.id, lines: [DraftLine(productId: p.id, qty: 2, unitPrice: p.sellingPrice)], payments: [PaymentLine(PaymentMethod.cash, p.sellingPrice * 2)]));
    expect(inv.total, p.sellingPrice * 2);
    expect((await d.invoices.getInvoice(inv.id)).number, inv.number);
    final ret = await d.invoices.createReturn(ReturnDraft(invoiceId: inv.id, qtyByProduct: {p.id: 1}));
    await d.invoices.getReturn(ret.id);
    await d.invoices.getReturns(invoiceId: inv.id);
    expect(await d.invoices.getInvoices(InvoiceQuery(InvoiceType.sale, from: DateTime.now().subtract(const Duration(days: 1)))), isNotEmpty);

    final ov = await d.cash.getOverview();
    expect(ov.drawer, isNotNull);
    await d.cash.addTransaction(const MoneyTxInput(type: TxType.cashIn, amount: 10));
    await d.cash.getTransactions(const TxQuery());
    await d.cash.getSessionSummary(ov.drawer!.session.id);
    await d.cash.getSessions();

    await d.reports.getTradeReport(InvoiceType.sale, TradeReportFilter(range: DateRange.lastDays(7)));
    await d.reports.getTradeReport(InvoiceType.purchase, TradeReportFilter(range: DateRange.thisMonth()));
    await d.reports.getStockReport();
    await d.reports.getFinancialReport(DateRange.thisMonth());

    final alerts = await d.alerts.getAlerts();
    if (alerts.isNotEmpty) await d.alerts.markRead(alerts.first.id);
    await d.alerts.markAllRead();
    expect(await d.search.search('ب', SearchScope.all), isNotEmpty);
    await d.search.addRecent('بيبسي');
    expect(await d.search.recentSearches(), contains('بيبسي'));
    await d.search.removeRecent('بيبسي');
    await d.search.clearRecent();
    await d.auth.logout();
    expect(await d.auth.currentUser(), isNull);
  });
}
