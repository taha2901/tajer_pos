enum PartyType {
  customer('عميل', 'العملاء'),
  supplier('مورد', 'الموردين');

  const PartyType(this.label, this.plural);
  final String label;
  final String plural;
}

/// Price level used when selling. Also the default "customer type".
enum PriceTier {
  retail('قطاعي'),
  halfWholesale('نص جملة'),
  wholesale('جملة'),
  custom('سعر خاص');

  const PriceTier(this.label);
  final String label;
}

enum PaymentMethod {
  cash('نقدي'),
  card('بطاقة'),
  bank('تحويل بنكي');

  const PaymentMethod(this.label);
  final String label;

  MoneyAccount get account => this == cash ? MoneyAccount.cash : MoneyAccount.bank;
}

enum MoneyAccount {
  cash('الخزنة'),
  bank('البنك');

  const MoneyAccount(this.label);
  final String label;
}

enum InvoiceType {
  sale('فاتورة بيع', 'المبيعات', 'S'),
  purchase('فاتورة شراء', 'المشتريات', 'P');

  const InvoiceType(this.label, this.plural, this.prefix);
  final String label;
  final String plural;
  final String prefix;

  PartyType get partyType => this == sale ? PartyType.customer : PartyType.supplier;
}

enum PaymentStatus {
  paid('مدفوعة'),
  partial('مدفوعة جزئياً'),
  unpaid('آجلة');

  const PaymentStatus(this.label);
  final String label;
}

enum StockMoveType {
  opening('رصيد افتتاحي', 1),
  purchase('شراء', 1),
  sale('بيع', -1),
  saleReturn('مرتجع بيع', 1),
  purchaseReturn('مرتجع شراء', -1),
  adjustment('تسوية', 0);

  const StockMoveType(this.label, this.sign);
  final String label;

  /// +1 increases stock, -1 decreases, 0 = either direction.
  final int sign;
}

enum LedgerKind {
  opening('رصيد افتتاحي'),
  invoice('فاتورة'),
  payment('دفعة'),
  returnDoc('مرتجع'),
  refund('رد نقدية'),
  adjustment('تسوية');

  const LedgerKind(this.label);
  final String label;
}

enum TxType {
  sale('مبيعات', true),
  customerPayment('تحصيل من عميل', true),
  purchaseRefund('رد من مورد', true),
  cashIn('إيداع نقدي', true),
  deposit('إضافة رأس مال', true),
  purchase('مشتريات', false),
  supplierPayment('دفع لمورد', false),
  saleRefund('رد لعميل', false),
  expense('مصروف', false),
  withdrawal('سحب', false),
  cashOut('صرف نقدي', false);

  const TxType(this.label, this.isIn);
  final String label;
  final bool isIn;

  /// Types the user can create manually from the cash screen.
  static const manual = [cashIn, cashOut, expense, deposit, withdrawal];
}

enum StockAdjustReason {
  count('جرد / تصحيح عدد'),
  damaged('تالف'),
  expired('منتهي الصلاحية'),
  lost('فقد'),
  gift('هدية / عينة'),
  other('أخرى');

  const StockAdjustReason(this.label);
  final String label;
}

const expenseCategories = [
  'إيجار',
  'كهرباء ومياه',
  'رواتب',
  'نقل وشحن',
  'صيانة',
  'ضيافة',
  'إنترنت واتصالات',
  'أخرى',
];

const productUnits = ['قطعة', 'علبة', 'كرتونة', 'كيلو', 'لتر', 'باكو', 'دستة', 'متر'];
