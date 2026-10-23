import '../../domain/models/models.dart';
import 'seeder.dart';

/// In-memory "database". Tables are insertion-ordered maps / lists.
/// Only [PosEngine] mutates business tables, so every change goes through the rules.
class LocalStore {
  final categories = <String, Category>{};
  final products = <String, Product>{};
  final parties = <String, Party>{};
  final invoices = <String, Invoice>{};
  final returns = <String, ReturnDoc>{};
  final payments = <String, PartyPayment>{};
  final ledger = <LedgerEntry>[];
  final stockMoves = <StockMovement>[];
  final txs = <MoneyTx>[];
  final sessions = <CashSession>[];

  AppSettings settings = const AppSettings();
  AppUser? currentUser;
  final users = <AppUser>[...demoUsers];
  final pins = <String, String>{...demoPins};
  final readAlerts = <String>{};
  final recentSearches = <String>[];

  final _seq = <String, int>{};

  int _next(String key) => _seq[key] = (_seq[key] ?? 0) + 1;

  String id(String prefix) => '$prefix${_next('id_$prefix')}';

  String number(String prefix, {int pad = 5, int start = 0}) {
    final n = _next('no_$prefix') + start;
    return '$prefix-${n.toString().padLeft(pad, '0')}';
  }

  CashSession? get openSession {
    for (final s in sessions.reversed) {
      if (s.isOpen) return s;
    }
    return null;
  }

  void clear() {
    categories.clear();
    products.clear();
    parties.clear();
    invoices.clear();
    returns.clear();
    payments.clear();
    ledger.clear();
    stockMoves.clear();
    txs.clear();
    sessions.clear();
    readAlerts.clear();
    recentSearches.clear();
    _seq.clear();
  }
}
