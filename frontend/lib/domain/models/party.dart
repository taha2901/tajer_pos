import 'enums.dart';

/// A customer or a supplier. Balance sign convention:
///  * customer: balance > 0 → the customer owes us (receivable)
///  * supplier: balance > 0 → we owe the supplier (payable)
class Party {
  const Party({
    required this.id,
    required this.type,
    required this.name,
    required this.createdAt,
    this.phone = '',
    this.address = '',
    this.company = '',
    this.priceTier = PriceTier.retail,
    this.creditLimit = 0,
    this.balance = 0,
    this.notes = '',
  });

  final String id;
  final PartyType type;
  final String name;
  final String phone;
  final String address;
  final String company;
  final PriceTier priceTier;

  /// 0 = no limit.
  final double creditLimit;
  final double balance;
  final String notes;
  final DateTime createdAt;

  bool get isCustomer => type == PartyType.customer;
  bool get hasDebt => balance > 0.009;
  bool get overLimit => creditLimit > 0 && balance > creditLimit;
  double get availableCredit => creditLimit <= 0 ? double.infinity : creditLimit - balance;

  Party copyWith({
    String? name,
    String? phone,
    String? address,
    String? company,
    PriceTier? priceTier,
    double? creditLimit,
    double? balance,
    String? notes,
  }) =>
      Party(
        id: id,
        type: type,
        createdAt: createdAt,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        address: address ?? this.address,
        company: company ?? this.company,
        priceTier: priceTier ?? this.priceTier,
        creditLimit: creditLimit ?? this.creditLimit,
        balance: balance ?? this.balance,
        notes: notes ?? this.notes,
      );
}

class PartyInput {
  const PartyInput({
    required this.type,
    required this.name,
    this.phone = '',
    this.address = '',
    this.company = '',
    this.priceTier = PriceTier.retail,
    this.creditLimit = 0,
    this.openingBalance = 0,
    this.notes = '',
  });

  final PartyType type;
  final String name;
  final String phone;
  final String address;
  final String company;
  final PriceTier priceTier;
  final double creditLimit;
  final double openingBalance;
  final String notes;
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.partyId,
    required this.date,
    required this.kind,
    required this.description,
    required this.debit,
    required this.credit,
    required this.balance,
    this.refId,
    this.refNumber,
  });

  final String id;
  final String partyId;
  final DateTime date;
  final LedgerKind kind;
  final String description;
  final double debit;
  final double credit;

  /// Running balance after this entry (in the party's sign convention).
  final double balance;
  final String? refId;
  final String? refNumber;
}

class PartyPayment {
  const PartyPayment({
    required this.id,
    required this.number,
    required this.partyType,
    required this.partyId,
    required this.partyName,
    required this.amount,
    required this.method,
    required this.date,
    required this.user,
    required this.balanceBefore,
    required this.balanceAfter,
    this.note = '',
  });

  final String id;
  final String number;
  final PartyType partyType;
  final String partyId;
  final String partyName;
  final double amount;
  final PaymentMethod method;
  final DateTime date;
  final String user;
  final String note;
  final double balanceBefore;
  final double balanceAfter;
}

class PaymentInput {
  const PaymentInput({
    required this.partyId,
    required this.amount,
    required this.method,
    this.note = '',
  });

  final String partyId;
  final double amount;
  final PaymentMethod method;
  final String note;
}

enum PartyFilter {
  all('الكل'),
  withBalance('عليهم رصيد'),
  overLimit('تجاوز الحد'),
  clear('بدون رصيد');

  const PartyFilter(this.label);
  final String label;
}

class PartyQuery {
  const PartyQuery(this.type, {this.search = '', this.filter = PartyFilter.all});
  final PartyType type;
  final String search;
  final PartyFilter filter;

  PartyQuery copyWith({String? search, PartyFilter? filter}) =>
      PartyQuery(type, search: search ?? this.search, filter: filter ?? this.filter);
}

class PartyStats {
  const PartyStats({
    required this.invoicesCount,
    required this.invoicesTotal,
    required this.paidTotal,
    required this.returnsTotal,
    required this.lastActivity,
  });

  final int invoicesCount;
  final double invoicesTotal;
  final double paidTotal;
  final double returnsTotal;
  final DateTime? lastActivity;
}

class Statement {
  const Statement({
    required this.party,
    required this.from,
    required this.to,
    required this.openingBalance,
    required this.entries,
  });

  final Party party;
  final DateTime? from;
  final DateTime? to;
  final double openingBalance;
  final List<LedgerEntry> entries;

  double get totalDebit => entries.fold(0, (s, e) => s + e.debit);
  double get totalCredit => entries.fold(0, (s, e) => s + e.credit);
  double get closingBalance => entries.isEmpty ? openingBalance : entries.last.balance;
}
