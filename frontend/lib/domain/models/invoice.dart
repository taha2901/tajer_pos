import 'enums.dart';

class InvoiceLine {
  const InvoiceLine({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.qty,
    required this.unitPrice,
    this.discount = 0,
    this.costPrice = 0,
    this.returnedQty = 0,
  });

  final String productId;
  final String productName;
  final String unit;
  final double qty;
  final double unitPrice;

  /// Line discount amount (not percent).
  final double discount;

  /// Cost snapshot at time of sale (used for profit).
  final double costPrice;
  final double returnedQty;

  double get gross => qty * unitPrice;
  double get total => gross - discount;
  double get netUnitPrice => qty == 0 ? 0 : total / qty;
  double get returnableQty => qty - returnedQty;

  InvoiceLine copyWith({double? returnedQty}) => InvoiceLine(
        productId: productId,
        productName: productName,
        unit: unit,
        qty: qty,
        unitPrice: unitPrice,
        discount: discount,
        costPrice: costPrice,
        returnedQty: returnedQty ?? this.returnedQty,
      );
}

class PaymentLine {
  const PaymentLine(this.method, this.amount, {this.reference = ''});
  final PaymentMethod method;
  final double amount;
  final String reference;
}

class Invoice {
  const Invoice({
    required this.id,
    required this.number,
    required this.type,
    required this.date,
    required this.partyName,
    required this.lines,
    required this.discount,
    required this.paid,
    required this.payments,
    required this.user,
    this.partyId,
    this.priceTier = PriceTier.retail,
    this.returnedAmount = 0,
    this.note = '',
    this.supplierRef = '',
  });

  final String id;
  final String number;
  final InvoiceType type;
  final DateTime date;
  final String? partyId;
  final String partyName;
  final PriceTier priceTier;
  final List<InvoiceLine> lines;

  /// Invoice-level discount amount.
  final double discount;

  /// Total paid toward this invoice (initial payments + allocated later payments − cash refunds).
  final double paid;
  final List<PaymentLine> payments;
  final double returnedAmount;
  final String user;
  final String note;

  /// Supplier's own invoice number (purchases only).
  final String supplierRef;

  double get subtotal => lines.fold(0, (s, l) => s + l.total);
  double get total => subtotal - discount;
  double get netTotal => total - returnedAmount;
  double get due {
    final d = total - returnedAmount - paid;
    return d.abs() < 0.005 ? 0 : d;
  }

  double get itemsCount => lines.fold(0, (s, l) => s + l.qty);
  double get linesDiscount => lines.fold(0, (s, l) => s + l.discount);
  double get totalDiscount => linesDiscount + discount;

  /// Share of the invoice discount kept per currency unit of line total.
  double get discountFactor => subtotal == 0 ? 1 : total / subtotal;

  double get cost => lines.fold(0, (s, l) => s + l.costPrice * l.qty);
  double get profit => total - cost;

  bool get isWalkIn => partyId == null;
  bool get hasReturns => returnedAmount > 0.009;
  bool get fullyReturned => lines.every((l) => l.returnedQty >= l.qty - 0.0001);

  PaymentStatus get paymentStatus {
    if (due <= 0.009) return PaymentStatus.paid;
    if (paid <= 0.009) return PaymentStatus.unpaid;
    return PaymentStatus.partial;
  }

  Invoice copyWith({
    List<InvoiceLine>? lines,
    double? paid,
    double? returnedAmount,
  }) =>
      Invoice(
        id: id,
        number: number,
        type: type,
        date: date,
        partyId: partyId,
        partyName: partyName,
        priceTier: priceTier,
        lines: lines ?? this.lines,
        discount: discount,
        paid: paid ?? this.paid,
        payments: payments,
        returnedAmount: returnedAmount ?? this.returnedAmount,
        user: user,
        note: note,
        supplierRef: supplierRef,
      );
}

/// What the UI sends to create a sale or purchase.
class InvoiceDraft {
  const InvoiceDraft({
    required this.type,
    required this.lines,
    required this.payments,
    this.partyId,
    this.priceTier = PriceTier.retail,
    this.discount = 0,
    this.note = '',
    this.supplierRef = '',
    this.overrideCreditLimit = false,
  });

  final InvoiceType type;
  final String? partyId;
  final PriceTier priceTier;
  final List<DraftLine> lines;
  final double discount;
  final List<PaymentLine> payments;
  final String note;
  final String supplierRef;

  /// Admin explicitly accepted going over the credit limit.
  final bool overrideCreditLimit;

  double get subtotal => lines.fold(0, (s, l) => s + l.total);
  double get total => subtotal - discount;
  double get paid => payments.fold(0, (s, p) => s + p.amount);
}

class DraftLine {
  const DraftLine({
    required this.productId,
    required this.qty,
    required this.unitPrice,
    this.discount = 0,
  });

  final String productId;
  final double qty;
  final double unitPrice;
  final double discount;

  double get total => qty * unitPrice - discount;
}

enum InvoiceStatusFilter {
  all('الكل'),
  paid('مدفوعة'),
  due('عليها متبقي'),
  returned('بها مرتجع');

  const InvoiceStatusFilter(this.label);
  final String label;
}

class InvoiceQuery {
  const InvoiceQuery(
    this.type, {
    this.search = '',
    this.from,
    this.to,
    this.partyId,
    this.status = InvoiceStatusFilter.all,
  });

  final InvoiceType type;
  final String search;
  final DateTime? from;
  final DateTime? to;
  final String? partyId;
  final InvoiceStatusFilter status;

  InvoiceQuery copyWith({
    String? search,
    DateTime? Function()? from,
    DateTime? Function()? to,
    InvoiceStatusFilter? status,
  }) =>
      InvoiceQuery(
        type,
        search: search ?? this.search,
        from: from != null ? from() : this.from,
        to: to != null ? to() : this.to,
        partyId: partyId,
        status: status ?? this.status,
      );
}

class ReturnLine {
  const ReturnLine({
    required this.productId,
    required this.productName,
    required this.unit,
    required this.qty,
    required this.unitPrice,
    this.costPrice = 0,
  });

  final String productId;
  final String productName;
  final String unit;
  final double qty;

  /// Net unit value refunded (after line + invoice discount).
  final double unitPrice;
  final double costPrice;

  double get total => qty * unitPrice;
}

class ReturnDoc {
  const ReturnDoc({
    required this.id,
    required this.number,
    required this.type,
    required this.invoiceId,
    required this.invoiceNumber,
    required this.partyName,
    required this.date,
    required this.lines,
    required this.creditApplied,
    required this.cashRefund,
    required this.refundMethod,
    required this.user,
    this.partyId,
    this.reason = '',
  });

  final String id;
  final String number;
  final InvoiceType type;
  final String invoiceId;
  final String invoiceNumber;
  final String? partyId;
  final String partyName;
  final DateTime date;
  final List<ReturnLine> lines;

  /// Amount deducted from the invoice due (party balance).
  final double creditApplied;

  /// Amount refunded in money.
  final double cashRefund;
  final PaymentMethod refundMethod;
  final String user;
  final String reason;

  double get total => lines.fold(0, (s, l) => s + l.total);
  double get cost => lines.fold(0, (s, l) => s + l.costPrice * l.qty);
}

class ReturnDraft {
  const ReturnDraft({
    required this.invoiceId,
    required this.qtyByProduct,
    this.refundMethod = PaymentMethod.cash,
    this.reason = '',
  });

  final String invoiceId;
  final Map<String, double> qtyByProduct;
  final PaymentMethod refundMethod;
  final String reason;
}

/// Pure preview of how a return will be settled (used by UI and engine).
class ReturnSettlement {
  const ReturnSettlement(this.total, this.creditApplied, this.cashRefund);
  final double total;
  final double creditApplied;
  final double cashRefund;

  factory ReturnSettlement.of(Invoice invoice, Map<String, double> qtyByProduct) {
    var total = 0.0;
    for (final line in invoice.lines) {
      final q = qtyByProduct[line.productId] ?? 0;
      total += q * line.netUnitPrice * invoice.discountFactor;
    }
    total = (total * 100).roundToDouble() / 100;
    final due = invoice.due < 0 ? 0.0 : invoice.due;
    final credit = total < due ? total : due;
    return ReturnSettlement(total, credit, total - credit);
  }
}
