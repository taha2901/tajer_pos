import 'package:flutter_test/flutter_test.dart';
import 'package:tajer/core/errors.dart';
import 'package:tajer/data/local/local_store.dart';
import 'package:tajer/data/local/pos_engine.dart';
import 'package:tajer/data/local/seeder.dart';
import 'package:tajer/domain/models/models.dart';

void main() {
  late LocalStore db;
  late PosEngine engine;
  late Category cat;

  Product product({double cost = 50, double price = 100, double stock = 100}) => engine.createProduct(ProductInput(
        name: 'منتج ${db.products.length + 1}',
        barcode: '',
        sku: '',
        categoryId: cat.id,
        unit: 'قطعة',
        purchasePrice: cost,
        sellingPrice: price,
        wholesalePrice: 0,
        halfWholesalePrice: 0,
        minStock: 5,
        openingStock: stock,
      ));

  Party customer({double limit = 0}) =>
      engine.createParty(PartyInput(type: PartyType.customer, name: 'عميل', creditLimit: limit));
  Party supplier() => engine.createParty(const PartyInput(type: PartyType.supplier, name: 'مورد'));

  double drawer() => engine.drawer(db.openSession!).expected;

  setUp(() {
    db = LocalStore()..currentUser = demoUsers.first;
    engine = PosEngine(db);
    cat = engine.addCategory('عام');
  });

  group('Brief scenarios', () {
    test('credit sale 10,000 paid 4,000 → debt 6,000; payment 2,000 → 4,000', () {
      engine.openSession(0);
      final p = product(price: 1000, stock: 50);
      final c = customer();
      final inv = engine.createInvoice(InvoiceDraft(
        type: InvoiceType.sale,
        partyId: c.id,
        lines: [DraftLine(productId: p.id, qty: 10, unitPrice: 1000)],
        payments: const [PaymentLine(PaymentMethod.cash, 4000)],
      ));
      expect(inv.total, 10000);
      expect(inv.due, 6000);
      expect(db.parties[c.id]!.balance, 6000);
      expect(db.products[p.id]!.stock, 40, reason: 'sale decreases stock');
      expect(drawer(), 4000, reason: 'only the paid cash enters the drawer');

      final pay = engine.addPayment(PaymentInput(partyId: c.id, amount: 2000, method: PaymentMethod.cash));
      expect(pay.balanceBefore, 6000);
      expect(pay.balanceAfter, 4000);
      expect(db.invoices[inv.id]!.due, 4000, reason: 'payment allocated to the invoice');
      expect(drawer(), 6000);
    });

    test('mixed payment: 10,000 total, 6,000 cash → 4,000 credit', () {
      engine.openSession(0);
      final p = product(price: 1000, stock: 20);
      final c = customer();
      final inv = engine.createInvoice(InvoiceDraft(
        type: InvoiceType.sale,
        partyId: c.id,
        lines: [DraftLine(productId: p.id, qty: 10, unitPrice: 1000)],
        payments: const [PaymentLine(PaymentMethod.cash, 6000)],
      ));
      expect(inv.paid, 6000);
      expect(inv.due, 4000);
      expect(db.parties[c.id]!.balance, 4000);
      expect(drawer(), 6000);
    });

    test('purchase 20,000 paid 5,000 → payable 15,000; pay 5,000 → 10,000', () {
      final p = product(cost: 100, stock: 0);
      final s = supplier();
      engine.createInvoice(InvoiceDraft(
        type: InvoiceType.purchase,
        partyId: s.id,
        lines: [DraftLine(productId: p.id, qty: 200, unitPrice: 100)],
        payments: const [PaymentLine(PaymentMethod.bank, 5000)],
      ));
      expect(db.parties[s.id]!.balance, 15000);
      expect(db.products[p.id]!.stock, 200, reason: 'purchase increases stock');
      engine.addPayment(PaymentInput(partyId: s.id, amount: 5000, method: PaymentMethod.bank));
      expect(db.parties[s.id]!.balance, 10000);
    });

    test('drawer: 5,000 + 10,000 sales + 2,000 collections − 1,000 expense − 3,000 supplier = 13,000', () {
      engine.openSession(5000);
      final p = product(price: 1000, stock: 100);
      final c = customer();
      final s = supplier();
      engine.createInvoice(InvoiceDraft(
        type: InvoiceType.sale,
        lines: [DraftLine(productId: p.id, qty: 10, unitPrice: 1000)],
        payments: const [PaymentLine(PaymentMethod.cash, 10000)],
      ));
      engine.adjustBalance(c.id, 2000, 'رصيد سابق');
      engine.addPayment(PaymentInput(partyId: c.id, amount: 2000, method: PaymentMethod.cash));
      engine.addManualTx(const MoneyTxInput(type: TxType.expense, amount: 1000, category: 'كهرباء ومياه'));
      engine.adjustBalance(s.id, 3000, 'رصيد سابق');
      engine.addPayment(PaymentInput(partyId: s.id, amount: 3000, method: PaymentMethod.cash));
      expect(drawer(), 13000);
      final closed = engine.closeSession(12990, 'عجز');
      expect(closed.expectedCash, 13000);
      expect(closed.difference, -10);
    });
  });

  group('Returns', () {
    test('sale return reduces the due first, then refunds cash', () {
      engine.openSession(1000);
      final p = product(price: 100, stock: 10);
      final c = customer();
      final inv = engine.createInvoice(InvoiceDraft(
        type: InvoiceType.sale,
        partyId: c.id,
        lines: [DraftLine(productId: p.id, qty: 10, unitPrice: 100)],
        payments: const [PaymentLine(PaymentMethod.cash, 700)],
      ));
      expect(db.parties[c.id]!.balance, 300);

      final r = engine.createReturn(ReturnDraft(invoiceId: inv.id, qtyByProduct: {p.id: 5}));
      expect(r.total, 500);
      expect(r.creditApplied, 300);
      expect(r.cashRefund, 200);
      expect(db.parties[c.id]!.balance, 0);
      expect(db.invoices[inv.id]!.due, 0);
      expect(db.products[p.id]!.stock, 5, reason: 'returned goods go back to stock');
      expect(drawer(), 1000 + 700 - 200);
    });

    test('return honours invoice discount and blocks over-return', () {
      engine.openSession(0);
      final p = product(price: 100, stock: 10);
      final inv = engine.createInvoice(InvoiceDraft(
        type: InvoiceType.sale,
        lines: [DraftLine(productId: p.id, qty: 4, unitPrice: 100)],
        discount: 40,
        payments: const [PaymentLine(PaymentMethod.cash, 360)],
      ));
      final r = engine.createReturn(ReturnDraft(invoiceId: inv.id, qtyByProduct: {p.id: 1}));
      expect(r.total, 90, reason: '10% invoice discount shared pro rata');
      expect(
        () => engine.createReturn(ReturnDraft(invoiceId: inv.id, qtyByProduct: {p.id: 4})),
        throwsA(isA<BusinessException>()),
      );
    });

    test('purchase return decreases stock and payable', () {
      final p = product(cost: 10, stock: 0);
      final s = supplier();
      final inv = engine.createInvoice(InvoiceDraft(
        type: InvoiceType.purchase,
        partyId: s.id,
        lines: [DraftLine(productId: p.id, qty: 100, unitPrice: 10)],
        payments: const [],
      ));
      engine.createReturn(ReturnDraft(invoiceId: inv.id, qtyByProduct: {p.id: 20}));
      expect(db.products[p.id]!.stock, 80);
      expect(db.parties[s.id]!.balance, 800);
    });
  });

  group('Rules', () {
    test('walk-in customers cannot buy on credit', () {
      final p = product();
      expect(
        () => engine.createInvoice(InvoiceDraft(type: InvoiceType.sale, lines: [DraftLine(productId: p.id, qty: 1, unitPrice: 100)], payments: const [])),
        throwsA(isA<BusinessException>()),
      );
    });

    test('credit limit blocks unless overridden', () {
      final p = product();
      final c = customer(limit: 500);
      InvoiceDraft draft({bool override = false}) => InvoiceDraft(
            type: InvoiceType.sale,
            partyId: c.id,
            lines: [DraftLine(productId: p.id, qty: 6, unitPrice: 100)],
            payments: const [],
            overrideCreditLimit: override,
          );
      expect(() => engine.createInvoice(draft()), throwsA(predicate((e) => e is BusinessException && e.code == ErrorCodes.creditLimit)));
      expect(engine.createInvoice(draft(override: true)).due, 600);
    });

    test('cannot sell more than stock; cash needs an open drawer', () {
      final p = product(stock: 2);
      expect(
        () => engine.createInvoice(InvoiceDraft(type: InvoiceType.sale, lines: [DraftLine(productId: p.id, qty: 3, unitPrice: 100)], payments: const [PaymentLine(PaymentMethod.cash, 300)])),
        throwsA(predicate((e) => e is BusinessException && e.code == ErrorCodes.insufficientStock)),
      );
      expect(
        () => engine.createInvoice(InvoiceDraft(type: InvoiceType.sale, lines: [DraftLine(productId: p.id, qty: 1, unitPrice: 100)], payments: const [PaymentLine(PaymentMethod.cash, 100)])),
        throwsA(predicate((e) => e is BusinessException && e.code == ErrorCodes.drawerClosed)),
      );
    });

    test('cannot pay out more cash than the drawer holds', () {
      engine.openSession(100);
      expect(
        () => engine.addManualTx(const MoneyTxInput(type: TxType.expense, amount: 500, category: 'أخرى')),
        throwsA(predicate((e) => e is BusinessException && e.code == ErrorCodes.insufficientCash)),
      );
    });

    test('product with sales cannot be deleted', () {
      engine.openSession(0);
      final p = product();
      engine.createInvoice(InvoiceDraft(type: InvoiceType.sale, lines: [DraftLine(productId: p.id, qty: 1, unitPrice: 100)], payments: const [PaymentLine(PaymentMethod.cash, 100)]));
      expect(() => engine.deleteProduct(p.id), throwsA(predicate((e) => e is BusinessException && e.code == ErrorCodes.hasTransactions)));
    });
  });

  test('seeded demo data is internally consistent', () {
    Seeder(db, engine).run();
    expect(db.invoices.length, greaterThan(150));
    expect(db.openSession, isNotNull, reason: 'today stays open');

    // Stock equals the sum of its movements.
    for (final p in db.products.values) {
      final sum = db.stockMoves.where((m) => m.productId == p.id).fold(0.0, (s, m) => s + m.qty);
      expect(p.stock, closeTo(sum, 0.001), reason: p.name);
      expect(p.stock, greaterThanOrEqualTo(0), reason: p.name);
    }
    // Balances equal the ledger and the sum of open invoice dues.
    for (final party in db.parties.values) {
      final entries = db.ledger.where((e) => e.partyId == party.id);
      final net = entries.fold(0.0, (s, e) => s + (party.isCustomer ? e.debit - e.credit : e.credit - e.debit));
      expect(party.balance, closeTo(net, 0.01), reason: party.name);
      final dues = db.invoices.values.where((i) => i.partyId == party.id).fold(0.0, (s, i) => s + i.due);
      expect(party.balance, closeTo(dues, 0.01), reason: '${party.name} dues');
    }
    // Closed sessions: expected = opening + in − out, and the next opening carries the count.
    final sessions = db.sessions;
    for (var i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      if (s.isOpen) continue;
      expect(s.expectedCash, closeTo(engine.drawer(s).expected, 0.01));
      if (i + 1 < sessions.length) expect(sessions[i + 1].openingBalance, s.countedCash);
    }
  });
}
