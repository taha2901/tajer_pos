import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/session_cubit.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import 'drawer_guard.dart';

/// Manual money movement: cash in / out, expense, deposit, withdrawal.
Future<void> showCashTxSheet(BuildContext context, {TxType type = TxType.expense}) {
  return showAppSheet<void>(context, builder: (_) => _CashTxForm(initial: type));
}

class _CashTxForm extends StatefulWidget {
  const _CashTxForm({required this.initial});
  final TxType initial;

  @override
  State<_CashTxForm> createState() => _CashTxFormState();
}

class _CashTxFormState extends State<_CashTxForm> {
  late TxType _type = widget.initial;
  final MoneyAccount _account = MoneyAccount.cash;
  String? _category;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _ref = TextEditingController();
  final _form = GlobalKey<FormState>();

  static const _descriptions = {
    TxType.cashIn: 'إيداع نقدية متنوعة في الخزنة',
    TxType.cashOut: 'صرف نقدية متنوعة من الخزنة',
    TxType.expense: 'مصروفات تشغيل المحل',
    TxType.deposit: 'إضافة رأس مال من المالك',
    TxType.withdrawal: 'سحب من المالك أو توريد للبنك',
  };

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _ref.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final amount = parseNum(_amount.text)!;
    final threshold = context.settings.largeExpenseThreshold;
    if (_type == TxType.expense && amount >= threshold) {
      final ok = await confirmDialog(
        context,
        title: 'مصروف كبير',
        message: 'المبلغ ${Fmt.money(amount)} يتجاوز حد التنبيه (${Fmt.money(threshold)}). سيتم إنشاء تنبيه للمدير. متابعة؟',
        confirmLabel: 'تسجيل',
        icon: Icons.warning_amber_rounded,
      );
      if (!ok || !mounted) return;
    }
    final repo = context.read<CashRepository>();
    final tx = await submitWithRecovery<MoneyTx>(
      context,
      (_) => repo.addTransaction(MoneyTxInput(
        type: _type,
        amount: amount,
        account: _account,
        note: _note.text.trim(),
        reference: _ref.text.trim(),
        category: _type == TxType.expense ? _category : null,
      )),
      success: 'تم تسجيل ${_type.label}',
    );
    if (tx != null && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final amount = parseNum(_amount.text) ?? 0;
    final large = _type == TxType.expense && amount >= context.settings.largeExpenseThreshold;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('حركة نقدية', style: context.text.titleLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in TxType.manual)
                    ChoiceChip(
                      avatar: Icon(t.isIn ? Icons.south_west_rounded : Icons.north_east_rounded, size: 16, color: t.isIn ? pal.success : pal.danger),
                      label: Text(t.label),
                      selected: _type == t,
                      onSelected: (_) => setState(() => _type = t),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(_descriptions[_type] ?? '', style: context.text.bodySmall),
              const SizedBox(height: 14),
              MoneyField(
                controller: _amount,
                label: 'المبلغ',
                big: true,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                validator: (v) => requiredNumber(v, allowZero: false),
              ),
              if (large)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('مصروف كبير — سيظهر في التنبيهات', style: TextStyle(color: pal.warning)),
                ),
              if (_type == TxType.expense) ...[
                const SizedBox(height: 14),
                Text('بند المصروف', style: context.text.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final c in expenseCategories)
                      ChoiceChip(label: Text(c), selected: _category == c, onSelected: (_) => setState(() => _category = c)),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              TextFormField(controller: _note, decoration: const InputDecoration(labelText: 'البيان / ملاحظة')),
              const SizedBox(height: 12),
              TextFormField(controller: _ref, decoration: const InputDecoration(labelText: 'رقم مرجعي (إيصال / فاتورة)')),
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _type.isIn ? pal.success : null),
                onPressed: () {
                  if (_type == TxType.expense && _category == null) {
                    showToast(context, 'اختر بند المصروف', kind: ToastKind.error);
                    return;
                  }
                  _submit();
                },
                child: Text('تسجيل ${_type.label}'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
