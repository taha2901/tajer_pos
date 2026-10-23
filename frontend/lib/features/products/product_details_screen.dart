import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/nav.dart';
import '../../app/session_cubit.dart';
import '../../app/theme.dart';
import '../../core/data_bus.dart';
import '../../core/format.dart';
import '../../core/query_cubit.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../common/export.dart';
import '../common/product_widgets.dart';
import '../pos/cart_cubit.dart';
import '../purchases/purchase_form_screen.dart';
import '../shell/home_shell.dart';
import 'product_form_screen.dart';
import 'stock_history_screen.dart';

typedef _Data = (Product, String categoryName);

class ProductDetailsScreen extends StatelessWidget {
  const ProductDetailsScreen({super.key, required this.productId});
  final String productId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => simpleQuery<_Data>(
        () async {
          final repo = c.read<ProductRepository>();
          final p = await repo.getProduct(productId);
          final cats = await repo.getCategories();
          return (p, cats.where((x) => x.id == p.categoryId).firstOrNull?.name ?? '');
        },
        bus: c.read<DataBus>(),
        topics: const {DataTopic.products},
      ),
      child: BlocBuilder<QueryCubit<_Data, Null>, ViewState<_Data>>(
        builder: (context, state) {
          final p = state.data?.$1;
          return Scaffold(
            appBar: AppBar(
              actions: [
                if (p != null) ...[
                  IconButton(
                    tooltip: 'تعديل',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => context.push(ProductFormScreen(product: p)),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) => switch (v) {
                      'history' => context.push(StockHistoryScreen(product: p)),
                      'adjust' => showStockAdjustSheet(context, p),
                      _ => _printLabel(context, p),
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'history', child: Text('سجل المخزون')),
                      if (context.perms.canAdjustStock) const PopupMenuItem(value: 'adjust', child: Text('تسوية المخزون')),
                      const PopupMenuItem(value: 'label', child: Text('طباعة ملصق')),
                    ],
                  ),
                ],
              ],
            ),
            body: AsyncBody<_Data>(
              state: state,
              onRetry: context.read<QueryCubit<_Data, Null>>().load,
              builder: (d) => _Body(product: d.$1, category: d.$2),
            ),
            bottomNavigationBar: p == null
                ? null
                : BottomBar(
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => context.push(PurchaseFormScreen(product: p)),
                            child: const Text('شراء'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: p.isActive
                                ? () {
                                    final err = context.read<CartCubit>().add(p);
                                    if (err != null) {
                                      showToast(context, err, kind: ToastKind.error);
                                      return;
                                    }
                                    context.read<ShellCubit>().go(ShellTab.pos);
                                    Navigator.of(context).popUntil((r) => r.isFirst);
                                  }
                                : null,
                            child: const Text('إضافة للبيع'),
                          ),
                        ),
                      ],
                    ),
                  ),
          );
        },
      ),
    );
  }

  static void _printLabel(BuildContext context, Product p) => context.push(PrintPreviewScreen(
        title: 'ملصق ${p.name}',
        receipt: true,
        child: Column(
          children: [
            Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.black)),
            const SizedBox(height: 6),
            BarcodeWidget(barcode: Barcode.code128(), data: p.barcode, height: 60, width: 220, style: const TextStyle(color: Colors.black)),
            const SizedBox(height: 6),
            Text(Fmt.money(p.sellingPrice), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black)),
          ],
        ),
      ));
}

class _Body extends StatelessWidget {
  const _Body({required this.product, required this.category});
  final Product product;
  final String category;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final pal = context.palette;
    final (stockColor, stockLabel) = p.isOutOfStock
        ? (pal.danger, 'نفد المخزون')
        : p.isLowStock
            ? (pal.warning, 'مخزون منخفض')
            : (pal.success, 'متوفر');

    return MaxWidth(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Center(child: ProductThumb(p, size: 88)),
          const SizedBox(height: 16),
          Text(p.name, style: context.text.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            [category, p.unit].where((e) => e.isNotEmpty).join(' • '),
            style: context.text.bodyMedium?.copyWith(color: pal.muted),
            textAlign: TextAlign.center,
          ),
          if (!p.isActive) ...[
            const SizedBox(height: 10),
            const Center(child: StatusPill('موقوف عن البيع')),
          ],
          const SizedBox(height: 28),
          SoftPanel(
            child: Row(
              children: [
                Expanded(child: _Figure('سعر البيع', Fmt.money(p.sellingPrice), color: context.colors.primary)),
                if (context.perms.isAdmin) Expanded(child: _Figure('سعر الشراء', Fmt.money(p.purchasePrice))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SoftPanel(
            child: Row(
              children: [
                Expanded(
                  child: _Figure(
                    'المخزون',
                    '${Fmt.qty(p.stock)} ${p.unit}',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 7, height: 7, decoration: BoxDecoration(color: stockColor, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text(stockLabel, style: context.text.labelMedium?.copyWith(color: stockColor)),
                      ],
                    ),
                  ),
                ),
                Expanded(child: _Figure('تنبيه عند', '${Fmt.qty(p.minStock)} ${p.unit}')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SoftPanel(
            child: Column(
              children: [
                BarcodeWidget(
                  barcode: p.barcode.length == 13 && RegExp(r'^\d+$').hasMatch(p.barcode) ? Barcode.ean13() : Barcode.code128(),
                  data: p.barcode,
                  height: 64,
                  width: 210,
                  color: context.colors.onSurface,
                  style: TextStyle(color: context.colors.onSurface, fontSize: 13, letterSpacing: 1),
                  errorBuilder: (_, _) => Text(p.barcode),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, {this.color, this.trailing});
  final String label;
  final String value;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.labelMedium?.copyWith(color: context.palette.muted)),
          const SizedBox(height: 6),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: context.text.titleLarge?.copyWith(color: color))),
          if (trailing != null) ...[const SizedBox(height: 6), trailing!],
        ],
      );
}

class StockMoveTile extends StatelessWidget {
  const StockMoveTile({super.key, required this.move, required this.unit});
  final StockMovement move;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final m = move;
    final pal = context.palette;
    final isIn = m.qty > 0;
    final (icon, tone) = switch (m.type) {
      StockMoveType.sale => (Icons.shopping_cart_outlined, Tone.primary),
      StockMoveType.purchase => (Icons.local_shipping_outlined, Tone.info),
      StockMoveType.saleReturn || StockMoveType.purchaseReturn => (Icons.assignment_return_outlined, Tone.warning),
      StockMoveType.adjustment => (Icons.tune_rounded, Tone.neutral),
      StockMoveType.opening => (Icons.flag_outlined, Tone.neutral),
    };
    final (fg, bg) = context.tone(tone);
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: fg, size: 20),
      ),
      title: Text('${m.type.label}${m.refNumber == null ? '' : ' • ${m.refNumber}'}'),
      subtitle: Text('${Fmt.relative(m.date)} • ${m.user}${m.note.isEmpty ? '' : '\n${m.note}'}'),
      isThreeLine: m.note.isNotEmpty,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('${isIn ? '+' : ''}${Fmt.qty(m.qty)}', style: context.text.titleSmall?.copyWith(color: isIn ? pal.success : pal.danger)),
          Text('الرصيد ${Fmt.qty(m.stockAfter)}', style: context.text.labelSmall?.copyWith(color: pal.muted)),
        ],
      ),
    );
  }
}

/// Stock count / adjustment with reason.
Future<void> showStockAdjustSheet(BuildContext context, Product product) {
  var mode = 0; // 0 = set count, 1 = add, 2 = remove
  var reason = StockAdjustReason.count;
  final qty = TextEditingController();
  final note = TextEditingController();
  final form = GlobalKey<FormState>();
  final repo = context.read<ProductRepository>();

  return showAppSheet<void>(
    context,
    title: 'تسوية مخزون ${product.name}',
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final v = parseNum(qty.text) ?? 0;
        final newStock = switch (mode) { 0 => v, 1 => product.stock + v, _ => product.stock - v };
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('الرصيد الحالي ${Fmt.qty(product.stock)} ${product.unit}', style: ctx.text.bodySmall),
                  const SizedBox(height: 12),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('جرد فعلي')),
                      ButtonSegment(value: 1, label: Text('إضافة')),
                      ButtonSegment(value: 2, label: Text('خصم')),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) => set(() {
                      mode = s.first;
                      if (mode == 0) reason = StockAdjustReason.count;
                      if (mode == 2 && reason == StockAdjustReason.count) reason = StockAdjustReason.damaged;
                    }),
                  ),
                  const SizedBox(height: 12),
                  MoneyField(
                    controller: qty,
                    label: mode == 0 ? 'الكمية الفعلية بالمخزن' : 'الكمية',
                    suffix: product.unit,
                    autofocus: true,
                    onChanged: (_) => set(() {}),
                    validator: (s) {
                      final e = requiredNumber(s, allowZero: mode == 0);
                      if (e != null) return e;
                      if (newStock < 0) return 'الكمية أكبر من الرصيد';
                      if ((newStock - product.stock).abs() < 0.0001) return 'لا يوجد تغيير';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Text('السبب', style: ctx.text.titleSmall),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final r in StockAdjustReason.values)
                        ChoiceChip(label: Text(r.label), selected: reason == r, onSelected: (_) => set(() => reason = r)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة')),
                  const SizedBox(height: 12),
                  AppCard(
                    color: ctx.palette.subtle,
                    child: Column(
                      children: [
                        InfoRow('الرصيد بعد التسوية', '${Fmt.qty(newStock)} ${product.unit}', bold: true),
                        InfoRow('الفرق', '${newStock - product.stock >= 0 ? '+' : ''}${Fmt.qty(newStock - product.stock)}',
                            valueColor: newStock >= product.stock ? ctx.palette.success : ctx.palette.danger),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      if (!form.currentState!.validate()) return;
                      final r = await runTask(
                        ctx,
                        () => repo.adjustStock(product.id, newStock: newStock, reason: reason, note: note.text.trim()),
                        success: 'تم تسجيل التسوية',
                      );
                      if (r != null && ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('تسجيل التسوية'),
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
