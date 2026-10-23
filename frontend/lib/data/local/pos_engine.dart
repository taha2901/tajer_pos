import 'dart:math';

import '../../core/errors.dart';
import '../../core/format.dart';
import '../../domain/models/models.dart';
import 'local_store.dart';

/// The business rules of the POS, executed against [LocalStore].
///
/// This class plays the role a backend will play later: each public method is
/// one atomic operation. It validates everything first, then applies every
/// side effect (stock, party ledger, money movements), each carrying a
/// reference. See docs/ARCHITECTURE.md §3.
class PosEngine {
  PosEngine(this.db);

  final LocalStore db;

  static const _eps = 0.009;

  String get _user => db.currentUser?.name ?? 'النظام';

  // ───────────────────────────── Catalog ─────────────────────────────

  Category addCategory(String name) {
    final n = name.trim();
    if (n.isEmpty) throw const BusinessException('اسم الفئة مطلوب');
    if (db.categories.values.any((c) => c.name == n)) {
      throw const BusinessException('الفئة موجودة بالفعل');
    }
    final c = Category(id: db.id('c'), name: n);
    db.categories[c.id] = c;
    return c;
  }

  void _validateProduct(ProductInput i, {String? excludeId}) {
    if (i.name.trim().isEmpty) throw const BusinessException('اسم المنتج مطلوب');
    if (!db.categories.containsKey(i.categoryId)) throw const BusinessException('اختر فئة المنتج');
    if (i.purchasePrice < 0 || i.sellingPrice <= 0) {
      throw const BusinessException('أدخل سعر الشراء وسعر البيع بشكل صحيح');
    }
    for (final p in db.products.values) {
      if (p.id == excludeId) continue;
      if (i.barcode.isNotEmpty && p.barcode == i.barcode) {
        throw BusinessException('الباركود مستخدم بالفعل للمنتج "${p.name}"');
      }
      if (i.sku.isNotEmpty && p.sku == i.sku) {
        throw BusinessException('كود SKU مستخدم بالفعل للمنتج "${p.name}"');
      }
    }
  }

  Product createProduct(ProductInput i, {DateTime? at}) {
    _validateProduct(i);
    if (i.openingStock < 0) throw const BusinessException('الرصيد الافتتاحي لا يمكن أن يكون سالباً');
    final now = at ?? DateTime.now();
    final p = Product(
      id: db.id('p'),
      name: i.name.trim(),
      barcode: i.barcode.isEmpty ? generateBarcode() : i.barcode,
      sku: i.sku.isEmpty ? generateSku(i.categoryId) : i.sku,
      categoryId: i.categoryId,
      unit: i.unit,
      purchasePrice: i.purchasePrice,
      sellingPrice: i.sellingPrice,
      wholesalePrice: i.wholesalePrice > 0 ? i.wholesalePrice : i.sellingPrice,
      halfWholesalePrice: i.halfWholesalePrice > 0 ? i.halfWholesalePrice : i.sellingPrice,
      stock: 0,
      minStock: i.minStock,
      supplierId: i.supplierId,
      description: i.description,
      imagePath: i.imagePath,
      isActive: i.isActive,
      createdAt: now,
    );
    db.products[p.id] = p;
    if (i.openingStock > 0) {
      _moveStock(p.id, i.openingStock, StockMoveType.opening, at: now, note: 'رصيد أول المدة');
    }
    return db.products[p.id]!;
  }

  Product updateProduct(String id, ProductInput i) {
    final p = _product(id);
    _validateProduct(i, excludeId: id);
    final updated = p.copyWith(
      name: i.name.trim(),
      barcode: i.barcode.isEmpty ? p.barcode : i.barcode,
      sku: i.sku.isEmpty ? p.sku : i.sku,
      categoryId: i.categoryId,
      unit: i.unit,
      purchasePrice: i.purchasePrice,
      sellingPrice: i.sellingPrice,
      wholesalePrice: i.wholesalePrice > 0 ? i.wholesalePrice : i.sellingPrice,
      halfWholesalePrice: i.halfWholesalePrice > 0 ? i.halfWholesalePrice : i.sellingPrice,
      minStock: i.minStock,
      supplierId: () => i.supplierId,
      description: i.description,
      imagePath: () => i.imagePath,
      isActive: i.isActive,
    );
    db.products[id] = updated;
    return updated;
  }

  void deleteProduct(String id) {
    _product(id);
    final used = db.stockMoves.any((m) => m.productId == id && m.type != StockMoveType.opening) ||
        db.invoices.values.any((inv) => inv.lines.any((l) => l.productId == id));
    if (used) {
      throw const BusinessException(
        'لا يمكن حذف منتج له حركات بيع أو شراء. يمكنك إيقافه بدلاً من ذلك.',
        code: ErrorCodes.hasTransactions,
      );
    }
    db.products.remove(id);
    db.stockMoves.removeWhere((m) => m.productId == id);
  }

  Product setActive(String id, bool active) {
    final p = _product(id).copyWith(isActive: active);
    db.products[id] = p;
    return p;
  }

  Product adjustStock(String id, double newStock, StockAdjustReason reason, String note, {DateTime? at}) {
    final p = _product(id);
    if (newStock < 0) throw const BusinessException('الكمية لا يمكن أن تكون سالبة');
    final delta = newStock - p.stock;
    if (delta.abs() < 0.0001) throw const BusinessException('الكمية الجديدة مساوية للرصيد الحالي');
    final ref = db.number('ADJ', pad: 4);
    _moveStock(id, delta, StockMoveType.adjustment,
        at: at, refNumber: ref, note: note.isEmpty ? reason.label : '${reason.label} — $note');
    return db.products[id]!;
  }

  String generateBarcode() {
    final rnd = Random();
    while (true) {
      final body = '622${List.generate(9, (_) => rnd.nextInt(10)).join()}';
      final code = body + _ean13Check(body).toString();
      if (!db.products.values.any((p) => p.barcode == code)) return code;
    }
  }

  static int _ean13Check(String twelve) {
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      sum += int.parse(twelve[i]) * (i.isEven ? 1 : 3);
    }
    return (10 - sum % 10) % 10;
  }

  String generateSku(String categoryId) {
    final idx = db.categories.keys.toList().indexOf(categoryId) + 1;
    final prefix = 'C${idx.clamp(1, 99).toString().padLeft(2, '0')}';
    var n = db.products.values.where((p) => p.sku.startsWith(prefix)).length + 1;
    while (true) {
      final sku = '$prefix-${n.toString().padLeft(4, '0')}';
      if (!db.products.values.any((p) => p.sku == sku)) return sku;
      n++;
    }
  }

  void _moveStock(
    String productId,
    double qty,
    StockMoveType type, {
    DateTime? at,
    String? refId,
    String? refNumber,
    String note = '',
  }) {
    final p = _product(productId);
    final after = p.stock + qty;
    db.products[productId] = p.copyWith(stock: after);
    db.stockMoves.add(StockMovement(
      id: db.id('m'),
      productId: productId,
      date: at ?? DateTime.now(),
      type: type,
      qty: qty,
      stockAfter: after,
      refId: refId,
      refNumber: refNumber,
      note: note,
      user: _user,
    ));
  }

  // ───────────────────────────── Parties ─────────────────────────────

  void _validateParty(PartyInput i) {
    if (i.name.trim().isEmpty) throw const BusinessException('الاسم مطلوب');
    if (i.phone.isNotEmpty && i.phone.length < 8) throw const BusinessException('رقم الهاتف غير صحيح');
    if (i.creditLimit < 0) throw const BusinessException('حد الائتمان لا يمكن أن يكون سالباً');
  }

  Party createParty(PartyInput i, {DateTime? at}) {
    _validateParty(i);
    final now = at ?? DateTime.now();
    final p = Party(
      id: db.id(i.type == PartyType.customer ? 'cu' : 'su'),
      type: i.type,
      name: i.name.trim(),
      phone: i.phone,
      address: i.address,
      company: i.company,
      priceTier: i.priceTier,
      creditLimit: i.creditLimit,
      notes: i.notes,
      createdAt: now,
    );
    db.parties[p.id] = p;
    if (i.openingBalance.abs() > _eps) {
      final isCustomer = i.type == PartyType.customer;
      final amount = i.openingBalance.abs();
      final increases = i.openingBalance > 0;
      _post(p.id, LedgerKind.opening, 'رصيد افتتاحي',
          debit: isCustomer == increases ? amount : 0, credit: isCustomer == increases ? 0 : amount, at: now);
    }
    return db.parties[p.id]!;
  }

  Party updateParty(String id, PartyInput i) {
    final p = _party(id);
    _validateParty(i);
    final u = p.copyWith(
      name: i.name.trim(),
      phone: i.phone,
      address: i.address,
      company: i.company,
      priceTier: i.priceTier,
      creditLimit: i.creditLimit,
      notes: i.notes,
    );
    db.parties[id] = u;
    return u;
  }

  void deleteParty(String id) {
    final p = _party(id);
    final hasDocs = db.invoices.values.any((i) => i.partyId == id) ||
        db.payments.values.any((x) => x.partyId == id);
    if (hasDocs || p.balance.abs() > _eps) {
      throw BusinessException(
        'لا يمكن حذف ${p.type.label} له فواتير أو رصيد مفتوح.',
        code: ErrorCodes.hasTransactions,
      );
    }
    db.parties.remove(id);
    db.ledger.removeWhere((e) => e.partyId == id);
  }

  /// [amount] > 0 increases what the party owes us / we owe them.
  Party adjustBalance(String id, double amount, String note, {DateTime? at}) {
    final p = _party(id);
    if (amount.abs() < _eps) throw const BusinessException('أدخل مبلغ التسوية');
    final ref = db.number('ADJ', pad: 4);
    final increase = amount > 0;
    final debitSide = p.isCustomer == increase;
    _post(id, LedgerKind.adjustment, note.isEmpty ? 'تسوية رصيد' : 'تسوية: $note',
        debit: debitSide ? amount.abs() : 0, credit: debitSide ? 0 : amount.abs(), at: at, refNumber: ref);
    return db.parties[id]!;
  }

  /// Posts a ledger entry and updates the party balance.
  void _post(
    String partyId,
    LedgerKind kind,
    String description, {
    double debit = 0,
    double credit = 0,
    DateTime? at,
    String? refId,
    String? refNumber,
  }) {
    final p = _party(partyId);
    final delta = p.isCustomer ? debit - credit : credit - debit;
    final balance = r2(p.balance + delta);
    db.parties[partyId] = p.copyWith(balance: balance);
    db.ledger.add(LedgerEntry(
      id: db.id('l'),
      partyId: partyId,
      date: at ?? DateTime.now(),
      kind: kind,
      description: description,
      debit: r2(debit),
      credit: r2(credit),
      balance: balance,
      refId: refId,
      refNumber: refNumber,
    ));
  }

  // ───────────────────────────── Invoices ─────────────────────────────

  Invoice createInvoice(InvoiceDraft d, {DateTime? at}) {
    final now = at ?? DateTime.now();
    final isSale = d.type == InvoiceType.sale;

    // 1. Validate
    if (d.lines.isEmpty) throw const BusinessException('أضف منتجاً واحداً على الأقل');
    for (final l in d.lines) {
      _product(l.productId);
      if (l.qty <= 0) throw const BusinessException('الكمية يجب أن تكون أكبر من صفر');
      if (l.unitPrice < 0) throw const BusinessException('السعر غير صحيح');
      if (l.discount < 0 || l.discount > l.qty * l.unitPrice + _eps) {
        throw const BusinessException('خصم الصنف أكبر من قيمته');
      }
    }
    final subtotal = r2(d.subtotal);
    if (d.discount < 0 || d.discount > subtotal + _eps) throw const BusinessException('الخصم أكبر من الإجمالي');
    final total = r2(subtotal - d.discount);
    final paid = r2(d.paid);
    if (d.payments.any((p) => p.amount < 0)) throw const BusinessException('مبلغ دفع غير صحيح');
    if (paid > total + _eps) throw const BusinessException('المبلغ المدفوع أكبر من إجمالي الفاتورة');
    final due = r2(total - paid);

    Party? party;
    if (d.partyId != null) {
      party = _party(d.partyId!);
      if (party.type != d.type.partyType) throw const BusinessException('نوع الطرف غير مناسب للفاتورة');
    } else if (!isSale) {
      throw const BusinessException('اختر المورد');
    }

    if (due > _eps && party == null) {
      throw const BusinessException('البيع الآجل يتطلب اختيار عميل مسجل');
    }

    if (isSale && party != null && due > _eps && party.creditLimit > 0 && !d.overrideCreditLimit) {
      final newBalance = party.balance + due;
      if (newBalance > party.creditLimit + _eps) {
        throw BusinessException(
          'تجاوز حد الائتمان: رصيد العميل سيصبح ${Fmt.money(newBalance)} والحد ${Fmt.money(party.creditLimit)}',
          code: ErrorCodes.creditLimit,
        );
      }
    }

    if (isSale && !db.settings.allowNegativeStock) {
      final need = <String, double>{};
      for (final l in d.lines) {
        need[l.productId] = (need[l.productId] ?? 0) + l.qty;
      }
      for (final e in need.entries) {
        final p = _product(e.key);
        if (e.value > p.stock + 0.0001) {
          throw BusinessException(
            'الكمية المطلوبة من "${p.name}" (${Fmt.qty(e.value)}) أكبر من المتاح (${Fmt.qty(p.stock)})',
            code: ErrorCodes.insufficientStock,
          );
        }
      }
    }

    final cashPaid = d.payments.fold(0.0, (s, p) => s + p.amount);
    if (cashPaid > _eps) {
      final session = _requireSession();
      if (!isSale) _requireCash(session, cashPaid);
    }

    // 2. Apply
    final id = db.id(isSale ? 'si' : 'pi');
    final number = db.number(d.type.prefix, start: isSale ? 1000 : 500);
    final factor = subtotal == 0 ? 1.0 : total / subtotal;

    final lines = d.lines.map((l) {
      final p = _product(l.productId);
      final netUnit = l.qty == 0 ? 0.0 : (l.total / l.qty) * factor;
      return InvoiceLine(
        productId: p.id,
        productName: p.name,
        unit: p.unit,
        qty: l.qty,
        unitPrice: l.unitPrice,
        discount: l.discount,
        costPrice: isSale ? p.purchasePrice : r2(netUnit),
      );
    }).toList();

    final invoice = Invoice(
      id: id,
      number: number,
      type: d.type,
      date: now,
      partyId: party?.id,
      partyName: party?.name ?? 'عميل نقدي',
      priceTier: d.priceTier,
      lines: lines,
      discount: r2(d.discount),
      paid: paid,
      payments: d.payments.where((p) => p.amount > _eps).toList(),
      user: _user,
      note: d.note,
      supplierRef: d.supplierRef,
    );
    db.invoices[id] = invoice;

    for (final l in lines) {
      if (isSale) {
        _moveStock(l.productId, -l.qty, StockMoveType.sale, at: now, refId: id, refNumber: number);
      } else {
        _moveStock(l.productId, l.qty, StockMoveType.purchase, at: now, refId: id, refNumber: number);
        // Purchase price follows the latest cost.
        db.products[l.productId] = db.products[l.productId]!.copyWith(purchasePrice: l.costPrice);
      }
    }

    if (party != null) {
      if (isSale) {
        _post(party.id, LedgerKind.invoice, 'فاتورة بيع', debit: total, at: now, refId: id, refNumber: number);
        if (paid > _eps) {
          _post(party.id, LedgerKind.payment, 'مدفوع مع الفاتورة', credit: paid, at: now, refId: id, refNumber: number);
        }
      } else {
        _post(party.id, LedgerKind.invoice, 'فاتورة شراء', credit: total, at: now, refId: id, refNumber: number);
        if (paid > _eps) {
          _post(party.id, LedgerKind.payment, 'مدفوع مع الفاتورة', debit: paid, at: now, refId: id, refNumber: number);
        }
      }
    }

    for (final p in invoice.payments) {
      _addTx(
        isSale ? TxType.sale : TxType.purchase,
        p.method.account,
        p.amount,
        at: now,
        refId: id,
        refNumber: number,
        note: '${d.type.label} — ${invoice.partyName}${p.reference.isEmpty ? '' : ' • مرجع ${p.reference}'}',
      );
    }
    return invoice;
  }

  ReturnDoc createReturn(ReturnDraft d, {DateTime? at}) {
    final now = at ?? DateTime.now();
    final inv = db.invoices[d.invoiceId] ?? (throw const NotFoundException('الفاتورة غير موجودة'));
    final isSale = inv.type == InvoiceType.sale;

    final qty = {
      for (final e in d.qtyByProduct.entries)
        if (e.value > 0) e.key: e.value,
    };
    if (qty.isEmpty) throw const BusinessException('حدد كمية مرتجعة لصنف واحد على الأقل');
    for (final e in qty.entries) {
      final line = inv.lines.where((l) => l.productId == e.key).firstOrNull ??
          (throw const BusinessException('الصنف غير موجود في الفاتورة'));
      if (e.value > line.returnableQty + 0.0001) {
        throw BusinessException('أقصى كمية يمكن إرجاعها من "${line.productName}" هي ${Fmt.qty(line.returnableQty)}');
      }
      if (!isSale && !db.settings.allowNegativeStock) {
        final p = _product(e.key);
        if (e.value > p.stock + 0.0001) {
          throw BusinessException(
            'لا يمكن إرجاع ${Fmt.qty(e.value)} من "${p.name}" — المتاح بالمخزن ${Fmt.qty(p.stock)}',
            code: ErrorCodes.insufficientStock,
          );
        }
      }
    }

    final s = ReturnSettlement.of(inv, qty);
    if (s.cashRefund > _eps) {
      final session = _requireSession();
      if (isSale) _requireCash(session, s.cashRefund);
    }

    final id = db.id(isSale ? 'sr' : 'pr');
    final number = db.number(isSale ? 'SR' : 'PR', pad: 4);
    final lines = <ReturnLine>[];
    final updatedLines = inv.lines.map((l) {
      final q = qty[l.productId] ?? 0;
      if (q <= 0) return l;
      lines.add(ReturnLine(
        productId: l.productId,
        productName: l.productName,
        unit: l.unit,
        qty: q,
        unitPrice: r2(l.netUnitPrice * inv.discountFactor),
        costPrice: l.costPrice,
      ));
      return l.copyWith(returnedQty: l.returnedQty + q);
    }).toList();

    db.invoices[inv.id] = inv.copyWith(
      lines: updatedLines,
      returnedAmount: r2(inv.returnedAmount + s.total),
      paid: r2(inv.paid - s.cashRefund),
    );

    final doc = ReturnDoc(
      id: id,
      number: number,
      type: inv.type,
      invoiceId: inv.id,
      invoiceNumber: inv.number,
      partyId: inv.partyId,
      partyName: inv.partyName,
      date: now,
      lines: lines,
      creditApplied: s.creditApplied,
      cashRefund: s.cashRefund,
      refundMethod: d.refundMethod,
      user: _user,
      reason: d.reason,
    );
    db.returns[id] = doc;

    for (final l in lines) {
      _moveStock(l.productId, isSale ? l.qty : -l.qty,
          isSale ? StockMoveType.saleReturn : StockMoveType.purchaseReturn,
          at: now, refId: id, refNumber: number, note: 'من ${inv.number}');
    }

    if (inv.partyId != null) {
      final desc = 'مرتجع من ${inv.number}';
      if (isSale) {
        _post(inv.partyId!, LedgerKind.returnDoc, desc, credit: s.total, at: now, refId: id, refNumber: number);
        if (s.cashRefund > _eps) {
          _post(inv.partyId!, LedgerKind.refund, 'رد مبلغ للعميل', debit: s.cashRefund, at: now, refId: id, refNumber: number);
        }
      } else {
        _post(inv.partyId!, LedgerKind.returnDoc, desc, debit: s.total, at: now, refId: id, refNumber: number);
        if (s.cashRefund > _eps) {
          _post(inv.partyId!, LedgerKind.refund, 'استرداد مبلغ من المورد', credit: s.cashRefund, at: now, refId: id, refNumber: number);
        }
      }
    }

    if (s.cashRefund > _eps) {
      _addTx(isSale ? TxType.saleRefund : TxType.purchaseRefund, d.refundMethod.account, s.cashRefund,
          at: now, refId: id, refNumber: number, note: 'مرتجع ${inv.number} — ${inv.partyName}');
    }
    return doc;
  }

  // ───────────────────────────── Payments ─────────────────────────────

  PartyPayment addPayment(PaymentInput i, {DateTime? at}) {
    final now = at ?? DateTime.now();
    final party = _party(i.partyId);
    final amount = r2(i.amount);
    if (amount <= 0) throw const BusinessException('أدخل مبلغاً أكبر من صفر');
    final session = _requireSession();
    if (!party.isCustomer) _requireCash(session, amount);

    final id = db.id('pay');
    final number = db.number(party.isCustomer ? 'RC' : 'PV', pad: 4);
    final before = party.balance;

    if (party.isCustomer) {
      _post(party.id, LedgerKind.payment, 'تحصيل ${i.method.label}${i.note.isEmpty ? '' : ' — ${i.note}'}',
          credit: amount, at: now, refId: id, refNumber: number);
    } else {
      _post(party.id, LedgerKind.payment, 'سداد ${i.method.label}${i.note.isEmpty ? '' : ' — ${i.note}'}',
          debit: amount, at: now, refId: id, refNumber: number);
    }

    // FIFO allocation to the oldest open invoices.
    var left = amount;
    final open = db.invoices.values.where((x) => x.partyId == party.id && x.due > _eps).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    for (final inv in open) {
      if (left <= _eps) break;
      final take = min(left, inv.due);
      db.invoices[inv.id] = inv.copyWith(paid: r2(inv.paid + take));
      left = r2(left - take);
    }

    _addTx(party.isCustomer ? TxType.customerPayment : TxType.supplierPayment, i.method.account, amount,
        at: now, refId: id, refNumber: number, note: party.name);

    final payment = PartyPayment(
      id: id,
      number: number,
      partyType: party.type,
      partyId: party.id,
      partyName: party.name,
      amount: amount,
      method: i.method,
      date: now,
      user: _user,
      note: i.note,
      balanceBefore: before,
      balanceAfter: db.parties[party.id]!.balance,
    );
    db.payments[id] = payment;
    return payment;
  }

  // ───────────────────────────── Cash ─────────────────────────────

  CashSession openSession(double opening, {DateTime? at}) {
    if (db.openSession != null) throw const BusinessException('الخزنة مفتوحة بالفعل');
    if (opening < 0) throw const BusinessException('رصيد الافتتاح لا يمكن أن يكون سالباً');
    final s = CashSession(
      id: db.id('ses'),
      number: db.number('SH', pad: 4),
      openedAt: at ?? DateTime.now(),
      openedBy: _user,
      openingBalance: r2(opening),
    );
    db.sessions.add(s);
    return s;
  }

  CashSession closeSession(double counted, String note, {DateTime? at}) {
    final s = db.openSession ?? (throw const BusinessException('لا توجد وردية مفتوحة'));
    if (counted < 0) throw const BusinessException('المبلغ الفعلي لا يمكن أن يكون سالباً');
    final closed = s.close(at: at ?? DateTime.now(), by: _user, expected: r2(drawer(s).expected), counted: r2(counted), note: note);
    db.sessions[db.sessions.indexOf(s)] = closed;
    return closed;
  }

  DrawerSummary drawer(CashSession s) {
    final txs = db.txs.where((t) => t.sessionId == s.id).toList();
    final byType = <TxType, double>{};
    for (final t in txs) {
      byType[t.type] = r2((byType[t.type] ?? 0) + t.amount);
    }
    return DrawerSummary(session: s, byType: byType, transactions: txs.reversed.toList());
  }

  double get bankBalance => r2(db.txs.where((t) => t.account == MoneyAccount.bank).fold(0.0, (s, t) => s + t.signed));

  double get lastClosedCash {
    for (final s in db.sessions.reversed) {
      if (!s.isOpen) return s.countedCash ?? 0;
    }
    return 0;
  }

  MoneyTx addManualTx(MoneyTxInput i, {DateTime? at}) {
    if (!TxType.manual.contains(i.type)) throw const BusinessException('نوع حركة غير مسموح');
    if (i.amount <= 0) throw const BusinessException('أدخل مبلغاً أكبر من صفر');
    if (i.type == TxType.expense && (i.category == null || i.category!.isEmpty)) {
      throw const BusinessException('اختر بند المصروف');
    }
    final s = _requireSession();
    if (!i.type.isIn) _requireCash(s, i.amount);
    final note = i.note.trim().isEmpty ? (i.category ?? i.type.label) : i.note.trim();
    return _addTx(i.type, MoneyAccount.cash, i.amount,
        at: at, refNumber: i.reference.isEmpty ? null : i.reference, note: note, category: i.category);
  }

  MoneyTx _addTx(
    TxType type,
    MoneyAccount account,
    double amount, {
    DateTime? at,
    String? refId,
    String? refNumber,
    String note = '',
    String? category,
  }) {
    final tx = MoneyTx(
      id: db.id('t'),
      number: db.number('TX', pad: 5),
      date: at ?? DateTime.now(),
      type: type,
      account: account,
      amount: r2(amount),
      user: _user,
      sessionId: account == MoneyAccount.cash ? db.openSession?.id : null,
      refId: refId,
      refNumber: refNumber,
      note: note,
      category: category,
    );
    db.txs.add(tx);
    return tx;
  }

  CashSession _requireSession() =>
      db.openSession ??
      (throw const BusinessException('الخزنة مغلقة. افتح وردية أولاً لتسجيل حركات نقدية.', code: ErrorCodes.drawerClosed));

  void _requireCash(CashSession s, double amount) {
    final available = drawer(s).expected;
    if (amount > available + _eps) {
      throw BusinessException(
        'النقدية بالخزنة غير كافية. المتاح ${Fmt.money(available)} والمطلوب ${Fmt.money(amount)}',
        code: ErrorCodes.insufficientCash,
      );
    }
  }

  // ───────────────────────────── Helpers ─────────────────────────────

  Product _product(String id) => db.products[id] ?? (throw const NotFoundException('المنتج غير موجود'));

  Party _party(String id) => db.parties[id] ?? (throw const NotFoundException('الطرف غير موجود'));
}
