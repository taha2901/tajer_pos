import 'enums.dart';

class MoneyTx {
  const MoneyTx({
    required this.id,
    required this.number,
    required this.date,
    required this.type,
    required this.account,
    required this.amount,
    required this.user,
    this.sessionId,
    this.refId,
    this.refNumber,
    this.note = '',
    this.category,
  });

  final String id;
  final String number;
  final DateTime date;
  final TxType type;
  final MoneyAccount account;

  /// Always positive; direction comes from [type].
  final double amount;
  final String user;
  final String? sessionId;
  final String? refId;
  final String? refNumber;
  final String note;

  /// Expense category.
  final String? category;

  bool get isIn => type.isIn;
  double get signed => isIn ? amount : -amount;
}

class MoneyTxInput {
  const MoneyTxInput({
    required this.type,
    required this.amount,
    this.account = MoneyAccount.cash,
    this.note = '',
    this.reference = '',
    this.category,
  });

  final TxType type;
  final double amount;
  final MoneyAccount account;
  final String note;
  final String reference;
  final String? category;
}

class CashSession {
  const CashSession({
    required this.id,
    required this.number,
    required this.openedAt,
    required this.openedBy,
    required this.openingBalance,
    this.closedAt,
    this.closedBy,
    this.expectedCash,
    this.countedCash,
    this.note = '',
  });

  final String id;
  final String number;
  final DateTime openedAt;
  final String openedBy;
  final double openingBalance;
  final DateTime? closedAt;
  final String? closedBy;
  final double? expectedCash;
  final double? countedCash;
  final String note;

  bool get isOpen => closedAt == null;
  double get difference => (countedCash ?? 0) - (expectedCash ?? 0);

  CashSession close({
    required DateTime at,
    required String by,
    required double expected,
    required double counted,
    String note = '',
  }) =>
      CashSession(
        id: id,
        number: number,
        openedAt: openedAt,
        openedBy: openedBy,
        openingBalance: openingBalance,
        closedAt: at,
        closedBy: by,
        expectedCash: expected,
        countedCash: counted,
        note: note,
      );
}

/// Drawer breakdown for a session (live or closed).
class DrawerSummary {
  const DrawerSummary({
    required this.session,
    required this.byType,
    required this.transactions,
  });

  final CashSession session;
  final Map<TxType, double> byType;
  final List<MoneyTx> transactions;

  double get totalIn => byType.entries.where((e) => e.key.isIn).fold(0, (s, e) => s + e.value);
  double get totalOut => byType.entries.where((e) => !e.key.isIn).fold(0, (s, e) => s + e.value);
  double get expected => session.openingBalance + totalIn - totalOut;
  double amount(TxType t) => byType[t] ?? 0;
}

class TxQuery {
  const TxQuery({this.account, this.type, this.from, this.to, this.sessionId, this.search = ''});
  final MoneyAccount? account;
  final TxType? type;
  final DateTime? from;
  final DateTime? to;
  final String? sessionId;
  final String search;

  TxQuery copyWith({
    MoneyAccount? Function()? account,
    TxType? Function()? type,
    DateTime? Function()? from,
    DateTime? Function()? to,
    String? search,
  }) =>
      TxQuery(
        account: account != null ? account() : this.account,
        type: type != null ? type() : this.type,
        from: from != null ? from() : this.from,
        to: to != null ? to() : this.to,
        sessionId: sessionId,
        search: search ?? this.search,
      );
}

class CashOverview {
  const CashOverview({
    required this.drawer,
    required this.bankBalance,
    required this.lastClosedCash,
    required this.recentSessions,
  });

  /// Null when the drawer is closed.
  final DrawerSummary? drawer;
  final double bankBalance;
  final double lastClosedCash;
  final List<CashSession> recentSessions;
}
