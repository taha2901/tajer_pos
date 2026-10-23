import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/query_cubit.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../cash/drawer_guard.dart';

/// Sales return / purchase return from an existing invoice.
class ReturnScreen extends StatelessWidget {
  const ReturnScreen({super.key, required this.invoiceId});
  final String invoiceId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => simpleQuery(() => c.read<InvoiceRepository>().getInvoice(invoiceId)),
      child: BlocBuilder<QueryCubit<Invoice, Null>, ViewState<Invoice>>(
        builder: (context, s) => s.data != null
            ? _ReturnForm(invoice: s.data!)
            : Scaffold(
                appBar: AppBar(title: const Text('مرتجع')),
                body: AsyncBody<Invoice>(state: s, onRetry: context.read<QueryCubit<Invoice, Null>>().load, builder: (_) => const SizedBox()),
              ),
      ),
    );
  }
}

class _ReturnForm extends StatefulWidget {
  const _ReturnForm({required this.invoice});
  final Invoice invoice;

  @override
  State<_ReturnForm> createState() => _ReturnFormState();
}

class _ReturnFormState extends State<_ReturnForm> {
  final _qty = <String, double>{};
  PaymentMethod _method = PaymentMethod.cash;
  String _reason = '';
  final _note = TextEditingController();

  bool get _isSale => widget.invoice.type == InvoiceType.sale;
  List<String> get _reasons => _isSale
      ? const ['عيب في المنتج', 'خطأ في الطلب', 'العميل غيّر رأيه', 'منتهي الصلاحية']
      : const ['تالف عند الاستلام', 'مخالف للمواصفات', 'كمية زائدة', 'منتهي الصلاحية'];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = [_reason, _note.text.trim()].where((e) => e.isNotEmpty).join(' — ');
    final ok = await confirmDialog(
      context,
      title: 'تأكيد المرتجع',
      message: 'سيتم ${_isSale ? 'إعادة الأصناف للمخزون' : 'خصم الأصناف من المخزون'} وتسوية الحساب والنقدية. لا يمكن التراجع عن هذه العملية.',
      confirmLabel: 'تأكيد المرتجع',
      icon: Icons.assignment_return_outlined,
    );
    if (!ok || !mounted) return;
    final repo = context.read<InvoiceRepository>();
    final doc = await submitWithRecovery<ReturnDoc>(
      context,
      (_) => repo.createReturn(ReturnDraft(invoiceId: widget.invoice.id, qtyByProduct: Map.of(_qty), refundMethod: _method, reason: reason)),
      success: 'تم تسجيل المرتجع',
    );
    if (doc != null && mounted) Navigator.pop(context, doc);
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    final p = context.palette;
    final s = ReturnSettlement.of(inv, _qty);
    final hasQty = _qty.values.any((q) => q > 0);
    final lines = inv.lines.where((l) => l.returnableQty > 0).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_isSale ? 'مرتجع بيع' : 'مرتجع شراء'),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              for (final l in lines) {
                _qty[l.productId] = l.returnableQty;
              }
            }),
            child: const Text('إرجاع الكل'),
          ),
        ],
      ),
      body: MaxWidth(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppCard(
                child: Row(
                  children: [
                    Icon(Icons.receipt_long_outlined, color: p.muted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${inv.number} • ${inv.partyName}', style: context.text.titleSmall),
                          Text('${Fmt.date(inv.date)} • الإجمالي ${Fmt.money(inv.total)} • المتبقي ${Fmt.money(inv.due)}', style: context.text.bodySmall),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SectionHeader('حدد الأصناف والكميات المرتجعة'),
            if (lines.isEmpty)
              const EmptyView(icon: Icons.check_circle_outline, title: 'تم إرجاع كل أصناف الفاتورة', compact: true)
            else
              ListGroup(
                children: [
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l.productName, style: context.text.titleSmall),
                                Text(
                                  'مباع ${Fmt.qty(l.qty)}${l.returnedQty > 0 ? ' • مرتجع سابق ${Fmt.qty(l.returnedQty)}' : ''} • ${Fmt.money(l.netUnitPrice * inv.discountFactor)} للوحدة',
                                  style: context.text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          QtyStepper(
                            compact: true,
                            value: _qty[l.productId] ?? 0,
                            max: l.returnableQty,
                            onChanged: (v) => setState(() => _qty[l.productId] = v),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            const SectionHeader('سبب الإرجاع'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in _reasons)
                    ChoiceChip(label: Text(r), selected: _reason == r, onSelected: (sel) => setState(() => _reason = sel ? r : '')),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)')),
            ),
            const SectionHeader('التسوية'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InfoRow('قيمة المرتجع', Fmt.money(s.total), bold: true),
                    InfoRow(_isSale ? 'يُخصم من مديونية العميل' : 'يُخصم من المستحق للمورد', Fmt.money(s.creditApplied)),
                    InfoRow(_isSale ? 'يُرد للعميل' : 'يُسترد من المورد', Fmt.money(s.cashRefund),
                        valueColor: s.cashRefund > 0 ? p.warning : null, bold: s.cashRefund > 0),
                    if (s.cashRefund > 0) ...[
                      const SizedBox(height: 10),
                      ChipsRow<PaymentMethod>(
                        padding: EdgeInsets.zero,
                        values: const [PaymentMethod.cash, PaymentMethod.bank],
                        selected: _method,
                        label: (m) => m == PaymentMethod.cash ? 'نقداً من الخزنة' : 'تحويل بنكي',
                        onSelected: (m) => setState(() => _method = m),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(
                      _isSale
                          ? 'المرتجع يُخصم أولاً من المتبقي على الفاتورة، والزيادة تُرد للعميل.'
                          : 'المرتجع يُخصم أولاً من المستحق للمورد على الفاتورة، والزيادة تُسترد منه.',
                      style: context.text.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: BottomBar(
        child: FilledButton.icon(
          onPressed: hasQty ? _submit : null,
          icon: const Icon(Icons.assignment_return_outlined),
          label: Text(hasQty ? 'تأكيد المرتجع • ${Fmt.money(s.total)}' : 'حدد كمية للإرجاع'),
        ),
      ),
    );
  }
}
