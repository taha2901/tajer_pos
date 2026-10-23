import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../cash/drawer_guard.dart';
import '../common/pickers.dart';
import '../common/product_widgets.dart';
import '../common/scanner.dart';
import '../invoices/receipt_screen.dart';
import '../products/product_form_screen.dart';

class _Line {
  _Line(this.product, {required this.qty, required this.cost});
  final Product product;
  double qty;
  double cost;
  double discount = 0;
  double get total => qty * cost - discount;
}

enum _PayMode {
  cash('نقدي كامل'),
  bank('تحويل كامل'),
  partial('دفعة جزئية'),
  credit('آجل كامل');

  const _PayMode(this.label);
  final String label;
}

/// Create a purchase invoice from a supplier.
class PurchaseFormScreen extends StatefulWidget {
  const PurchaseFormScreen({super.key, this.supplier, this.product, this.newBarcode});
  final Party? supplier;

  /// Pre-filled product (e.g. reorder from a low-stock alert).
  final Product? product;

  /// Unknown scanned barcode: opens the new-product form pre-filled on start.
  final String? newBarcode;

  @override
  State<PurchaseFormScreen> createState() => _PurchaseFormScreenState();
}

class _PurchaseFormScreenState extends State<PurchaseFormScreen> {
  Party? _supplier;
  final _lines = <_Line>[];
  final _ref = TextEditingController();
  final _discount = TextEditingController();
  final _paid = TextEditingController();
  _PayMode _mode = _PayMode.credit;
  PaymentMethod _partialMethod = PaymentMethod.cash;

  @override
  void initState() {
    super.initState();
    _supplier = widget.supplier;
    final p = widget.product;
    if (p != null) {
      _lines.add(_Line(p, qty: (p.minStock * 2 - p.stock).clamp(1, double.infinity).roundToDouble(), cost: p.purchasePrice));
    }
    final code = widget.newBarcode;
    if (code != null) WidgetsBinding.instance.addPostFrameCallback((_) => _addNewProduct(barcode: code));
  }

  @override
  void dispose() {
    _ref.dispose();
    _discount.dispose();
    _paid.dispose();
    super.dispose();
  }

  double get _subtotal => _lines.fold(0, (s, l) => s + l.total);
  double get _disc => parseNum(_discount.text) ?? 0;
  double get _total => r2(_subtotal - _disc);
  double get _paidAmount => switch (_mode) {
        _PayMode.cash || _PayMode.bank => _total,
        _PayMode.credit => 0,
        _PayMode.partial => (parseNum(_paid.text) ?? 0).clamp(0, _total).toDouble(),
      };

  Future<void> _addProduct({bool scan = false}) async {
    Product? p;
    if (scan) {
      final code = await scanBarcode(context);
      if (code == null || !mounted) return;
      p = await context.read<ProductRepository>().findByBarcode(code);
      if (p == null) {
        if (!mounted) return;
        final add = await confirmDialog(context, title: 'منتج غير مسجل', message: 'لا يوجد منتج بالكود $code. هل تريد تسجيله كمنتج جديد؟', confirmLabel: 'منتج جديد');
        if (!add || !mounted) return;
        p = await _createProduct(barcode: code);
      }
    } else {
      p = await pickProduct(context, showCost: true);
    }
    if (p == null || !mounted) return;
    final existing = _lines.where((l) => l.product.id == p!.id).firstOrNull;
    if (existing != null) {
      setState(() => existing.qty += 1);
      _editLine(existing);
    } else {
      final line = _Line(p, qty: 1, cost: p.purchasePrice);
      setState(() => _lines.add(line));
      _editLine(line, isNew: true);
    }
  }

  Future<Product?> _createProduct({String? barcode}) =>
      Navigator.of(context).push<Product>(MaterialPageRoute(builder: (_) => ProductFormScreen(barcode: barcode, fromPurchase: true)));

  Future<void> _addNewProduct({String? barcode}) async {
    final p = await _createProduct(barcode: barcode);
    if (p == null || !mounted) return;
    final line = _Line(p, qty: 1, cost: p.purchasePrice);
    setState(() => _lines.add(line));
    _editLine(line, isNew: true);
  }

  Future<void> _editLine(_Line line, {bool isNew = false}) async {
    final qty = TextEditingController(text: Fmt.qty(line.qty));
    final cost = TextEditingController(text: Fmt.qty(line.cost));
    final disc = TextEditingController(text: line.discount == 0 ? '' : Fmt.qty(line.discount));
    final form = GlobalKey<FormState>();
    await showAppSheet<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          final c = parseNum(cost.text) ?? 0;
          final warn = c >= line.product.sellingPrice;
          return SafeArea(
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
                        ProductThumb(line.product),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(line.product.name, style: ctx.text.titleMedium),
                              Text('المخزون ${Fmt.qty(line.product.stock)} • سعر البيع ${Fmt.money(line.product.sellingPrice)}', style: ctx.text.bodySmall),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    MoneyField(controller: qty, label: 'الكمية', suffix: line.product.unit, autofocus: isNew, validator: (v) => requiredNumber(v, allowZero: false)),
                    const SizedBox(height: 12),
                    MoneyField(
                      controller: cost,
                      label: 'سعر الشراء للوحدة',
                      helper: 'آخر سعر شراء ${Fmt.money(line.product.purchasePrice)}',
                      onChanged: (_) => set(() {}),
                      validator: (v) => requiredNumber(v),
                    ),
                    if (warn)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('تنبيه: سعر الشراء أعلى من أو يساوي سعر البيع الحالي', style: TextStyle(color: ctx.palette.warning)),
                      ),
                    const SizedBox(height: 12),
                    MoneyField(controller: disc, label: 'خصم على الصنف (مبلغ)'),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        IconButton.outlined(
                          onPressed: () {
                            setState(() => _lines.remove(line));
                            Navigator.pop(ctx);
                          },
                          icon: Icon(Icons.delete_outline, color: ctx.palette.danger),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              if (!form.currentState!.validate()) return;
                              setState(() {
                                line.qty = parseNum(qty.text)!;
                                line.cost = parseNum(cost.text)!;
                                line.discount = (parseNum(disc.text) ?? 0).clamp(0, line.qty * line.cost).toDouble();
                              });
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
          );
        },
      ),
    );
  }

  Future<void> _submit() async {
    if (_supplier == null) {
      showToast(context, 'اختر المورد أولاً', kind: ToastKind.error);
      return;
    }
    if (_disc < 0 || _disc > _subtotal) {
      showToast(context, 'الخصم أكبر من الإجمالي', kind: ToastKind.error);
      return;
    }
    final paid = _paidAmount;
    final method = switch (_mode) {
      _PayMode.cash => PaymentMethod.cash,
      _PayMode.bank => PaymentMethod.bank,
      _ => _partialMethod,
    };
    final draft = InvoiceDraft(
      type: InvoiceType.purchase,
      partyId: _supplier!.id,
      lines: [for (final l in _lines) DraftLine(productId: l.product.id, qty: l.qty, unitPrice: l.cost, discount: l.discount)],
      discount: _disc,
      payments: [if (paid > 0) PaymentLine(method, paid)],
      supplierRef: _ref.text.trim(),
    );
    final repo = context.read<InvoiceRepository>();
    final inv = await submitWithRecovery<Invoice>(context, (_) => repo.create(draft));
    if (inv == null || !mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => ReceiptScreen(invoice: inv, justCreated: true)));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final remaining = r2(_total - _paidAmount);
    return PopScope(
      canPop: _lines.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await confirmDialog(context, title: 'تجاهل الفاتورة؟', message: 'لم يتم حفظ فاتورة الشراء. هل تريد الخروج؟', confirmLabel: 'خروج', destructive: true);
        if (leave && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('فاتورة شراء جديدة')),
        body: MaxWidth(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              ListGroup(
                children: [
                  ListTile(
                    leading: Initials(_supplier?.name ?? 'م', tone: _supplier == null ? Tone.neutral : Tone.primary),
                    title: Text(_supplier?.name ?? 'اختر المورد'),
                    subtitle: Text(_supplier == null
                        ? 'مطلوب'
                        : _supplier!.hasDebt
                            ? 'مستحق له حالياً ${Fmt.money(_supplier!.balance)}'
                            : _supplier!.company),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () async {
                      final s = await pickParty(context, PartyType.supplier);
                      if (s != null) setState(() => _supplier = s);
                    },
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: TextField(
                  controller: _ref,
                  decoration: const InputDecoration(labelText: 'رقم فاتورة المورد (اختياري)', prefixIcon: Icon(Icons.tag)),
                ),
              ),
              SectionHeader(
                'الأصناف (${_lines.length})',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(tooltip: 'منتج جديد', onPressed: () => _addNewProduct(), icon: const Icon(Icons.add_box_outlined)),
                    IconButton(tooltip: 'مسح باركود', onPressed: () => _addProduct(scan: true), icon: const Icon(Icons.qr_code_scanner_rounded)),
                  ],
                ),
                actionLabel: 'إضافة صنف',
                onAction: _addProduct,
              ),
              if (_lines.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AppCard(
                    onTap: _addProduct,
                    child: const EmptyView(icon: Icons.add_box_outlined, title: 'لم تتم إضافة أصناف', message: 'اضغط لإضافة منتج أو امسح الباركود', compact: true),
                  ),
                )
              else
                ListGroup(
                  children: [
                    for (final l in _lines)
                      ListTile(
                        leading: ProductThumb(l.product, size: 40),
                        title: Text(l.product.name),
                        subtitle: Text('${Fmt.qty(l.qty)} ${l.product.unit} × ${Fmt.money(l.cost)}${l.discount > 0 ? ' • خصم ${Fmt.money(l.discount)}' : ''}'),
                        trailing: Text(Fmt.money(l.total), style: context.text.titleSmall),
                        onTap: () => _editLine(l),
                      ),
                  ],
                ),
              const SectionHeader('الخصم والدفع'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    MoneyField(controller: _discount, label: 'خصم على الفاتورة', onChanged: (_) => setState(() {})),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final m in _PayMode.values)
                          ChoiceChip(label: Text(m.label), selected: _mode == m, onSelected: (_) => setState(() => _mode = m)),
                      ],
                    ),
                    if (_mode == _PayMode.partial) ...[
                      const SizedBox(height: 12),
                      MoneyField(controller: _paid, label: 'المبلغ المدفوع الآن', onChanged: (_) => setState(() {})),
                      const SizedBox(height: 8),
                      ChipsRow<PaymentMethod>(
                        padding: EdgeInsets.zero,
                        values: const [PaymentMethod.cash, PaymentMethod.bank],
                        selected: _partialMethod,
                        label: (m) => m.label,
                        onSelected: (m) => setState(() => _partialMethod = m),
                      ),
                    ],
                    const SizedBox(height: 16),
                    AppCard(
                      child: Column(
                        children: [
                          InfoRow('إجمالي الأصناف', Fmt.money(_subtotal)),
                          if (_disc > 0) InfoRow('الخصم', '- ${Fmt.money(_disc)}', valueColor: p.success),
                          InfoRow('الإجمالي', Fmt.money(_total), bold: true),
                          InfoRow('المدفوع', Fmt.money(_paidAmount), valueColor: p.success),
                          const Divider(height: 20),
                          InfoRow('المتبقي للمورد (آجل)', Fmt.money(remaining), large: true, valueColor: remaining > 0 ? p.danger : null),
                          if (_supplier != null && remaining > 0)
                            InfoRow('رصيد المورد بعد الفاتورة', Fmt.money(_supplier!.balance + remaining)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
        bottomNavigationBar: BottomBar(
          child: FilledButton.icon(
            onPressed: _lines.isEmpty ? null : _submit,
            icon: const Icon(Icons.check_circle_outline),
            label: Text('حفظ فاتورة الشراء • ${Fmt.money(_total)}'),
          ),
        ),
      ),
    );
  }
}
