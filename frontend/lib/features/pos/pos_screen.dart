import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../common/pickers.dart';
import '../common/product_widgets.dart';
import '../common/scanner.dart';
import '../invoices/invoices_list_screen.dart';
import 'cart_cubit.dart';
import 'cart_screen.dart';
import 'checkout_screen.dart';

typedef ProductsCubit = QueryCubit<List<Product>, ProductQuery>;

/// Cashier screen: Scan / search → add → cart → pay.
class PosScreen extends StatelessWidget {
  const PosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (c) => ProductsCubit(
            (q) => c.read<ProductRepository>().getProducts(q),
            filter: const ProductQuery(includeInactive: false),
            bus: c.read<DataBus>(),
            topics: const {DataTopic.products},
          ),
        ),
        BlocProvider(
          create: (c) => simpleQuery(() => c.read<ProductRepository>().getCategories(), bus: c.read<DataBus>(), topics: const {DataTopic.products}),
        ),
      ],
      child: BlocListener<ProductsCubit, ViewState<List<Product>>>(
        listenWhen: (a, b) => b.status == ViewStatus.success,
        listener: (context, s) => context.read<CartCubit>().refreshProducts({for (final p in s.data!) p.id: p}),
        child: const _PosView(),
      ),
    );
  }
}

class _PosView extends StatelessWidget {
  const _PosView();

  Future<void> _addByCode(BuildContext context, String code) async {
    final p = await context.read<ProductRepository>().findByBarcode(code);
    if (!context.mounted) return;
    if (p == null) {
      showToast(context, 'لا يوجد منتج بالكود $code', kind: ToastKind.error);
      return;
    }
    final err = context.read<CartCubit>().add(p);
    showToast(context, err ?? 'تمت إضافة ${p.name}', kind: err == null ? ToastKind.success : ToastKind.error);
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartCubit>();
    final products = context.read<ProductsCubit>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('نقطة البيع'),
        actions: [
          IconButton(
            tooltip: 'فواتير البيع',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => context.push(const InvoicesListScreen(type: InvoiceType.sale)),
          ),
          BlocBuilder<CartCubit, CartState>(
            buildWhen: (a, b) => a.held.length != b.held.length,
            builder: (context, s) => IconButton(
              tooltip: 'الفواتير المعلقة',
              onPressed: s.held.isEmpty ? null : () => _showHeld(context),
              icon: Badge(
                isLabelVisible: s.held.isNotEmpty,
                label: Text('${s.held.length}'),
                child: const Icon(Icons.pause_circle_outline_rounded),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const _CustomerBar(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: SearchField(
              hint: 'ابحث أو امسح الباركود',
              onChanged: (v) => products.setFilter(products.filter.copyWith(search: v)),
              // Hardware scanners type the code then press Enter.
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) _addByCode(context, v.trim());
              },
              onScan: () => scanContinuous(context, (code) async {
                final p = await context.read<ProductRepository>().findByBarcode(code);
                if (p == null) return ('لا يوجد منتج بالكود $code', false);
                final err = cart.add(p);
                return (err ?? 'تمت إضافة ${p.name} • الكمية ${Fmt.qty(cart.state.qtyOf(p.id))}', err == null);
              }),
            ),
          ),
          BlocBuilder<QueryCubit<List<Category>, Null>, ViewState<List<Category>>>(
            builder: (context, s) => _CategoryChips(categories: s.data ?? const []),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: BlocBuilder<ProductsCubit, ViewState<List<Product>>>(
              builder: (context, state) => AsyncBody<List<Product>>(
                state: state,
                onRetry: products.load,
                isEmpty: (d) => d.isEmpty,
                empty: EmptyView(
                  icon: Icons.search_off_rounded,
                  title: products.filter.search.isEmpty ? 'لا توجد منتجات' : 'لا توجد نتائج',
                  message: products.filter.search.isEmpty ? 'أضف منتجات من شاشة المنتجات للبدء في البيع' : 'جرّب اسماً آخر أو امسح الباركود',
                ),
                builder: (list) => _ProductGrid(products: list),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const _CartBar(),
    );
  }

  void _showHeld(BuildContext context) {
    final cart = context.read<CartCubit>();
    showAppSheet<void>(
      context,
      title: 'الفواتير المعلقة',
      builder: (ctx) => BlocBuilder<CartCubit, CartState>(
        bloc: cart,
        builder: (ctx, s) => ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            if (s.held.isEmpty) const EmptyView(icon: Icons.pause_circle_outline, title: 'لا توجد فواتير معلقة', compact: true),
            for (var i = 0; i < s.held.length; i++)
              ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(s.held[i].customer?.name ?? 'عميل نقدي'),
                subtitle: Text('${s.held[i].lines.length} صنف • ${Fmt.money(s.held[i].total)}'),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => cart.dropHeld(i)),
                onTap: () {
                  cart.resume(i);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.categories});
  final List<Category> categories;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProductsCubit>();
    // Rebuilds on every product state so the selected category stays in sync.
    return BlocBuilder<ProductsCubit, ViewState<List<Product>>>(
      builder: (context, _) => ChipsRow<String?>(
        values: [null, ...categories.map((c) => c.id)],
        selected: cubit.filter.categoryId,
        label: (id) => id == null ? 'الكل' : categories.firstWhere((c) => c.id == id).name,
        onSelected: (id) => cubit.setFilter(cubit.filter.copyWith(categoryId: () => id)),
      ),
    );
  }
}

class _CustomerBar extends StatelessWidget {
  const _CustomerBar();

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartCubit>();
    return BlocBuilder<CartCubit, CartState>(
      buildWhen: (a, b) => a.customer != b.customer,
      builder: (context, s) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  onTap: () async {
                    final p = await pickParty(context, PartyType.customer, allowWalkIn: true);
                    if (p != null) cart.setCustomer(p.id == walkInCustomer.id ? null : p);
                  },
                  child: Row(
                    children: [
                      Icon(s.customer == null ? Icons.person_outline_rounded : Icons.person_rounded,
                          color: s.customer == null ? context.palette.muted : context.colors.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(s.customer?.name ?? 'عميل نقدي', style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (s.customer != null && s.customer!.hasDebt)
                              Text('رصيد سابق ${Fmt.money(s.customer!.balance)}',
                                  style: context.text.labelSmall?.copyWith(color: context.palette.danger)),
                          ],
                        ),
                      ),
                      Icon(Icons.expand_more_rounded, color: context.palette.muted),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.products});
  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / 175).floor().clamp(2, 6);
      return BlocBuilder<CartCubit, CartState>(
        buildWhen: (a, b) => a.lines != b.lines,
        builder: (context, cart) => GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            mainAxisExtent: 128,
          ),
          itemCount: products.length,
          itemBuilder: (_, i) => _ProductTile(product: products[i], inCart: cart.qtyOf(products[i].id)),
        ),
      );
    });
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.inCart});
  final Product product;
  final double inCart;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final selected = inCart > 0;
    final disabled = p.isOutOfStock && !context.settings.allowNegativeStock;
    return Material(
      color: context.colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: selected ? BorderSide(color: context.colors.primary, width: 1.6) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          final err = context.read<CartCubit>().add(p);
          if (err != null) showToast(context, err, kind: ToastKind.error);
        },
        onLongPress: () => _askQty(context),
        child: Opacity(
          opacity: disabled ? 0.5 : 1,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ProductThumb(p, size: 34),
                    const Spacer(),
                    if (selected)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: context.colors.primary, borderRadius: BorderRadius.circular(10)),
                        child: Text(Fmt.qty(inCart), style: context.text.labelMedium?.copyWith(color: context.colors.onPrimary, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: Text(p.name, style: context.text.labelLarge?.copyWith(height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(Fmt.money(p.sellingPrice), style: context.text.titleSmall?.copyWith(color: context.colors.primary)),
                    ),
                    Text(
                      p.isOutOfStock ? 'نفد' : Fmt.qty(p.stock),
                      style: context.text.labelSmall?.copyWith(
                        color: p.isOutOfStock ? context.palette.danger : p.isLowStock ? context.palette.warning : context.palette.muted,
                        fontWeight: FontWeight.w600,
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

  Future<void> _askQty(BuildContext context) async {
    final ctrl = TextEditingController(text: '1');
    final qty = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(product.name),
        content: MoneyField(controller: ctrl, label: 'الكمية', suffix: product.unit, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, parseNum(ctrl.text)), child: const Text('إضافة')),
        ],
      ),
    );
    if (qty == null || qty <= 0 || !context.mounted) return;
    final err = context.read<CartCubit>().add(product, qty: qty);
    if (err != null) showToast(context, err, kind: ToastKind.error);
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CartCubit, CartState>(
      builder: (context, s) {
        if (s.isEmpty) return const SizedBox.shrink();
        return BottomBar(
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => context.push(const CartScreen()),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: Row(
                      children: [
                        Badge(
                          label: Text(Fmt.qty(s.itemsCount)),
                          child: Icon(Icons.shopping_basket_outlined, color: context.colors.primary),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${s.lines.length} صنف • عرض السلة', style: context.text.labelSmall?.copyWith(color: context.palette.muted)),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(Fmt.money(s.total), style: context.text.titleLarge),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => context.push(const CheckoutScreen()),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('الدفع'),
              ),
            ],
          ),
        );
      },
    );
  }
}
