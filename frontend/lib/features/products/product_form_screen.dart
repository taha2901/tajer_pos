import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/session_cubit.dart';
import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../common/product_widgets.dart';
import '../common/scanner.dart';

/// Add / edit product — only the fields a cashier actually needs.
/// SKU is generated automatically; supplier / description are kept as-is on edit.
class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.product, this.barcode, this.fromPurchase = false});
  final Product? product;

  /// Pre-filled barcode (from scanning an unknown code).
  final String? barcode;

  /// Created from a purchase invoice: stock comes from the invoice, not an opening quantity.
  final bool fromPurchase;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  final _form = GlobalKey<FormState>();
  Product? get _p => widget.product;
  bool get _isEdit => _p != null;

  late final _name = TextEditingController(text: _p?.name);
  late final _barcode = TextEditingController(text: _p?.barcode ?? widget.barcode);
  late final _cost = TextEditingController(text: _num(_p?.purchasePrice));
  late final _price = TextEditingController(text: _num(_p?.sellingPrice));
  late final _min = TextEditingController(text: _num(_p?.minStock) ?? '5');
  final _opening = TextEditingController();
  late String _unit = _p?.unit ?? productUnits.first;
  late String? _categoryId = _p?.categoryId;
  late String? _image = _p?.imagePath;
  late bool _active = _p?.isActive ?? true;

  List<Category> _categories = const [];
  bool _loading = true;
  Object? _loadError;

  static String? _num(double? v) => v == null ? null : Fmt.qty(v);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final cats = await context.read<ProductRepository>().getCategories();
      if (!mounted) return;
      setState(() {
        _categories = cats;
        _categoryId ??= cats.firstOrNull?.id;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e;
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _barcode, _cost, _price, _min, _opening]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 80);
      if (file != null) setState(() => _image = file.path);
    } catch (_) {
      if (mounted) showToast(context, 'تعذّر فتح معرض الصور', kind: ToastKind.error);
    }
  }

  Future<void> _addCategory() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('فئة جديدة'),
        content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(labelText: 'اسم الفئة')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('إضافة')),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final c = await runTask(context, () => context.read<ProductRepository>().addCategory(name));
    if (c != null && mounted) {
      setState(() {
        _categories = [..._categories, c];
        _categoryId = c.id;
      });
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final cost = parseNum(_cost.text)!;
    final price = parseNum(_price.text)!;
    if (price < cost) {
      final ok = await confirmDialog(context,
          title: 'سعر البيع أقل من التكلفة', message: 'سعر البيع (${Fmt.money(price)}) أقل من سعر الشراء (${Fmt.money(cost)}). هل تريد الحفظ؟', confirmLabel: 'حفظ');
      if (!ok || !mounted) return;
    }
    final input = ProductInput(
      name: _name.text,
      barcode: _barcode.text.trim(),
      sku: _p?.sku ?? '',
      categoryId: _categoryId!,
      unit: _unit,
      purchasePrice: cost,
      sellingPrice: price,
      // Single selling price: the other price levels follow it.
      wholesalePrice: price,
      halfWholesalePrice: price,
      minStock: parseNum(_min.text) ?? 0,
      openingStock: widget.fromPurchase ? 0 : parseNum(_opening.text) ?? 0,
      supplierId: _p?.supplierId,
      description: _p?.description ?? '',
      imagePath: _image,
      isActive: _active,
    );
    final repo = context.read<ProductRepository>();
    final saved = await runTask(
      context,
      () => _isEdit ? repo.update(_p!.id, input) : repo.create(input),
      success: _isEdit ? 'تم حفظ التعديلات' : 'تمت إضافة المنتج',
    );
    if (saved != null && mounted) Navigator.pop(context, saved);
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'حذف "${_p!.name}"؟',
      message: 'سيتم حذف المنتج نهائياً. المنتجات التي لها حركات بيع أو شراء لا يمكن حذفها ويمكن إيقافها بدلاً من ذلك.',
      confirmLabel: 'حذف',
      destructive: true,
      icon: Icons.delete_outline,
    );
    if (!ok || !mounted) return;
    final repo = context.read<ProductRepository>();
    Object? err;
    final done = await runTask(context, () async {
      await repo.delete(_p!.id);
      return true;
    }, success: 'تم حذف المنتج', onError: (e) => err = e);
    if (!mounted) return;
    if (done == true) {
      Navigator.of(context)
        ..pop()
        ..pop();
      return;
    }
    if (err is BusinessException && (err as BusinessException).code == ErrorCodes.hasTransactions) {
      final deactivate = await confirmDialog(context, title: 'لا يمكن الحذف', message: '${errorMessage(err!)}\n\nهل تريد إيقاف المنتج عن البيع؟', confirmLabel: 'إيقاف المنتج');
      if (deactivate && mounted) {
        final r = await runTask(context, () => repo.setActive(_p!.id, false), success: 'تم إيقاف المنتج');
        if (r != null && mounted) Navigator.pop(context, r);
      }
    } else if (err != null) {
      await showErrorDialog(context, err!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final cost = parseNum(_cost.text) ?? 0;
    final price = parseNum(_price.text) ?? 0;
    final margin = price - cost;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'تعديل المنتج' : 'منتج جديد'),
        actions: [
          if (_isEdit && context.perms.canDelete)
            IconButton(tooltip: 'حذف', icon: Icon(Icons.delete_outline, color: pal.danger), onPressed: _delete),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? ErrorView(message: errorMessage(_loadError!), onRetry: _load)
              : Form(
                  key: _form,
                  child: MaxWidth(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        // Image + name side by side keeps the top compact.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ImagePicker(
                              image: _image,
                              name: _name.text,
                              categoryId: _categoryId,
                              onPick: _pickImage,
                              onClear: () => setState(() => _image = null),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                controller: _name,
                                autofocus: !_isEdit && widget.barcode == null,
                                decoration: const InputDecoration(labelText: 'اسم المنتج'),
                                validator: requiredText,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _barcode,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'الباركود',
                            hintText: 'يُولَّد تلقائياً إذا تُرك فارغاً',
                            prefixIcon: const Icon(Icons.qr_code_2_rounded),
                            suffixIcon: IconButton(
                              tooltip: 'مسح الباركود',
                              icon: Icon(Icons.qr_code_scanner_rounded, color: context.colors.primary),
                              onPressed: () async {
                                final code = await scanBarcode(context);
                                if (code != null) setState(() => _barcode.text = code);
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<String>(
                                initialValue: _categoryId,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: 'الفئة',
                                  suffixIcon: IconButton(tooltip: 'فئة جديدة', onPressed: _addCategory, icon: const Icon(Icons.add_rounded)),
                                ),
                                items: [for (final c in _categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
                                onChanged: (v) => setState(() => _categoryId = v),
                                validator: (v) => v == null ? 'اختر الفئة' : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<String>(
                                initialValue: _unit,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'الوحدة'),
                                items: [for (final u in {...productUnits, _unit}) DropdownMenuItem(value: u, child: Text(u))],
                                onChanged: (v) => setState(() => _unit = v!),
                              ),
                            ),
                          ],
                        ),
                        const _Label('السعر'),
                        Row(
                          children: [
                            Expanded(child: MoneyField(controller: _cost, label: 'سعر الشراء', validator: (v) => requiredNumber(v), onChanged: (_) => setState(() {}))),
                            const SizedBox(width: 10),
                            Expanded(child: MoneyField(controller: _price, label: 'سعر البيع', validator: (v) => requiredNumber(v, allowZero: false), onChanged: (_) => setState(() {}))),
                          ],
                        ),
                        if (cost > 0 && price > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'الربح في الوحدة ${Fmt.money(margin)} (${Fmt.percent(margin / cost * 100)})',
                              style: context.text.bodySmall?.copyWith(color: margin >= 0 ? pal.success : pal.danger),
                            ),
                          ),
                        const _Label('المخزون'),
                        Row(
                          children: [
                            if (!_isEdit && !widget.fromPurchase) ...[
                              Expanded(child: MoneyField(controller: _opening, label: 'الكمية الحالية', suffix: _unit)),
                              const SizedBox(width: 10),
                            ],
                            Expanded(child: MoneyField(controller: _min, label: 'تنبيه عند', suffix: _unit)),
                          ],
                        ),
                        if (_isEdit) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('المخزون الحالي ${Fmt.qty(_p!.stock)} ${_p!.unit} — يُعدَّل من "تسوية المخزون"', style: context.text.bodySmall),
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('متاح للبيع'),
                            value: _active,
                            onChanged: (v) => setState(() => _active = v),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
      bottomNavigationBar: _loading || _loadError != null
          ? null
          : BottomBar(child: FilledButton(onPressed: _save, child: Text(_isEdit ? 'حفظ التعديلات' : 'إضافة المنتج'))),
    );
  }
}

class _ImagePicker extends StatelessWidget {
  const _ImagePicker({required this.image, required this.name, required this.categoryId, required this.onPick, required this.onClear});
  final String? image;
  final String name;
  final String? categoryId;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    const size = 56.0;
    return InkWell(
      onTap: onPick,
      onLongPress: image == null ? null : onClear,
      borderRadius: BorderRadius.circular(14),
      child: image == null
          ? Container(
              width: size,
              height: size,
              decoration: BoxDecoration(color: pal.subtle, borderRadius: BorderRadius.circular(14), border: Border.all(color: pal.border)),
              child: Icon(Icons.add_a_photo_outlined, color: pal.muted, size: 22),
            )
          : ProductThumb(
              Product(
                id: '-', name: name.isEmpty ? '?' : name, barcode: '', sku: '', categoryId: categoryId ?? '',
                unit: '', purchasePrice: 0, sellingPrice: 0, wholesalePrice: 0, halfWholesalePrice: 0, stock: 0, minStock: 0,
                createdAt: DateTime.now(), imagePath: image,
              ),
              size: size,
            ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(title, style: context.text.titleSmall?.copyWith(color: context.palette.muted)),
      );
}
