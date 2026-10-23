// JSON <-> domain model mapping for the API. Enums travel by name, dates as ISO-8601 (UTC).

import 'package:flutter/material.dart' show ThemeMode;

import '../../domain/models/models.dart';

typedef Json = Map<String, dynamic>;

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
DateTime _date(Object? v) => DateTime.parse(v as String).toLocal();
DateTime? _dateOrNull(Object? v) => v == null ? null : _date(v);
String _s(Object? v) => (v as String?) ?? '';
List<T> listOf<T>(Object? v, T Function(Json) f) => [for (final e in (v as List? ?? const [])) f(e as Json)];

// ───────────────────────────── Decoders ─────────────────────────────

AppUser userFrom(Json j) => AppUser(id: j['id'], name: j['name'], username: j['username']);

AppSettings settingsFrom(Json j, AppSettings base) => base.copyWith(
      storeName: j['storeName'],
      storePhone: j['storePhone'],
      storeAddress: j['storeAddress'],
      invoiceFooter: j['invoiceFooter'],
      allowNegativeStock: j['allowNegativeStock'],
      largeExpenseThreshold: (j['largeExpenseThreshold'] as num?)?.toDouble(),
      debtDueDays: (j['debtDueDays'] as num?)?.toInt(),
      closingReminderHour: (j['closingReminderHour'] as num?)?.toInt(),
      themeMode: ThemeMode.values.asNameMap()[j['themeMode']],
    );

Category categoryFrom(Json j) => Category(id: j['id'], name: j['name']);

Product productFrom(Json j) => Product(
      id: j['id'],
      name: j['name'],
      barcode: _s(j['barcode']),
      sku: _s(j['sku']),
      categoryId: j['categoryId'],
      unit: _s(j['unit']),
      purchasePrice: _d(j['purchasePrice']),
      sellingPrice: _d(j['sellingPrice']),
      wholesalePrice: _d(j['wholesalePrice']),
      halfWholesalePrice: _d(j['halfWholesalePrice']),
      stock: _d(j['stock']),
      minStock: _d(j['minStock']),
      createdAt: _date(j['createdAt']),
      supplierId: j['supplierId'],
      description: _s(j['description']),
      imagePath: j['imagePath'],
      isActive: j['isActive'] ?? true,
    );

StockMovement movementFrom(Json j) => StockMovement(
      id: j['id'],
      productId: j['productId'],
      date: _date(j['date']),
      type: StockMoveType.values.byName(j['type']),
      qty: _d(j['qty']),
      stockAfter: _d(j['stockAfter']),
      user: _s(j['user']),
      refId: j['refId'],
      refNumber: j['refNumber'],
      note: _s(j['note']),
    );

ProductStats productStatsFrom(Json j) => ProductStats(
      soldQty: _d(j['soldQty']),
      soldAmount: _d(j['soldAmount']),
      purchasedQty: _d(j['purchasedQty']),
      purchasedAmount: _d(j['purchasedAmount']),
      returnedQty: _d(j['returnedQty']),
      profit: _d(j['profit']),
      recentMovements: listOf(j['recentMovements'], movementFrom),
    );

Party partyFrom(Json j) => Party(
      id: j['id'],
      type: PartyType.values.byName(j['type']),
      name: j['name'],
      createdAt: _date(j['createdAt']),
      phone: _s(j['phone']),
      address: _s(j['address']),
      company: _s(j['company']),
      priceTier: PriceTier.values.byName(j['priceTier'] ?? 'retail'),
      creditLimit: _d(j['creditLimit']),
      balance: _d(j['balance']),
      notes: _s(j['notes']),
    );

LedgerEntry ledgerFrom(Json j) => LedgerEntry(
      id: j['id'],
      partyId: j['partyId'],
      date: _date(j['date']),
      kind: LedgerKind.values.byName(j['kind']),
      description: _s(j['description']),
      debit: _d(j['debit']),
      credit: _d(j['credit']),
      balance: _d(j['balance']),
      refId: j['refId'],
      refNumber: j['refNumber'],
    );

PartyPayment paymentFrom(Json j) => PartyPayment(
      id: j['id'],
      number: j['number'],
      partyType: PartyType.values.byName(j['partyType']),
      partyId: j['partyId'],
      partyName: _s(j['partyName']),
      amount: _d(j['amount']),
      method: PaymentMethod.values.byName(j['method']),
      date: _date(j['date']),
      user: _s(j['user']),
      balanceBefore: _d(j['balanceBefore']),
      balanceAfter: _d(j['balanceAfter']),
      note: _s(j['note']),
    );

PartyStats partyStatsFrom(Json j) => PartyStats(
      invoicesCount: (j['invoicesCount'] as num).toInt(),
      invoicesTotal: _d(j['invoicesTotal']),
      paidTotal: _d(j['paidTotal']),
      returnsTotal: _d(j['returnsTotal']),
      lastActivity: _dateOrNull(j['lastActivity']),
    );

Statement statementFrom(Json j) => Statement(
      party: partyFrom(j['party']),
      from: _dateOrNull(j['from']),
      to: _dateOrNull(j['to']),
      openingBalance: _d(j['openingBalance']),
      entries: listOf(j['entries'], ledgerFrom),
    );

Invoice invoiceFrom(Json j) => Invoice(
      id: j['id'],
      number: j['number'],
      type: InvoiceType.values.byName(j['type']),
      date: _date(j['date']),
      partyId: j['partyId'],
      partyName: _s(j['partyName']),
      priceTier: PriceTier.values.byName(j['priceTier'] ?? 'retail'),
      lines: listOf(
        j['lines'],
        (l) => InvoiceLine(
          productId: l['productId'],
          productName: _s(l['productName']),
          unit: _s(l['unit']),
          qty: _d(l['qty']),
          unitPrice: _d(l['unitPrice']),
          discount: _d(l['discount']),
          costPrice: _d(l['costPrice']),
          returnedQty: _d(l['returnedQty']),
        ),
      ),
      discount: _d(j['discount']),
      paid: _d(j['paid']),
      payments: listOf(j['payments'], (p) => PaymentLine(PaymentMethod.values.byName(p['method']), _d(p['amount']), reference: _s(p['reference']))),
      returnedAmount: _d(j['returnedAmount']),
      user: _s(j['user']),
      note: _s(j['note']),
      supplierRef: _s(j['supplierRef']),
    );

ReturnDoc returnFrom(Json j) => ReturnDoc(
      id: j['id'],
      number: j['number'],
      type: InvoiceType.values.byName(j['type']),
      invoiceId: j['invoiceId'],
      invoiceNumber: _s(j['invoiceNumber']),
      partyId: j['partyId'],
      partyName: _s(j['partyName']),
      date: _date(j['date']),
      lines: listOf(
        j['lines'],
        (l) => ReturnLine(
          productId: l['productId'],
          productName: _s(l['productName']),
          unit: _s(l['unit']),
          qty: _d(l['qty']),
          unitPrice: _d(l['unitPrice']),
          costPrice: _d(l['costPrice']),
        ),
      ),
      creditApplied: _d(j['creditApplied']),
      cashRefund: _d(j['cashRefund']),
      refundMethod: PaymentMethod.values.byName(j['refundMethod']),
      user: _s(j['user']),
      reason: _s(j['reason']),
    );

MoneyTx txFrom(Json j) => MoneyTx(
      id: j['id'],
      number: j['number'],
      date: _date(j['date']),
      type: TxType.values.byName(j['type']),
      account: MoneyAccount.values.byName(j['account']),
      amount: _d(j['amount']),
      user: _s(j['user']),
      sessionId: j['sessionId'],
      refId: j['refId'],
      refNumber: j['refNumber'],
      note: _s(j['note']),
      category: j['category'],
    );

CashSession sessionFrom(Json j) => CashSession(
      id: j['id'],
      number: j['number'],
      openedAt: _date(j['openedAt']),
      openedBy: _s(j['openedBy']),
      openingBalance: _d(j['openingBalance']),
      closedAt: _dateOrNull(j['closedAt']),
      closedBy: j['closedBy'],
      expectedCash: (j['expectedCash'] as num?)?.toDouble(),
      countedCash: (j['countedCash'] as num?)?.toDouble(),
      note: _s(j['note']),
    );

Map<TxType, double> _byType(Object? v) => {
      for (final e in (v as Map? ?? const {}).entries) TxType.values.byName(e.key as String): _d(e.value),
    };

DrawerSummary drawerFrom(Json j) => DrawerSummary(
      session: sessionFrom(j['session']),
      byType: _byType(j['byType']),
      transactions: listOf(j['transactions'], txFrom),
    );

CashOverview cashOverviewFrom(Json j) => CashOverview(
      drawer: j['drawer'] == null ? null : drawerFrom(j['drawer']),
      bankBalance: _d(j['bankBalance']),
      lastClosedCash: _d(j['lastClosedCash']),
      recentSessions: listOf(j['recentSessions'], sessionFrom),
    );

NamedValue namedFrom(Json j) => NamedValue(_s(j['name']), _d(j['value']), count: _d(j['count']), extra: _d(j['extra']), id: j['id']);
DayValue _dayFrom(Json j) => DayValue(_date(j['day']), _d(j['value']));

DashboardData dashboardFrom(Json j) => DashboardData(
      todaySales: _d(j['todaySales']),
      todaySalesCount: (j['todaySalesCount'] as num).toInt(),
      todayPurchases: _d(j['todayPurchases']),
      todayProfit: _d(j['todayProfit']),
      todayExpenses: _d(j['todayExpenses']),
      cashBalance: _d(j['cashBalance']),
      drawerOpen: j['drawerOpen'] == true,
      bankBalance: _d(j['bankBalance']),
      customerDebts: _d(j['customerDebts']),
      supplierDebts: _d(j['supplierDebts']),
      lowStock: listOf(j['lowStock'], productFrom),
      outOfStockCount: (j['outOfStockCount'] as num).toInt(),
      recentSales: listOf(j['recentSales'], invoiceFrom),
      recentPurchases: listOf(j['recentPurchases'], invoiceFrom),
      salesByDay: listOf(j['salesByDay'], _dayFrom),
      purchasesByDay: listOf(j['purchasesByDay'], _dayFrom),
      profitByDay: listOf(j['profitByDay'], _dayFrom),
      topProducts: listOf(j['topProducts'], namedFrom),
      yesterdaySales: _d(j['yesterdaySales']),
    );

TradeReport tradeReportFrom(Json j) => TradeReport(
      type: InvoiceType.values.byName(j['type']),
      invoicesCount: (j['invoicesCount'] as num).toInt(),
      gross: _d(j['gross']),
      discounts: _d(j['discounts']),
      returns: _d(j['returns']),
      cost: _d(j['cost']),
      paid: _d(j['paid']),
      due: _d(j['due']),
      byDay: listOf(j['byDay'], namedFrom),
      byWeek: listOf(j['byWeek'], namedFrom),
      byMonth: listOf(j['byMonth'], namedFrom),
      byParty: listOf(j['byParty'], namedFrom),
      byProduct: listOf(j['byProduct'], namedFrom),
      byCategory: listOf(j['byCategory'], namedFrom),
      byPaymentMethod: listOf(j['byPaymentMethod'], namedFrom),
    );

StockReport stockReportFrom(Json j) => StockReport(
      products: listOf(j['products'], productFrom),
      categoryNames: Map<String, String>.from(j['categoryNames'] as Map),
      movements: listOf(j['movements'], movementFrom),
      productNames: Map<String, String>.from(j['productNames'] as Map),
    );

FinancialReport financialReportFrom(Json j, DateRange range) => FinancialReport(
      range: range,
      revenue: _d(j['revenue']),
      salesReturns: _d(j['salesReturns']),
      cogs: _d(j['cogs']),
      expenses: _d(j['expenses']),
      expensesByCategory: listOf(j['expensesByCategory'], namedFrom),
      customerDebts: _d(j['customerDebts']),
      supplierDebts: _d(j['supplierDebts']),
      topDebtors: listOf(j['topDebtors'], namedFrom),
      topCreditors: listOf(j['topCreditors'], namedFrom),
      cashIn: _d(j['cashIn']),
      cashOut: _d(j['cashOut']),
      flowByType: _byType(j['flowByType']),
      flowByDay: listOf(j['flowByDay'], namedFrom),
      cashBalance: _d(j['cashBalance']),
      bankBalance: _d(j['bankBalance']),
    );

AppAlert alertFrom(Json j) => AppAlert(
      id: j['id'],
      kind: AlertKind.values.byName(j['kind']),
      title: _s(j['title']),
      body: _s(j['body']),
      date: _date(j['date']),
      severity: AlertSeverity.values.byName(j['severity']),
      targetId: j['targetId'],
      isRead: j['isRead'] == true,
    );

SearchHit searchHitFrom(Json j) => SearchHit(
      kind: SearchHitKind.values.byName(j['kind']),
      id: j['id'],
      title: _s(j['title']),
      subtitle: _s(j['subtitle']),
      trailing: _s(j['trailing']),
    );

// ───────────────────────────── Encoders ─────────────────────────────

Json settingsToJson(AppSettings s) => {
      'storeName': s.storeName,
      'storePhone': s.storePhone,
      'storeAddress': s.storeAddress,
      'invoiceFooter': s.invoiceFooter,
      'allowNegativeStock': s.allowNegativeStock,
      'largeExpenseThreshold': s.largeExpenseThreshold,
      'debtDueDays': s.debtDueDays,
      'closingReminderHour': s.closingReminderHour,
      'themeMode': s.themeMode.name,
    };

Json productInputToJson(ProductInput i) => {
      'name': i.name,
      'barcode': i.barcode,
      'sku': i.sku,
      'categoryId': i.categoryId,
      'unit': i.unit,
      'purchasePrice': i.purchasePrice,
      'sellingPrice': i.sellingPrice,
      'wholesalePrice': i.wholesalePrice,
      'halfWholesalePrice': i.halfWholesalePrice,
      'minStock': i.minStock,
      'openingStock': i.openingStock,
      'supplierId': i.supplierId,
      'description': i.description,
      'imagePath': i.imagePath,
      'isActive': i.isActive,
    };

Json partyInputToJson(PartyInput i) => {
      'type': i.type.name,
      'name': i.name,
      'phone': i.phone,
      'address': i.address,
      'company': i.company,
      'priceTier': i.priceTier.name,
      'creditLimit': i.creditLimit,
      'openingBalance': i.openingBalance,
      'notes': i.notes,
    };

Json paymentInputToJson(PaymentInput i) => {'partyId': i.partyId, 'amount': i.amount, 'method': i.method.name, 'note': i.note};

Json invoiceDraftToJson(InvoiceDraft d) => {
      'type': d.type.name,
      'partyId': d.partyId,
      'priceTier': d.priceTier.name,
      'lines': [
        for (final l in d.lines) {'productId': l.productId, 'qty': l.qty, 'unitPrice': l.unitPrice, 'discount': l.discount},
      ],
      'discount': d.discount,
      'payments': [
        for (final p in d.payments) {'method': p.method.name, 'amount': p.amount, 'reference': p.reference},
      ],
      'note': d.note,
      'supplierRef': d.supplierRef,
      'overrideCreditLimit': d.overrideCreditLimit,
    };

Json returnDraftToJson(ReturnDraft d) => {
      'invoiceId': d.invoiceId,
      'qtyByProduct': d.qtyByProduct,
      'refundMethod': d.refundMethod.name,
      'reason': d.reason,
    };

Json txInputToJson(MoneyTxInput i) => {
      'type': i.type.name,
      'amount': i.amount,
      'account': i.account.name,
      'note': i.note,
      'reference': i.reference,
      'category': i.category,
    };
