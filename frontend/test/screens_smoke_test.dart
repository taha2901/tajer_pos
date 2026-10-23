import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tajer/app/app.dart';
import 'package:tajer/app/di.dart';
import 'package:tajer/domain/models/models.dart';
import 'package:tajer/features/cash/cash_screen.dart';
import 'package:tajer/features/cash/daily_closing_screen.dart';
import 'package:tajer/features/cash/transactions_screen.dart';
import 'package:tajer/features/invoices/invoice_details_screen.dart';
import 'package:tajer/features/invoices/invoices_list_screen.dart';
import 'package:tajer/features/invoices/receipt_screen.dart';
import 'package:tajer/features/invoices/return_screen.dart';
import 'package:tajer/features/notifications/notifications_screen.dart';
import 'package:tajer/features/parties/parties_screen.dart';
import 'package:tajer/features/parties/party_details_screen.dart';
import 'package:tajer/features/parties/party_form_screen.dart';
import 'package:tajer/features/parties/party_payment_screen.dart';
import 'package:tajer/features/parties/statement_screen.dart';
import 'package:tajer/features/pos/cart_cubit.dart';
import 'package:tajer/features/pos/cart_screen.dart';
import 'package:tajer/features/pos/checkout_screen.dart';
import 'package:tajer/features/products/product_details_screen.dart';
import 'package:tajer/features/products/product_form_screen.dart';
import 'package:tajer/features/products/stock_history_screen.dart';
import 'package:tajer/features/purchases/purchase_form_screen.dart';
import 'package:tajer/features/reports/financial_report_screen.dart';
import 'package:tajer/features/reports/reports_screen.dart';
import 'package:tajer/features/reports/stock_report_screen.dart';
import 'package:tajer/features/reports/trade_report_screen.dart';
import 'package:tajer/features/settings/settings_screen.dart';
import 'package:tajer/features/shell/home_shell.dart';

/// Opens every screen on a phone-sized surface with seeded data and fails on
/// any exception (layout overflow, null errors, provider lookups...).
void main() {
  testWidgets('every screen renders without errors', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final deps = AppDependencies.local();
    await tester.pumpWidget(TajerApp(deps: deps));
    await _settle(tester);

    // Login as admin via the demo account card.
    await tester.tap(find.text('أحمد المدير'));
    await _settle(tester);
    expect(find.byType(HomeShell), findsOneWidget);

    // Bottom tabs.
    for (final label in ['البيع', 'المنتجات', 'العملاء', 'المزيد', 'الرئيسية']) {
      await tester.tap(find.text(label).last);
      await _settle(tester);
    }

    final products = await deps.products.getProducts();
    final product = products.firstWhere((p) => p.stock > 5);
    final customers = await deps.parties.getParties(const PartyQuery(PartyType.customer));
    final debtor = customers.firstWhere((c) => c.hasDebt, orElse: () => customers.first);
    final suppliers = await deps.parties.getParties(const PartyQuery(PartyType.supplier));
    final sales = await deps.invoices.getInvoices(const InvoiceQuery(InvoiceType.sale));
    final purchases = await deps.invoices.getInvoices(const InvoiceQuery(InvoiceType.purchase));
    final sessions = await deps.cash.getSessions();

    // Put something in the cart for cart / checkout.
    final ctx = tester.element(find.byType(HomeShell));
    ctx.read<CartCubit>().add(product, qty: 2);

    final screens = <String, Widget>{
      'product details': ProductDetailsScreen(productId: product.id),
      'stock history': StockHistoryScreen(product: product),
      'product form (add)': const ProductFormScreen(),
      'product form (edit)': ProductFormScreen(product: product),
      'customers': const PartiesScreen(type: PartyType.customer),
      'suppliers': const PartiesScreen(type: PartyType.supplier),
      'customer details': PartyDetailsScreen(partyId: debtor.id),
      'supplier details': PartyDetailsScreen(partyId: suppliers.first.id),
      'party form': const PartyFormScreen(type: PartyType.supplier),
      'statement': StatementScreen(partyId: debtor.id),
      'payment': PartyPaymentScreen(partyId: debtor.id),
      'sales list': const InvoicesListScreen(type: InvoiceType.sale),
      'purchases list': const InvoicesListScreen(type: InvoiceType.purchase),
      'sale details': InvoiceDetailsScreen(invoiceId: sales.first.id),
      'purchase details': InvoiceDetailsScreen(invoiceId: purchases.first.id),
      'receipt': ReceiptScreen(invoice: sales.first, change: 15, justCreated: true),
      'sale return': ReturnScreen(invoiceId: sales.first.id),
      'purchase return': ReturnScreen(invoiceId: purchases.first.id),
      'purchase form': PurchaseFormScreen(product: product),
      'cash': const CashScreen(),
      'transactions': const TransactionsScreen(),
      'expenses': const TransactionsScreen(type: TxType.expense),
      'daily closing': const DailyClosingScreen(),
      'session report': SessionReportScreen(sessionId: sessions.last.id),
      'reports': const ReportsScreen(),
      'sales report': const TradeReportScreen(type: InvoiceType.sale),
      'sales by product': const TradeReportScreen(type: InvoiceType.sale, initialGroup: 4),
      'purchases report': const TradeReportScreen(type: InvoiceType.purchase),
      'stock report': const StockReportScreen(),
      'financial report': const FinancialReportScreen(),
      'notifications': const NotificationsScreen(),
      'settings': const SettingsScreen(),
      'cart': const CartScreen(),
      'checkout': const CheckoutScreen(),
    };

    final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
    for (final e in screens.entries) {
      navigator.push(MaterialPageRoute<void>(builder: (_) => e.value));
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: e.key);
      navigator.pop();
      await _settle(tester);
    }
  });
}

/// Like pumpAndSettle but tolerant of indefinite animations (spinners).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}
