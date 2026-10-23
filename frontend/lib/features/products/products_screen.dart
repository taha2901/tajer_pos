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
import '../common/product_widgets.dart';
import '../common/scanner.dart';
import 'product_details_screen.dart';
import '../purchases/purchase_form_screen.dart';

typedef ProductListCubit = QueryCubit<List<Product>, ProductQuery>;
typedef _CategoriesCubit = QueryCubit<List<Category>, Null>;

String _stockFilterLabel(ProductStockFilter f) => switch (f) {
      ProductStockFilter.all => 'الكل',
      ProductStockFilter.low => 'مخزون منخفض',
      ProductStockFilter.out => 'نفد المخزون',
      ProductStockFilter.inactive => 'موقوف',
    };

class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key, this.isTab = false, this.initialFilter = ProductStockFilter.all});
  final bool isTab;
  final ProductStockFilter initialFilter;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (c) => ProductListCubit(
            (q) => c.read<ProductRepository>().getProducts(q),
            filter: ProductQuery(stockFilter: initialFilter),
            bus: c.read<DataBus>(),
            topics: const {DataTopic.products},
          ),
        ),
        BlocProvider(
          create: (c) => simpleQuery(() => c.read<ProductRepository>().getCategories(), bus: c.read<DataBus>(), topics: const {DataTopic.products}),
        ),
      ],
      child: _View(isTab: isTab),
    );
  }
}

class _View extends StatelessWidget {
  const _View({required this.isTab});
  final bool isTab;

  Future<void> _scan(BuildContext context) async {
    final code = await scanBarcode(context);
    if (code == null || !context.mounted) return;
    final p = await context.read<ProductRepository>().findByBarcode(code);
    if (!context.mounted) return;
    if (p != null) {
      context.push(ProductDetailsScreen(productId: p.id));
      return;
    }
    final add = await confirmDialog(context, title: 'منتج غير مسجل', message: 'لا يوجد منتج بالكود $code. هل تريد إضافته عبر فاتورة شراء؟', confirmLabel: 'فاتورة شراء');
    if (add && context.mounted) context.push(PurchaseFormScreen(newBarcode: code));
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProductListCubit>();
    return Scaffold(
      appBar: AppBar(title: const Text('المنتجات'), automaticallyImplyLeading: !isTab),
      body: BlocBuilder<_CategoriesCubit, ViewState<List<Category>>>(
        builder: (context, cs) {
          final categories = {for (final c in cs.data ?? const <Category>[]) c.id: c.name};
          return BlocBuilder<ProductListCubit, ViewState<List<Product>>>(
            builder: (context, state) {
              final q = cubit.filter;
              final activeCount = (q.categoryId != null ? 1 : 0) + (q.stockFilter != ProductStockFilter.all ? 1 : 0) + (q.sort != ProductSort.name ? 1 : 0);
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: SearchField(
                            hint: 'ابحث بالاسم أو الباركود أو SKU',
                            onChanged: (v) => cubit.setFilter(cubit.filter.copyWith(search: v)),
                            onScan: () => _scan(context),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Badge(
                          isLabelVisible: activeCount > 0,
                          label: Text('$activeCount'),
                          child: IconButton.filledTonal(
                            tooltip: 'الفلاتر والترتيب',
                            style: IconButton.styleFrom(minimumSize: const Size(50, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                            onPressed: () => _showFilters(context, categories),
                            icon: const Icon(Icons.tune_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (activeCount > 0) _ActiveFilters(categories: categories),
                  const SizedBox(height: 8),
                  Expanded(
                    child: AsyncBody<List<Product>>(
                      state: state,
                      onRetry: cubit.load,
                      isEmpty: (d) => d.isEmpty,
                      empty: q.search.isNotEmpty || activeCount > 0
                          ? EmptyView(
                              icon: Icons.search_off_rounded,
                              title: 'لا توجد منتجات مطابقة',
                              message: 'جرّب كلمة أخرى أو امسح الفلاتر',
                            )
                          : EmptyView(
                              icon: Icons.inventory_2_outlined,
                              title: 'لا توجد منتجات بعد',
                              message: 'أضف أول منتج للبدء في البيع وإدارة المخزون',
                              actionLabel: 'فاتورة شراء',
                              onAction: () => context.push(const PurchaseFormScreen()),
                            ),
                      builder: (list) => _ProductList(products: list, categories: categories),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'products_fab',
        onPressed: () => context.push(const PurchaseFormScreen()),
        icon: const Icon(Icons.local_shipping_outlined),
        label: const Text('شراء'),
      ),
    );
  }

  void _showFilters(BuildContext context, Map<String, String> categories) {
    final cubit = context.read<ProductListCubit>();
    var draft = cubit.filter;
    showAppSheet<void>(
      context,
      title: 'الفلاتر والترتيب',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          Widget group(String title, List<Widget> chips) => Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: ctx.text.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: chips),
                  ],
                ),
              );
          ChoiceChip chip(String label, bool selected, VoidCallback onTap) =>
              ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => set(onTap));

          return SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  group('الفئة', [
                    chip('كل الفئات', draft.categoryId == null, () => draft = draft.copyWith(categoryId: () => null)),
                    for (final e in categories.entries)
                      chip(e.value, draft.categoryId == e.key, () => draft = draft.copyWith(categoryId: () => e.key)),
                  ]),
                  group('حالة المخزون', [
                    for (final f in ProductStockFilter.values)
                      chip(_stockFilterLabel(f), draft.stockFilter == f, () => draft = draft.copyWith(stockFilter: f)),
                  ]),
                  group('الترتيب', [
                    for (final s in ProductSort.values) chip(s.label, draft.sort == s, () => draft = draft.copyWith(sort: s)),
                  ]),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              cubit.setFilter(ProductQuery(search: cubit.filter.search));
                              Navigator.pop(ctx);
                            },
                            child: const Text('مسح الكل'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton(
                            onPressed: () {
                              cubit.setFilter(draft.copyWith(search: cubit.filter.search));
                              Navigator.pop(ctx);
                            },
                            child: const Text('عرض النتائج'),
                          ),
                        ),
                      ],
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
}

/// Removable chips for the filters currently applied.
class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({required this.categories});
  final Map<String, String> categories;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ProductListCubit>();
    final q = cubit.filter;
    Widget chip(String label, VoidCallback onRemove) => Padding(
          padding: const EdgeInsetsDirectional.only(end: 6),
          child: InputChip(
            label: Text(label),
            onDeleted: onRemove,
            deleteIcon: const Icon(Icons.close_rounded, size: 16),
            visualDensity: VisualDensity.compact,
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          if (q.categoryId != null)
            chip(categories[q.categoryId] ?? 'فئة', () => cubit.setFilter(q.copyWith(categoryId: () => null))),
          if (q.stockFilter != ProductStockFilter.all)
            chip(_stockFilterLabel(q.stockFilter), () => cubit.setFilter(q.copyWith(stockFilter: ProductStockFilter.all))),
          if (q.sort != ProductSort.name) chip('ترتيب: ${q.sort.label}', () => cubit.setFilter(q.copyWith(sort: ProductSort.name))),
        ],
      ),
    );
  }
}

class _ProductList extends StatelessWidget {
  const _ProductList({required this.products, required this.categories});
  final List<Product> products;
  final Map<String, String> categories;

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final low = products.where((p) => p.isLowStock).length;
    final out = products.where((p) => p.isOutOfStock).length;
    return RefreshIndicator(
      onRefresh: context.read<ProductListCubit>().load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${products.length} منتج'),
                if (low > 0) TextSpan(text: '  •  $low منخفض', style: TextStyle(color: pal.warning)),
                if (out > 0) TextSpan(text: '  •  $out نفد', style: TextStyle(color: pal.danger)),
              ]),
              style: context.text.labelMedium?.copyWith(color: pal.muted),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < products.length; i++) ...[
                  if (i > 0) const Divider(indent: 76),
                  ProductTile(product: products[i], category: categories[products[i].categoryId]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One product row: identity on the start side, price and stock on the end side.
class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product, this.category});
  final Product product;
  final String? category;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final pal = context.palette;
    final (stockColor, stockText) = p.isOutOfStock
        ? (pal.danger, 'نفد')
        : p.isLowStock
            ? (pal.warning, 'متبقي ${Fmt.qty(p.stock)}')
            : (pal.success, '${Fmt.qty(p.stock)} ${p.unit}');
    return InkWell(
      onTap: () => context.push(ProductDetailsScreen(productId: p.id)),
      child: Opacity(
        opacity: p.isActive ? 1 : 0.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              ProductThumb(p, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.name, style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.qr_code_2_rounded, size: 14, color: pal.muted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            p.barcode,
                            style: context.text.labelSmall?.copyWith(color: pal.muted, letterSpacing: 0.5, fontFeatures: const [FontFeature.tabularFigures()]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.ltr,
                          ),
                        ),
                        if (category != null) ...[
                          Text('  •  ', style: context.text.labelSmall?.copyWith(color: pal.muted)),
                          Flexible(child: Text(category!, style: context.text.labelSmall?.copyWith(color: pal.muted), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ],
                      ],
                    ),
                    if (!p.isActive) ...[
                      const SizedBox(height: 4),
                      const StatusPill('موقوف عن البيع'),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(Fmt.money(p.sellingPrice), style: context.text.titleSmall),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 7, height: 7, decoration: BoxDecoration(color: stockColor, shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Text(stockText, style: context.text.labelSmall?.copyWith(color: stockColor, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  if (context.perms.isAdmin)
                    Text('تكلفة ${Fmt.number(p.purchasePrice)}', style: context.text.labelSmall?.copyWith(color: pal.muted, fontSize: 10.5)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
