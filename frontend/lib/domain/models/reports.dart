import 'enums.dart';
import 'invoice.dart';
import 'product.dart';

class DateRange {
  const DateRange(this.from, this.to);
  final DateTime from;

  /// Inclusive end (end of day).
  final DateTime to;

  bool contains(DateTime d) => !d.isBefore(from) && !d.isAfter(to);

  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime endOfDay(DateTime d) => DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

  factory DateRange.today() {
    final n = DateTime.now();
    return DateRange(startOfDay(n), endOfDay(n));
  }

  factory DateRange.lastDays(int days) {
    final n = DateTime.now();
    return DateRange(startOfDay(n.subtract(Duration(days: days - 1))), endOfDay(n));
  }

  factory DateRange.thisMonth() {
    final n = DateTime.now();
    return DateRange(DateTime(n.year, n.month), endOfDay(n));
  }

  int get days => DateTime(to.year, to.month, to.day).difference(DateTime(from.year, from.month, from.day)).inDays + 1;
}

class DayValue {
  const DayValue(this.day, this.value);
  final DateTime day;
  final double value;
}

class NamedValue {
  const NamedValue(this.name, this.value, {this.count = 0, this.extra = 0, this.id});
  final String name;
  final double value;

  /// Quantity or number of documents.
  final double count;

  /// Secondary metric (e.g. profit).
  final double extra;
  final String? id;
}

class DashboardData {
  const DashboardData({
    required this.todaySales,
    required this.todaySalesCount,
    required this.todayPurchases,
    required this.todayProfit,
    required this.todayExpenses,
    required this.cashBalance,
    required this.drawerOpen,
    required this.bankBalance,
    required this.customerDebts,
    required this.supplierDebts,
    required this.lowStock,
    required this.outOfStockCount,
    required this.recentSales,
    required this.recentPurchases,
    required this.salesByDay,
    required this.purchasesByDay,
    required this.profitByDay,
    required this.topProducts,
    required this.yesterdaySales,
  });

  final double todaySales;
  final int todaySalesCount;
  final double todayPurchases;
  final double todayProfit;
  final double todayExpenses;
  final double cashBalance;
  final bool drawerOpen;
  final double bankBalance;
  final double customerDebts;
  final double supplierDebts;
  final List<Product> lowStock;
  final int outOfStockCount;
  final List<Invoice> recentSales;
  final List<Invoice> recentPurchases;
  final List<DayValue> salesByDay;
  final List<DayValue> purchasesByDay;
  final List<DayValue> profitByDay;
  final List<NamedValue> topProducts;
  final double yesterdaySales;
}

enum SalesGroupBy {
  day('يومي'),
  week('أسبوعي'),
  month('شهري'),
  customer('حسب العميل'),
  product('حسب المنتج'),
  category('حسب الفئة'),
  paymentMethod('حسب طريقة الدفع');

  const SalesGroupBy(this.label);
  final String label;

  bool get isTime => this == day || this == week || this == month;
}

enum PurchasesGroupBy {
  day('يومي'),
  month('شهري'),
  supplier('حسب المورد'),
  product('حسب المنتج');

  const PurchasesGroupBy(this.label);
  final String label;

  bool get isTime => this == day || this == month;
}

class TradeReportFilter {
  const TradeReportFilter({
    required this.range,
    this.partyId,
    this.productId,
    this.categoryId,
  });

  final DateRange range;
  final String? partyId;
  final String? productId;
  final String? categoryId;

  TradeReportFilter copyWith({
    DateRange? range,
    String? Function()? partyId,
    String? Function()? productId,
    String? Function()? categoryId,
  }) =>
      TradeReportFilter(
        range: range ?? this.range,
        partyId: partyId != null ? partyId() : this.partyId,
        productId: productId != null ? productId() : this.productId,
        categoryId: categoryId != null ? categoryId() : this.categoryId,
      );
}

class TradeReport {
  const TradeReport({
    required this.type,
    required this.invoicesCount,
    required this.gross,
    required this.discounts,
    required this.returns,
    required this.cost,
    required this.paid,
    required this.due,
    required this.byDay,
    required this.byWeek,
    required this.byMonth,
    required this.byParty,
    required this.byProduct,
    required this.byCategory,
    required this.byPaymentMethod,
  });

  final InvoiceType type;
  final int invoicesCount;

  /// Sum of invoice totals (after discounts).
  final double gross;
  final double discounts;
  final double returns;

  /// Cost of goods (net of returns) — sales only.
  final double cost;
  final double paid;
  final double due;
  final List<NamedValue> byDay;
  final List<NamedValue> byWeek;
  final List<NamedValue> byMonth;
  final List<NamedValue> byParty;
  final List<NamedValue> byProduct;
  final List<NamedValue> byCategory;
  final List<NamedValue> byPaymentMethod;

  double get net => gross - returns;
  double get profit => net - cost;
  double get average => invoicesCount == 0 ? 0 : gross / invoicesCount;
}

enum StockReportView {
  current('المخزون الحالي'),
  low('منخفض'),
  out('نفد'),
  movement('حركة المخزون');

  const StockReportView(this.label);
  final String label;
}

class StockReport {
  const StockReport({
    required this.products,
    required this.categoryNames,
    required this.movements,
    required this.productNames,
  });

  final List<Product> products;
  final Map<String, String> categoryNames;
  final List<StockMovement> movements;
  final Map<String, String> productNames;

  double get costValue => products.fold(0, (s, p) => s + p.stockValue);
  double get retailValue => products.fold(0, (s, p) => s + (p.stock > 0 ? p.stock * p.sellingPrice : 0));
  List<Product> get low => products.where((p) => p.isLowStock).toList();
  List<Product> get out => products.where((p) => p.isOutOfStock).toList();
}

class FinancialReport {
  const FinancialReport({
    required this.range,
    required this.revenue,
    required this.salesReturns,
    required this.cogs,
    required this.expenses,
    required this.expensesByCategory,
    required this.customerDebts,
    required this.supplierDebts,
    required this.topDebtors,
    required this.topCreditors,
    required this.cashIn,
    required this.cashOut,
    required this.flowByType,
    required this.flowByDay,
    required this.cashBalance,
    required this.bankBalance,
  });

  final DateRange range;
  final double revenue;
  final double salesReturns;
  final double cogs;
  final double expenses;
  final List<NamedValue> expensesByCategory;
  final double customerDebts;
  final double supplierDebts;
  final List<NamedValue> topDebtors;
  final List<NamedValue> topCreditors;
  final double cashIn;
  final double cashOut;
  final Map<TxType, double> flowByType;
  final List<NamedValue> flowByDay;
  final double cashBalance;
  final double bankBalance;

  double get netRevenue => revenue - salesReturns;
  double get grossProfit => netRevenue - cogs;
  double get netProfit => grossProfit - expenses;
  double get netFlow => cashIn - cashOut;
}
