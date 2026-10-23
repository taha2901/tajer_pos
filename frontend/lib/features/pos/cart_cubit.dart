import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/format.dart';
import '../../domain/models/models.dart';

class CartLine {
  const CartLine({
    required this.product,
    required this.qty,
    required this.unitPrice,
    this.discount = 0,
    this.priceEdited = false,
  });

  final Product product;
  final double qty;
  final double unitPrice;
  final double discount;

  /// Manually overridden price — kept when the price tier changes.
  final bool priceEdited;

  double get gross => qty * unitPrice;
  double get total => gross - discount;

  CartLine copyWith({Product? product, double? qty, double? unitPrice, double? discount, bool? priceEdited}) => CartLine(
        product: product ?? this.product,
        qty: qty ?? this.qty,
        unitPrice: unitPrice ?? this.unitPrice,
        discount: discount ?? this.discount,
        priceEdited: priceEdited ?? this.priceEdited,
      );
}

class CartState {
  const CartState({
    this.lines = const [],
    this.customer,
    this.tier = PriceTier.retail,
    this.discount = 0,
    this.note = '',
    this.held = const [],
  });

  final List<CartLine> lines;
  final Party? customer;
  final PriceTier tier;

  /// Invoice-level discount amount.
  final double discount;
  final String note;

  /// Parked carts (hold / resume).
  final List<CartState> held;

  bool get isEmpty => lines.isEmpty;
  double get itemsCount => lines.fold(0, (s, l) => s + l.qty);
  double get gross => lines.fold(0, (s, l) => s + l.gross);
  double get linesDiscount => lines.fold(0, (s, l) => s + l.discount);
  double get subtotal => lines.fold(0, (s, l) => s + l.total);
  double get total => r2(subtotal - discount);
  double get totalDiscount => linesDiscount + discount;
  double get discountPercent => gross == 0 ? 0 : totalDiscount / gross * 100;
  double qtyOf(String productId) => lines.where((l) => l.product.id == productId).fold(0, (s, l) => s + l.qty);

  InvoiceDraft toDraft({required List<PaymentLine> payments, bool overrideCreditLimit = false}) => InvoiceDraft(
        type: InvoiceType.sale,
        partyId: customer?.id,
        priceTier: tier,
        lines: [
          for (final l in lines) DraftLine(productId: l.product.id, qty: l.qty, unitPrice: l.unitPrice, discount: l.discount),
        ],
        discount: discount,
        payments: payments,
        note: note,
        overrideCreditLimit: overrideCreditLimit,
      );

  CartState copyWith({
    List<CartLine>? lines,
    Party? Function()? customer,
    PriceTier? tier,
    double? discount,
    String? note,
    List<CartState>? held,
  }) =>
      CartState(
        lines: lines ?? this.lines,
        customer: customer != null ? customer() : this.customer,
        tier: tier ?? this.tier,
        discount: discount ?? this.discount,
        note: note ?? this.note,
        held: held ?? this.held,
      );
}

/// The POS cart. Pure client state until checkout creates the invoice.
class CartCubit extends Cubit<CartState> {
  CartCubit({required this.allowNegativeStock}) : super(const CartState());

  final bool Function() allowNegativeStock;

  /// Adds [qty] of [product]. Returns an error message or null.
  String? add(Product product, {double qty = 1}) {
    if (!product.isActive) return '"${product.name}" موقوف عن البيع';
    final current = state.qtyOf(product.id);
    if (!allowNegativeStock() && current + qty > product.stock + 0.0001) {
      return product.stock <= 0
          ? 'نفد مخزون "${product.name}"'
          : 'المتاح من "${product.name}" ${Fmt.qty(product.stock)} فقط';
    }
    final idx = state.lines.indexWhere((l) => l.product.id == product.id);
    final lines = [...state.lines];
    if (idx >= 0) {
      lines[idx] = lines[idx].copyWith(qty: lines[idx].qty + qty, product: product);
    } else {
      lines.insert(0, CartLine(product: product, qty: qty, unitPrice: product.priceFor(state.tier)));
    }
    emit(state.copyWith(lines: lines));
    return null;
  }

  String? setQty(String productId, double qty) {
    if (qty <= 0) {
      remove(productId);
      return null;
    }
    final idx = state.lines.indexWhere((l) => l.product.id == productId);
    if (idx < 0) return null;
    final line = state.lines[idx];
    if (!allowNegativeStock() && qty > line.product.stock + 0.0001) {
      return 'المتاح من "${line.product.name}" ${Fmt.qty(line.product.stock)} فقط';
    }
    final lines = [...state.lines]..[idx] = line.copyWith(qty: qty, discount: line.discount.clamp(0, qty * line.unitPrice).toDouble());
    emit(state.copyWith(lines: lines));
    return null;
  }

  void updateLine(String productId, {double? qty, double? unitPrice, double? discount}) {
    final idx = state.lines.indexWhere((l) => l.product.id == productId);
    if (idx < 0) return;
    final l = state.lines[idx];
    final lines = [...state.lines]
      ..[idx] = l.copyWith(
        qty: qty,
        unitPrice: unitPrice,
        discount: discount,
        priceEdited: l.priceEdited || (unitPrice != null && unitPrice != l.unitPrice),
      );
    emit(state.copyWith(lines: lines));
  }

  void remove(String productId) =>
      emit(state.copyWith(lines: state.lines.where((l) => l.product.id != productId).toList()));

  void setDiscount(double amount) => emit(state.copyWith(discount: amount.clamp(0, state.subtotal).toDouble()));

  void setNote(String note) => emit(state.copyWith(note: note));

  /// Single selling price for everyone — the customer only matters for credit.
  void setCustomer(Party? customer) => emit(state.copyWith(customer: () => customer));

  /// Refresh product snapshots (e.g. stock changed elsewhere).
  void refreshProducts(Map<String, Product> latest) {
    if (state.lines.isEmpty) return;
    emit(state.copyWith(lines: [for (final l in state.lines) l.copyWith(product: latest[l.product.id] ?? l.product)]));
  }

  void clear() => emit(CartState(held: state.held));

  void hold() {
    if (state.isEmpty) return;
    emit(CartState(held: [...state.held, state.copyWith(held: const [])]));
  }

  void resume(int index) {
    final held = [...state.held];
    final cart = held.removeAt(index);
    // Park the current cart if it has items.
    if (!state.isEmpty) held.add(state.copyWith(held: const []));
    emit(cart.copyWith(held: held));
  }

  void dropHeld(int index) => emit(state.copyWith(held: [...state.held]..removeAt(index)));
}
