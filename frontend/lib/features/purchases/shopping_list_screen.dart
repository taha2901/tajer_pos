import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/nav.dart';
import '../../app/theme.dart';
import '../../core/data_bus.dart';
import '../../core/format.dart';
import '../../core/query_cubit.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../common/export.dart';
import '../common/pickers.dart';
import 'purchase_form_screen.dart';

/// Items on the list + low / out-of-stock products not on it yet.
typedef _Data = (List<ShoppingItem>, List<Product>);
typedef _Cubit = QueryCubit<_Data, String?>;

/// Suggested quantity to order: back up to twice the minimum.
double suggestedQty(Product p) => (p.minStock * 2 - p.stock).clamp(1, double.infinity).roundToDouble();

/// Shortages list: what to order when a supplier comes by.
class ShoppingListScreen extends StatefulWidget {
  const ShoppingListScreen({super.key});

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen> {
  Party? _supplier;

  static Future<_Data> _load(BuildContext c, String? supplierId) async {
    final products = c.read<ProductRepository>();
    final (items, low, out) = await (
      c.read<ShoppingListRepository>().getItems(supplierId: supplierId),
      products.getProducts(const ProductQuery(stockFilter: ProductStockFilter.low, includeInactive: false)),
      products.getProducts(const ProductQuery(stockFilter: ProductStockFilter.out, includeInactive: false)),
    ).wait;
    final listed = {for (final i in items) i.productId};
    return (items, [...out, ...low].where((p) => !listed.contains(p.id)).toList());
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => _Cubit((s) => _load(c, s), filter: null, bus: c.read<DataBus>(), topics: const {DataTopic.shopping, DataTopic.products}),
      child: BlocBuilder<_Cubit, ViewState<_Data>>(
        builder: (context, state) {
          final items = state.data?.$1 ?? const <ShoppingItem>[];
          return Scaffold(
            appBar: AppBar(
              title: const Text('النواقص'),
              actions: [
                if (items.isNotEmpty)
                  IconButton(tooltip: 'إرسال للمورد', icon: const Icon(Icons.share_outlined), onPressed: () => _share(context, items)),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () => showShoppingItemSheet(context, supplier: _supplier),
              icon: const Icon(Icons.add),
              label: const Text('إضافة صنف'),
            ),
            body: Column(
              children: [
                ListGroup(
                  children: [
                    ListTile(
                      leading: Initials(_supplier?.name ?? 'م', tone: _supplier == null ? Tone.neutral : Tone.primary),
                      title: Text(_supplier?.name ?? 'كل الموردين'),
                      subtitle: Text(_supplier == null ? 'اختر مورداً لعرض ما تطلبه منه' : 'أصناف هذا المورد + الأصناف غير المحددة'),
                      trailing: _supplier == null
                          ? const Icon(Icons.chevron_left)
                          : IconButton(icon: const Icon(Icons.close), onPressed: () => _setSupplier(context, null)),
                      onTap: () async {
                        final s = await pickParty(context, PartyType.supplier);
                        if (s != null && context.mounted) _setSupplier(context, s);
                      },
                    ),
                  ],
                ),
                Expanded(
                  child: AsyncBody<_Data>(
                    state: state,
                    onRetry: context.read<_Cubit>().load,
                    isEmpty: (d) => d.$1.isEmpty && d.$2.isEmpty,
                    empty: const EmptyView(
                      icon: Icons.playlist_add_check_rounded,
                      title: 'لا توجد نواقص',
                      message: 'أضف الأصناف التي تحتاج شراءها لتطلبها من المورد عند حضوره',
                    ),
                    builder: (d) => _Body(items: d.$1, suggestions: d.$2, supplier: _supplier),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: items.any((i) => !i.isNewProduct)
                ? BottomBar(
                    child: FilledButton.icon(
                      onPressed: () => _toPurchase(context, items),
                      icon: const Icon(Icons.local_shipping_outlined),
                      label: const Text('تحويل لفاتورة شراء'),
                    ),
                  )
                : null,
          );
        },
      ),
    );
  }

  void _setSupplier(BuildContext context, Party? s) {
    setState(() => _supplier = s);
    context.read<_Cubit>().setFilter(s?.id);
  }

  void _share(BuildContext context, List<ShoppingItem> items) {
    final b = StringBuffer()..writeln('طلبية${_supplier == null ? '' : ' — ${_supplier!.name}'}');
    for (final i in items) {
      b.write('• ${i.name}: ${Fmt.qty(i.qty)} ${i.unit}'.trimRight());
      if (i.note.isNotEmpty) b.write(' (${i.note})');
      b.writeln();
    }
    shareText(context, b.toString(), subject: 'طلبية');
  }

  /// Opens a purchase invoice with the listed products; they leave the list once it's saved.
  Future<void> _toPurchase(BuildContext context, List<ShoppingItem> items) async {
    final repo = context.read<ProductRepository>();
    final shopping = context.read<ShoppingListRepository>();
    final known = items.where((i) => !i.isNewProduct).toList();
    final lines = await runTask(context, () async => [for (final i in known) (await repo.getProduct(i.productId!), i.qty)]);
    if (lines == null || !context.mounted) return;
    final skipped = items.length - known.length;
    if (skipped > 0) showToast(context, '$skipped صنف غير مسجل بقي في القائمة — سجّله كمنتج من داخل الفاتورة', kind: ToastKind.info);
    context.push(PurchaseFormScreen(
      supplier: _supplier,
      items: lines,
      onSaved: (inv) {
        final bought = {for (final l in inv.lines) l.productId};
        return shopping.remove([for (final i in known) if (bought.contains(i.productId)) i.id]);
      },
    ));
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.items, required this.suggestions, required this.supplier});
  final List<ShoppingItem> items;
  final List<Product> suggestions;
  final Party? supplier;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final repo = context.read<ShoppingListRepository>();
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        SectionHeader('المطلوب شراؤه (${items.length})'),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: AppCard(child: EmptyView(icon: Icons.add_shopping_cart_rounded, title: 'القائمة فارغة', message: 'اضغط "إضافة صنف" أو أضف من المقترحات', compact: true)),
          )
        else
          ListGroup(
            children: [
              for (final i in items)
                Dismissible(
                  key: ValueKey(i.id),
                  direction: DismissDirection.startToEnd,
                  background: Container(
                    color: p.dangerBg,
                    alignment: AlignmentDirectional.centerStart,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Icon(Icons.delete_outline, color: p.danger),
                  ),
                  onDismissed: (_) => runTask(context, () => repo.remove([i.id]), success: 'تم الحذف من النواقص'),
                  child: ListTile(
                    leading: Initials(i.name, tone: i.isNewProduct ? Tone.warning : Tone.primary),
                    title: Row(
                      children: [
                        Flexible(child: Text(i.name, overflow: TextOverflow.ellipsis)),
                        if (i.isNewProduct) ...[const SizedBox(width: 6), const StatusPill('غير مسجل', tone: Tone.warning)],
                      ],
                    ),
                    subtitle: Text([
                      if (i.stock != null) 'الرصيد ${Fmt.qty(i.stock!)}',
                      if (i.supplierName != null) i.supplierName!,
                      if (i.note.isNotEmpty) i.note,
                      if (i.addedBy.isNotEmpty) 'بواسطة ${i.addedBy}',
                    ].join(' • ')),
                    trailing: Text('${Fmt.qty(i.qty)} ${i.unit}', style: context.text.titleSmall),
                    onTap: () => showShoppingItemSheet(context, item: i),
                  ),
                ),
            ],
          ),
        if (suggestions.isNotEmpty) ...[
          const SectionHeader('مقترحات — قاربت على النفاد'),
          ListGroup(
            children: [
              for (final s in suggestions)
                ListTile(
                  leading: Initials(s.name, tone: s.isOutOfStock ? Tone.danger : Tone.warning),
                  title: Text(s.name),
                  subtitle: Text('الرصيد ${Fmt.qty(s.stock)} ${s.unit} • الحد الأدنى ${Fmt.qty(s.minStock)}'),
                  trailing: IconButton.filledTonal(
                    tooltip: 'أضف للنواقص',
                    icon: const Icon(Icons.add),
                    onPressed: () => runTask(
                      context,
                      () => repo.add(ShoppingItemInput(productId: s.id, qty: suggestedQty(s), supplierId: supplier?.id)),
                      success: 'تمت إضافة ${s.name}',
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Add an item (optionally pre-filled with [product]) or edit [item].
Future<void> showShoppingItemSheet(BuildContext context, {ShoppingItem? item, Product? product, Party? supplier}) {
  return showAppSheet<void>(
    context,
    title: item == null ? 'إضافة للنواقص' : 'تعديل الصنف',
    builder: (_) => _ItemForm(item: item, product: product, supplier: supplier),
  );
}

class _ItemForm extends StatefulWidget {
  const _ItemForm({this.item, this.product, this.supplier});
  final ShoppingItem? item;
  final Product? product;
  final Party? supplier;

  @override
  State<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends State<_ItemForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _unit = TextEditingController(text: widget.item?.unit ?? '');
  late final _qty = TextEditingController(text: widget.item == null ? '' : Fmt.qty(widget.item!.qty));
  late final _note = TextEditingController(text: widget.item?.note ?? '');
  Product? _product;
  String? _supplierId;
  String? _supplierName;
  late bool _newProduct = widget.item?.isNewProduct ?? false;

  bool get _editing => widget.item != null;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    if (_product != null) _qty.text = Fmt.qty(suggestedQty(_product!));
    _supplierId = widget.item?.supplierId ?? widget.supplier?.id;
    _supplierName = widget.item?.supplierName ?? widget.supplier?.name;
  }

  @override
  void dispose() {
    for (final c in [_name, _unit, _qty, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final productId = _editing ? widget.item!.productId : (_newProduct ? null : _product?.id);
    if (!_newProduct && productId == null) {
      showToast(context, 'اختر المنتج', kind: ToastKind.error);
      return;
    }
    final input = ShoppingItemInput(
      productId: productId,
      name: _name.text,
      unit: _unit.text,
      qty: parseNum(_qty.text)!,
      supplierId: _supplierId,
      note: _note.text,
    );
    final repo = context.read<ShoppingListRepository>();
    final ok = await runTask(context, () => _editing ? repo.update(widget.item!.id, input) : repo.add(input), success: 'تم الحفظ');
    if (ok != null && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_editing) ...[
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('منتج مسجل'), icon: Icon(Icons.inventory_2_outlined)),
                    ButtonSegment(value: true, label: Text('صنف جديد'), icon: Icon(Icons.edit_note_rounded)),
                  ],
                  selected: {_newProduct},
                  onSelectionChanged: (s) => setState(() => _newProduct = s.first),
                ),
                const SizedBox(height: 12),
              ],
              if (_newProduct) ...[
                TextFormField(
                  controller: _name,
                  autofocus: !_editing,
                  decoration: const InputDecoration(labelText: 'اسم الصنف', prefixIcon: Icon(Icons.label_outline)),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'مطلوب' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _unit, decoration: const InputDecoration(labelText: 'الوحدة (اختياري)', hintText: 'كرتونة، كيلو، قطعة...')),
              ] else if (_editing)
                Text(widget.item!.name, style: context.text.titleMedium)
              else
                OutlinedButton.icon(
                  onPressed: () async {
                    final p = await pickProduct(context, showCost: true);
                    if (p == null) return;
                    setState(() {
                      _product = p;
                      _qty.text = Fmt.qty(suggestedQty(p));
                    });
                  },
                  icon: const Icon(Icons.search),
                  label: Text(_product == null ? 'اختر المنتج' : '${_product!.name} • الرصيد ${Fmt.qty(_product!.stock)}'),
                ),
              const SizedBox(height: 12),
              MoneyField(
                controller: _qty,
                label: 'الكمية المطلوبة',
                suffix: _newProduct ? null : (_product?.unit ?? widget.item?.unit),
                validator: (v) => (parseNum(v ?? '') ?? 0) <= 0 ? 'أدخل كمية صحيحة' : null,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.store_mall_directory_outlined),
                title: Text(_supplierName ?? 'المورد (اختياري)'),
                subtitle: _supplierName == null ? const Text('بدون مورد = يظهر مع كل الموردين') : null,
                trailing: _supplierId == null
                    ? const Icon(Icons.chevron_left)
                    : IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _supplierId = _supplierName = null)),
                onTap: () async {
                  final s = await pickParty(context, PartyType.supplier);
                  if (s != null) {
                    setState(() {
                      _supplierId = s.id;
                      _supplierName = s.name;
                    });
                  }
                },
              ),
              TextFormField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)', hintText: 'ماركة معينة، مقاس...')),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (_editing) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(foregroundColor: context.palette.danger),
                        onPressed: () async {
                          final repo = context.read<ShoppingListRepository>();
                          final ok = await runTask(context, () async {
                            await repo.remove([widget.item!.id]);
                            return true;
                          }, success: 'تم الحذف');
                          if (ok != null && context.mounted) Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('حذف'),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(flex: 2, child: FilledButton(onPressed: _save, child: const Text('حفظ'))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
