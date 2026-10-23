enum AlertKind {
  lowStock('مخزون منخفض'),
  outOfStock('نفد المخزون'),
  customerDebtDue('مديونية عميل مستحقة'),
  customerOverLimit('تجاوز حد الائتمان'),
  supplierPaymentDue('مستحق لمورد'),
  largeExpense('مصروف كبير'),
  closingReminder('تذكير إقفال اليومية');

  const AlertKind(this.label);
  final String label;
}

enum AlertSeverity { info, warning, critical }

class AppAlert {
  const AppAlert({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.date,
    required this.severity,
    this.targetId,
    this.isRead = false,
  });

  /// Stable id derived from the subject so read-state survives recomputation.
  final String id;
  final AlertKind kind;
  final String title;
  final String body;
  final DateTime date;
  final AlertSeverity severity;

  /// Product / party id to open when tapped.
  final String? targetId;
  final bool isRead;
}

enum SearchScope {
  all('الكل'),
  products('المنتجات'),
  customers('العملاء'),
  suppliers('الموردين'),
  invoices('الفواتير');

  const SearchScope(this.label);
  final String label;
}

enum SearchHitKind { product, customer, supplier, sale, purchase }

class SearchHit {
  const SearchHit({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    this.trailing = '',
  });

  final SearchHitKind kind;
  final String id;
  final String title;
  final String subtitle;
  final String trailing;
}
