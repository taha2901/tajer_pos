import 'dart:math';

import '../../domain/models/models.dart';
import 'local_store.dart';
import 'pos_engine.dart';

const demoUsers = [
  AppUser(id: 'u1', name: 'أحمد', username: 'admin'),
  AppUser(id: 'u2', name: 'سارة', username: 'cashier'),
];
const demoPins = {'admin': '1234', 'cashier': '0000'};

/// Builds a realistic, internally consistent dataset by replaying ~30 days of
/// operations through [PosEngine] (so balances, stock and drawer all agree).
class Seeder {
  Seeder(this.db, this.engine);

  final LocalStore db;
  final PosEngine engine;
  final _rnd = Random(7);

  void run() {
    final keepSettings = db.settings;
    db.clear();
    db.settings = keepSettings.copyWith(allowNegativeStock: false);
    final start = DateTime.now().subtract(const Duration(days: 30));
    final t0 = DateTime(start.year, start.month, start.day, 8);
    db.currentUser = demoUsers.first;

    _catalog(t0);
    _parties(t0);
    _history();
    _finalTouches();

    db.settings = keepSettings;
    db.currentUser = null;
  }

  // ─────────────────────────── Catalog ───────────────────────────

  final _bySupplierCat = <String, String>{};

  void _catalog(DateTime at) {
    final cats = ['مشروبات', 'ألبان وأجبان', 'بقالة جافة', 'معلبات', 'منظفات', 'حلويات وسناكس', 'عناية شخصية']
        .map(engine.addCategory)
        .toList();

    // name, category index, unit, cost, price, min, opening
    const items = [
      ('بيبسي 1 لتر', 0, 'زجاجة', 17.0, 22.0, 24.0, 120.0),
      ('كوكاكولا كانز 330 مل', 0, 'علبة', 9.0, 12.0, 24.0, 96.0),
      ('مياه معدنية 1.5 لتر', 0, 'زجاجة', 6.0, 8.0, 36.0, 200.0),
      ('عصير مانجو 1 لتر', 0, 'علبة', 28.0, 35.0, 12.0, 60.0),
      ('شاي العروسة 250 جم', 0, 'باكو', 38.0, 48.0, 15.0, 80.0),
      ('نسكافيه كلاسيك 50 جم', 0, 'علبة', 62.0, 78.0, 10.0, 30.0),
      ('لبن كامل الدسم 1 لتر', 1, 'علبة', 34.0, 40.0, 20.0, 90.0),
      ('جبنة فيتا 500 جم', 1, 'علبة', 42.0, 52.0, 12.0, 50.0),
      ('زبادي طبيعي', 1, 'علبة', 7.0, 9.0, 30.0, 120.0),
      ('زبدة 200 جم', 1, 'قطعة', 105.0, 125.0, 8.0, 18.0),
      ('أرز مصري 1 كجم', 2, 'كيلو', 30.0, 36.0, 25.0, 150.0),
      ('سكر أبيض 1 كجم', 2, 'كيلو', 28.0, 33.0, 25.0, 150.0),
      ('زيت عباد الشمس 1 لتر', 2, 'زجاجة', 70.0, 82.0, 15.0, 70.0),
      ('مكرونة 400 جم', 2, 'باكو', 13.0, 16.0, 30.0, 160.0),
      ('دقيق فاخر 1 كجم', 2, 'كيلو', 22.0, 27.0, 15.0, 60.0),
      ('عدس أصفر 1 كجم', 2, 'كيلو', 48.0, 58.0, 10.0, 40.0),
      ('تونة قطع 140 جم', 3, 'علبة', 42.0, 52.0, 15.0, 70.0),
      ('فول مدمس 400 جم', 3, 'علبة', 16.0, 20.0, 20.0, 90.0),
      ('صلصة طماطم 320 جم', 3, 'علبة', 18.0, 23.0, 15.0, 70.0),
      ('سردين بالزيت', 3, 'علبة', 25.0, 32.0, 10.0, 22.0),
      ('سائل أطباق 650 مل', 4, 'زجاجة', 33.0, 40.0, 10.0, 45.0),
      ('مسحوق غسيل أوتوماتيك 1 كجم', 4, 'باكو', 85.0, 105.0, 8.0, 35.0),
      ('كلور 1 لتر', 4, 'زجاجة', 22.0, 28.0, 10.0, 40.0),
      ('مناديل 10 باكو', 4, 'كرتونة', 55.0, 68.0, 6.0, 25.0),
      ('شيبس عائلي', 5, 'كيس', 9.0, 12.0, 30.0, 140.0),
      ('كرواسون محشو', 5, 'قطعة', 8.0, 10.0, 30.0, 120.0),
      ('بسكويت سادة', 5, 'باكو', 4.0, 5.0, 40.0, 200.0),
      ('شوكولاتة بالحليب', 5, 'قطعة', 22.0, 28.0, 15.0, 60.0),
      ('صابون 120 جم', 6, 'قطعة', 18.0, 23.0, 15.0, 60.0),
      ('شامبو 400 مل', 6, 'زجاجة', 95.0, 115.0, 6.0, 14.0),
      ('معجون أسنان 100 مل', 6, 'أنبوبة', 35.0, 43.0, 10.0, 40.0),
    ];

    for (final (name, cat, unit, cost, price, min, opening) in items) {
      final margin = price - cost;
      engine.createProduct(
        ProductInput(
          name: name,
          barcode: '',
          sku: '',
          categoryId: cats[cat].id,
          unit: unit,
          purchasePrice: cost,
          sellingPrice: price,
          wholesalePrice: (cost + margin * 0.4).roundToDouble(),
          halfWholesalePrice: (cost + margin * 0.7).roundToDouble(),
          minStock: min,
          openingStock: opening,
          description: '',
        ),
        at: at,
      );
    }
  }

  void _parties(DateTime at) {
    const customers = [
      ('محمد عبد الله', '01012345678', 'مدينة نصر - الحي السابع', PriceTier.retail, 3000.0),
      ('سوبر ماركت النور', '01123456789', 'شارع مكرم عبيد', PriceTier.wholesale, 30000.0),
      ('أحمد حسن', '01234567890', 'الحي العاشر', PriceTier.retail, 2000.0),
      ('كافيتريا الصفا', '01098765432', 'شارع الطيران', PriceTier.halfWholesale, 10000.0),
      ('منى إبراهيم', '01187654321', 'عمارات العبور', PriceTier.retail, 1500.0),
      ('مطعم أبو علي', '01276543210', 'شارع عباس العقاد', PriceTier.wholesale, 20000.0),
      ('محمود السيد', '01065432109', 'الحي الثامن', PriceTier.retail, 0.0),
      ('بقالة الأمل', '01154321098', 'المنطقة السادسة', PriceTier.halfWholesale, 8000.0),
      ('ياسر فتحي', '01243210987', 'زهراء مدينة نصر', PriceTier.retail, 2500.0),
      ('هالة مصطفى', '01032109876', 'شارع يوسف عباس', PriceTier.retail, 1000.0),
    ];
    for (final (name, phone, addr, tier, limit) in customers) {
      engine.createParty(
        PartyInput(type: PartyType.customer, name: name, phone: phone, address: addr, priceTier: tier, creditLimit: limit),
        at: at,
      );
    }

    const suppliers = [
      ('شركة النيل للتوزيع', 'النيل للتجارة والتوزيع', '0223456789', 'العبور - المنطقة الصناعية', [0, 3]),
      ('موزع الألبان المتحد', 'المتحدة للألبان', '0224567890', 'مدينة السادس من أكتوبر', [1]),
      ('مؤسسة الفجر للمواد الغذائية', 'الفجر للأغذية', '0225678901', 'روض الفرج', [2]),
      ('الشركة المصرية للمنظفات', 'المصرية للمنظفات', '0226789012', 'العاشر من رمضان', [4, 6]),
      ('مصنع الأمل للسناكس', 'الأمل للصناعات الغذائية', '0227890123', 'مدينة بدر', [5]),
    ];
    final catIds = db.categories.keys.toList();
    for (final (name, company, phone, addr, cats) in suppliers) {
      final s = engine.createParty(
        PartyInput(type: PartyType.supplier, name: name, company: company, phone: phone, address: addr, creditLimit: 100000),
        at: at,
      );
      for (final c in cats) {
        _bySupplierCat[catIds[c]] = s.id;
      }
    }
    // Link products to their supplier.
    for (final p in db.products.values.toList()) {
      db.products[p.id] = p.copyWith(supplierId: () => _bySupplierCat[p.categoryId]);
    }
  }

  // ─────────────────────────── History ───────────────────────────

  void _history() {
    final now = DateTime.now();
    final customers = db.parties.values.where((p) => p.isCustomer).map((p) => p.id).toList();
    final suppliers = db.parties.values.where((p) => !p.isCustomer).map((p) => p.id).toList();

    for (var d = 30; d >= 0; d--) {
      final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: d));
      final isToday = d == 0;
      final dayStart = day.add(const Duration(hours: 9));
      final dayEnd = isToday ? now.subtract(const Duration(minutes: 3)) : day.add(const Duration(hours: 21, minutes: 30));
      final effectiveStart = dayEnd.isAfter(dayStart) ? dayStart : day;
      final span = dayEnd.difference(effectiveStart).inMinutes.clamp(10, 1000);
      DateTime at() => effectiveStart.add(Duration(minutes: 5 + _rnd.nextInt(span - 5)));

      final events = <(DateTime, void Function(DateTime))>[];

      if (d == 30) {
        events.add((effectiveStart.add(const Duration(minutes: 1)), (t) {
          engine.addManualTx(const MoneyTxInput(type: TxType.deposit, amount: 60000, account: MoneyAccount.bank, note: 'رأس مال - حساب البنك'), at: t);
        }));
      }

      final salesCount = isToday ? 7 : 6 + _rnd.nextInt(8);
      for (var i = 0; i < salesCount; i++) {
        events.add((at(), (t) => _randomSale(t, customers)));
      }
      if (d % 4 == 2 || d == 29) {
        events.add((at(), (t) => _randomPurchase(t, suppliers)));
      }
      if (_rnd.nextDouble() < 0.45) events.add((at(), (t) => _customerPayment(t, customers)));
      if (d % 5 == 1) events.add((at(), (t) => _supplierPayment(t, suppliers)));
      if (d % 6 == 3) events.add((at(), (t) => _randomReturn(t)));
      if (d % 9 == 4) events.add((at(), (t) => _randomPurchaseReturn(t)));

      events.add((at(), (t) => _expense(t, 'ضيافة', 40 + _rnd.nextInt(120).toDouble())));
      if (d % 7 == 0) events.add((at(), (t) => _expense(t, 'كهرباء ومياه', 650)));
      if (d == 25) events.add((at(), (t) => _expense(t, 'إيجار', 6000, bank: true)));
      if (d == 12) events.add((at(), (t) => _expense(t, 'رواتب', 9000, bank: true)));
      if (d % 7 == 5) {
        events.add((at(), (t) => _safely(() => engine.addManualTx(
            const MoneyTxInput(type: TxType.withdrawal, amount: 2500, note: 'مسحوبات المالك'), at: t))));
      }

      events.sort((a, b) => a.$1.compareTo(b.$1));
      final openAt = events.first.$1.subtract(const Duration(minutes: 20));
      db.currentUser = demoUsers.first;
      engine.openSession(d == 30 ? 3000 : engine.lastClosedCash, at: openAt.isBefore(day) ? day : openAt);

      for (final (t, run) in events) {
        db.currentUser = demoUsers[_rnd.nextInt(10) < 6 ? 1 : 0];
        _safely(() => run(t));
      }

      if (!isToday) {
        db.currentUser = demoUsers.first;
        final expected = engine.drawer(db.openSession!).expected;
        final diff = _rnd.nextInt(10) == 0 ? -(_rnd.nextInt(4) * 5).toDouble() : 0.0;
        engine.closeSession(expected + diff, diff == 0 ? '' : 'عجز بسيط', at: day.add(const Duration(hours: 22)));
      }
    }
  }

  void _safely(void Function() fn) {
    try {
      fn();
    } catch (_) {
      // Rule violations during random generation are simply skipped.
    }
  }

  List<DraftLine> _pickLines(PriceTier tier, {required bool bulk}) {
    final products = db.products.values.where((p) => p.stock > 3).toList()..shuffle(_rnd);
    final n = 1 + _rnd.nextInt(bulk ? 6 : 4);
    return products.take(n).map((p) {
      final maxQ = bulk ? 12 : 3;
      final q = (1 + _rnd.nextInt(maxQ)).toDouble().clamp(1, p.stock - 1).toDouble();
      return DraftLine(productId: p.id, qty: q, unitPrice: p.priceFor(tier));
    }).toList();
  }

  void _randomSale(DateTime t, List<String> customers) {
    final walkIn = _rnd.nextDouble() < 0.55;
    final customer = walkIn ? null : db.parties[customers[_rnd.nextInt(customers.length)]]!;
    final tier = customer?.priceTier ?? PriceTier.retail;
    final lines = _pickLines(tier, bulk: tier != PriceTier.retail);
    if (lines.isEmpty) return;
    final subtotal = lines.fold(0.0, (s, l) => s + l.total);
    final discount = subtotal > 500 && _rnd.nextBool() ? (subtotal * 0.02).roundToDouble() : 0.0;
    final total = subtotal - discount;

    List<PaymentLine> payments;
    final r = _rnd.nextDouble();
    if (customer == null) {
      payments = [PaymentLine(r < 0.8 ? PaymentMethod.cash : PaymentMethod.card, total)];
    } else if (r < 0.4) {
      payments = [PaymentLine(PaymentMethod.cash, total)];
    } else if (r < 0.55) {
      payments = [PaymentLine(PaymentMethod.card, total)];
    } else {
      final paid = (total * (_rnd.nextInt(6) / 10)).roundToDouble();
      payments = [if (paid > 0) PaymentLine(PaymentMethod.cash, paid)];
    }
    final draft = InvoiceDraft(
      type: InvoiceType.sale,
      partyId: customer?.id,
      priceTier: tier,
      lines: lines,
      discount: discount,
      payments: payments,
    );
    try {
      engine.createInvoice(draft, at: t);
    } catch (_) {
      // Likely credit limit: settle fully in cash instead.
      _safely(() => engine.createInvoice(
            InvoiceDraft(
              type: InvoiceType.sale,
              partyId: customer?.id,
              priceTier: tier,
              lines: lines,
              discount: discount,
              payments: [PaymentLine(PaymentMethod.cash, total)],
            ),
            at: t,
          ));
    }
  }

  void _randomPurchase(DateTime t, List<String> suppliers) {
    final sid = suppliers[_rnd.nextInt(suppliers.length)];
    final products = db.products.values.where((p) => p.supplierId == sid).toList()..shuffle(_rnd);
    if (products.isEmpty) return;
    final lines = products.take(2 + _rnd.nextInt(4)).map((p) {
      final q = (2 + _rnd.nextInt(5)) * 12.0;
      return DraftLine(productId: p.id, qty: q, unitPrice: p.purchasePrice);
    }).toList();
    final total = lines.fold(0.0, (s, l) => s + l.total);
    final r = _rnd.nextDouble();
    final payments = r < 0.3
        ? [PaymentLine(PaymentMethod.bank, total)]
        : r < 0.75
            ? [PaymentLine(PaymentMethod.bank, (total * 0.4).roundToDouble())]
            : <PaymentLine>[];
    engine.createInvoice(
      InvoiceDraft(
        type: InvoiceType.purchase,
        partyId: sid,
        lines: lines,
        payments: payments,
        supplierRef: 'INV-${2000 + _rnd.nextInt(8000)}',
      ),
      at: t,
    );
  }

  void _customerPayment(DateTime t, List<String> customers) {
    final debtors = customers.map((id) => db.parties[id]!).where((p) => p.balance > 50).toList();
    if (debtors.isEmpty) return;
    final c = debtors[_rnd.nextInt(debtors.length)];
    final amount = (c.balance * (0.3 + _rnd.nextDouble() * 0.7) / 10).roundToDouble() * 10;
    engine.addPayment(
        PaymentInput(partyId: c.id, amount: amount.clamp(10, c.balance), method: _rnd.nextBool() ? PaymentMethod.cash : PaymentMethod.bank),
        at: t);
  }

  void _supplierPayment(DateTime t, List<String> suppliers) {
    final creditors = suppliers.map((id) => db.parties[id]!).where((p) => p.balance > 100).toList();
    if (creditors.isEmpty) return;
    final s = creditors[_rnd.nextInt(creditors.length)];
    final amount = (s.balance * 0.5 / 100).roundToDouble() * 100;
    if (amount <= 0) return;
    engine.addPayment(PaymentInput(partyId: s.id, amount: amount, method: PaymentMethod.bank, note: 'دفعة تحت الحساب'), at: t);
  }

  void _randomReturn(DateTime t) {
    final candidates = db.invoices.values
        .where((i) => i.type == InvoiceType.sale && !i.hasReturns && t.difference(i.date).inDays < 5 && i.date.isBefore(t))
        .toList();
    if (candidates.isEmpty) return;
    final inv = candidates[_rnd.nextInt(candidates.length)];
    final line = inv.lines.first;
    engine.createReturn(
      ReturnDraft(invoiceId: inv.id, qtyByProduct: {line.productId: 1}, reason: 'عيب في المنتج'),
      at: t,
    );
  }

  void _randomPurchaseReturn(DateTime t) {
    final candidates = db.invoices.values.where((i) => i.type == InvoiceType.purchase && !i.hasReturns && i.date.isBefore(t)).toList();
    if (candidates.isEmpty) return;
    final inv = candidates.last;
    final line = inv.lines.first;
    engine.createReturn(
      ReturnDraft(invoiceId: inv.id, qtyByProduct: {line.productId: 6}, reason: 'تالف عند الاستلام', refundMethod: PaymentMethod.bank),
      at: t,
    );
  }

  void _expense(DateTime t, String category, double amount, {bool bank = false}) {
    _safely(() => engine.addManualTx(
          MoneyTxInput(
            type: TxType.expense,
            amount: amount,
            category: category,
            account: bank ? MoneyAccount.bank : MoneyAccount.cash,
          ),
          at: t,
        ));
  }

  void _finalTouches() {
    // Make sure the demo shows low-stock and out-of-stock alerts.
    db.currentUser = demoUsers.first;
    final ago = DateTime.now().subtract(const Duration(minutes: 2));
    final byName = {for (final p in db.products.values) p.name: p};
    void setTo(String name, double qty) {
      final p = byName[name];
      if (p != null && (p.stock - qty).abs() > 0.001) {
        engine.adjustStock(p.id, qty, StockAdjustReason.count, 'جرد دوري', at: ago);
      }
    }

    setTo('كوكاكولا كانز 330 مل', 0);
    setTo('شامبو 400 مل', 3);
    setTo('زبدة 200 جم', 5);
    setTo('سردين بالزيت', 6);
  }
}
