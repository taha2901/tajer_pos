import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/nav.dart';
import '../../app/session_cubit.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../common/pickers.dart';
import '../common/product_widgets.dart';
import 'cart_cubit.dart';
import 'checkout_screen.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartCubit>();
    return BlocBuilder<CartCubit, CartState>(
      builder: (context, s) => Scaffold(
        appBar: AppBar(
          title: Text('السلة (${s.lines.length})'),
          actions: [
            if (!s.isEmpty)
              TextButton(
                onPressed: () async {
                  if (await confirmDialog(context, title: 'إفراغ السلة؟', message: 'سيتم حذف جميع الأصناف.', confirmLabel: 'إفراغ', destructive: true)) {
                    cart.clear();
                  }
                },
                child: const Text('إفراغ'),
              ),
          ],
        ),
        body: s.isEmpty
            ? EmptyView(
                icon: Icons.shopping_basket_outlined,
                title: 'السلة فارغة',
                message: 'أضف منتجات بالبحث أو مسح الباركود',
                actionLabel: 'إضافة منتجات',
                onAction: () => Navigator.pop(context),
              )
            : MaxWidth(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    const SizedBox(height: 8),
                    _CustomerTile(state: s),
                    const SectionHeader('الأصناف', padding: EdgeInsets.fromLTRB(16, 16, 16, 8)),
                    ListGroup(children: [for (final l in s.lines) _LineTile(line: l)]),
                    const SizedBox(height: 16),
                    ListGroup(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.discount_outlined),
                          title: const Text('خصم على الفاتورة'),
                          trailing: Text(s.discount > 0 ? '- ${Fmt.money(s.discount)}' : 'إضافة',
                              style: context.text.labelLarge?.copyWith(color: s.discount > 0 ? context.palette.success : context.colors.primary)),
                          onTap: () => showDiscountSheet(context),
                        ),
                      ],
                    ),
                    Padding(padding: const EdgeInsets.all(16), child: CartTotals(state: s)),
                  ],
                ),
              ),
        bottomNavigationBar: s.isEmpty
            ? null
            : BottomBar(
                child: FilledButton(
                  onPressed: () => context.push(const CheckoutScreen()),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [const Text('متابعة للدفع'), Text(Fmt.money(s.total))],
                  ),
                ),
              ),
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.state});
  final CartState state;

  @override
  Widget build(BuildContext context) {
    final c = state.customer;
    return ListGroup(
      children: [
        ListTile(
          leading: Initials(c?.name ?? 'عميل نقدي', tone: c == null ? Tone.neutral : Tone.primary),
          title: Text(c?.name ?? 'عميل نقدي'),
          subtitle: Text(c == null ? 'اختر عميلاً للبيع الآجل' : c.hasDebt ? 'رصيد سابق ${Fmt.money(c.balance)}' : 'لا يوجد رصيد سابق'),
          trailing: TextButton(
            onPressed: () async {
              final p = await pickParty(context, PartyType.customer, allowWalkIn: true);
              if (p != null && context.mounted) context.read<CartCubit>().setCustomer(p.id == walkInCustomer.id ? null : p);
            },
            child: Text(c == null ? 'اختيار' : 'تغيير'),
          ),
        ),
      ],
    );
  }
}

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line});
  final CartLine line;

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartCubit>();
    return Dismissible(
      key: ValueKey(line.product.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: context.palette.dangerBg,
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Icon(Icons.delete_outline, color: context.palette.danger),
      ),
      onDismissed: (_) => cart.remove(line.product.id),
      child: InkWell(
        onTap: () => showLineEditor(context, line),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              ProductThumb(line.product, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line.product.name, style: context.text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Wrap(
                      spacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('${Fmt.money(line.unitPrice)} × ${Fmt.qty(line.qty)}', style: context.text.bodySmall),
                        if (line.priceEdited) const StatusPill('سعر معدّل', tone: Tone.info),
                        if (line.discount > 0) StatusPill('خصم ${Fmt.money(line.discount)}', tone: Tone.success),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(Fmt.money(line.total), style: context.text.titleSmall?.copyWith(color: context.colors.primary)),
                  ],
                ),
              ),
              QtyStepper(
                compact: true,
                value: line.qty,
                onTapValue: () => showLineEditor(context, line),
                onChanged: (v) {
                  final err = cart.setQty(line.product.id, v);
                  if (err != null) showToast(context, err, kind: ToastKind.error);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CartTotals extends StatelessWidget {
  const CartTotals({super.key, required this.state});
  final CartState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    return AppCard(
      child: Column(
        children: [
          InfoRow('الإجمالي قبل الخصم', Fmt.money(s.gross)),
          if (s.linesDiscount > 0) InfoRow('خصم الأصناف', '- ${Fmt.money(s.linesDiscount)}', valueColor: context.palette.success),
          if (s.discount > 0) InfoRow('خصم الفاتورة', '- ${Fmt.money(s.discount)}', valueColor: context.palette.success),
          const Divider(height: 20),
          InfoRow('الإجمالي', Fmt.money(s.total), large: true),
        ],
      ),
    );
  }
}

/// Edit qty / price / discount of a cart line — honours permissions.
Future<void> showLineEditor(BuildContext context, CartLine line) {
  final cart = context.read<CartCubit>();
  final perms = context.perms;
  final qty = TextEditingController(text: Fmt.qty(line.qty));
  final price = TextEditingController(text: Fmt.qty(line.unitPrice));
  final disc = TextEditingController(text: line.discount == 0 ? '' : Fmt.qty(line.discount));
  final form = GlobalKey<FormState>();
  final canPrice = perms.canEditPrice;

  return showAppSheet<void>(
    context,
    builder: (ctx) => SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ProductThumb(line.product, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(line.product.name, style: ctx.text.titleMedium),
                        Text('المتاح ${Fmt.qty(line.product.stock)} ${line.product.unit} • قطاعي ${Fmt.money(line.product.sellingPrice)}', style: ctx.text.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              MoneyField(controller: qty, label: 'الكمية', suffix: line.product.unit, validator: (v) => requiredNumber(v, allowZero: false)),
              const SizedBox(height: 12),
              MoneyField(
                controller: price,
                label: 'سعر الوحدة',
                helper: canPrice ? 'سعر التكلفة ${Fmt.money(line.product.purchasePrice)}' : 'تعديل السعر غير مسموح لصلاحيتك',
                validator: (v) {
                  final e = requiredNumber(v);
                  if (e != null) return e;
                  if (parseNum(v)! < line.product.purchasePrice && !perms.isAdmin) return 'لا يمكن البيع بأقل من التكلفة';
                  return null;
                },
              ).withEnabled(canPrice),
              const SizedBox(height: 12),
              MoneyField(
                controller: disc,
                label: 'خصم على الصنف (مبلغ)',
                helper: perms.isAdmin ? null : 'الحد الأقصى ${Fmt.percent(perms.maxDiscountPercent)} من قيمة الصنف',
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  final d = parseNum(v);
                  final q = parseNum(qty.text) ?? 0;
                  final p = parseNum(price.text) ?? 0;
                  if (d == null || d < 0) return 'قيمة غير صحيحة';
                  if (d > q * p) return 'الخصم أكبر من قيمة الصنف';
                  if (q * p > 0 && d / (q * p) * 100 > perms.maxDiscountPercent + 0.001) {
                    return 'تجاوزت الحد المسموح (${Fmt.percent(perms.maxDiscountPercent)})';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  IconButton.outlined(
                    onPressed: () {
                      cart.remove(line.product.id);
                      Navigator.pop(ctx);
                    },
                    icon: Icon(Icons.delete_outline, color: ctx.palette.danger),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        if (!form.currentState!.validate()) return;
                        final q = parseNum(qty.text)!;
                        final err = cart.setQty(line.product.id, q);
                        if (err != null) {
                          showToast(ctx, err, kind: ToastKind.error);
                          return;
                        }
                        cart.updateLine(
                          line.product.id,
                          unitPrice: canPrice ? parseNum(price.text) : null,
                          discount: parseNum(disc.text) ?? 0,
                        );
                        Navigator.pop(ctx);
                      },
                      child: const Text('حفظ'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Invoice discount as amount or percentage.
Future<void> showDiscountSheet(BuildContext context) {
  final cart = context.read<CartCubit>();
  final perms = context.perms;
  final s = cart.state;
  var percent = false;
  final ctrl = TextEditingController(text: s.discount == 0 ? '' : Fmt.qty(s.discount));
  final form = GlobalKey<FormState>();

  return showAppSheet<void>(
    context,
    title: 'خصم على الفاتورة',
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        double amount() {
          final v = parseNum(ctrl.text) ?? 0;
          return percent ? r2(s.subtotal * v / 100) : v;
        }

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('مبلغ'), icon: Icon(Icons.payments_outlined)),
                      ButtonSegment(value: true, label: Text('نسبة %'), icon: Icon(Icons.percent)),
                    ],
                    selected: {percent},
                    onSelectionChanged: (v) => setState(() {
                      percent = v.first;
                      ctrl.clear();
                    }),
                  ),
                  const SizedBox(height: 14),
                  MoneyField(
                    controller: ctrl,
                    label: percent ? 'نسبة الخصم' : 'قيمة الخصم',
                    suffix: percent ? '%' : Fmt.currency,
                    autofocus: true,
                    big: true,
                    onChanged: (_) => setState(() {}),
                    validator: (_) {
                      final a = amount();
                      if (a < 0 || a > s.subtotal) return 'الخصم أكبر من الإجمالي';
                      final pct = s.gross == 0 ? 0 : (s.linesDiscount + a) / s.gross * 100;
                      if (pct > perms.maxDiscountPercent + 0.001) {
                        return 'الحد الأقصى للخصم ${Fmt.percent(perms.maxDiscountPercent)}';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final p in [2, 5, 10])
                        if (p <= perms.maxDiscountPercent)
                          ActionChip(
                            label: Text('$p%'),
                            onPressed: () => setState(() {
                              percent = true;
                              ctrl.text = '$p';
                            }),
                          ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  InfoRow('الإجمالي بعد الخصم', Fmt.money(s.subtotal - amount()), bold: true),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (s.discount > 0) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              cart.setDiscount(0);
                              Navigator.pop(ctx);
                            },
                            child: const Text('إزالة الخصم'),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            if (!form.currentState!.validate()) return;
                            cart.setDiscount(amount());
                            Navigator.pop(ctx);
                          },
                          child: const Text('تطبيق'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

extension on Widget {
  Widget withEnabled(bool enabled) => enabled ? this : IgnorePointer(child: Opacity(opacity: 0.55, child: this));
}
