import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/query_cubit.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../cash/drawer_guard.dart';
import '../common/export.dart';

/// Receive a payment from a customer / pay a supplier.
class PartyPaymentScreen extends StatelessWidget {
  const PartyPaymentScreen({super.key, required this.partyId, this.suggestedAmount});
  final String partyId;
  final double? suggestedAmount;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => simpleQuery(() => c.read<PartyRepository>().getParty(partyId)),
      child: BlocBuilder<QueryCubit<Party, Null>, ViewState<Party>>(
        builder: (context, s) => s.data != null
            ? _Form(party: s.data!, suggested: suggestedAmount)
            : Scaffold(
                appBar: AppBar(),
                body: AsyncBody<Party>(state: s, onRetry: context.read<QueryCubit<Party, Null>>().load, builder: (_) => const SizedBox()),
              ),
      ),
    );
  }
}

class _Form extends StatefulWidget {
  const _Form({required this.party, this.suggested});
  final Party party;
  final double? suggested;

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> {
  final _form = GlobalKey<FormState>();
  late final _amount = TextEditingController(text: widget.suggested != null ? Fmt.qty(widget.suggested!) : '');
  final _note = TextEditingController();
  PaymentMethod _method = PaymentMethod.cash;

  Party get p => widget.party;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final amount = parseNum(_amount.text)!;
    if (amount > p.balance + 0.009) {
      final ok = await confirmDialog(
        context,
        title: 'المبلغ أكبر من الرصيد',
        message: p.isCustomer
            ? 'المبلغ أكبر من مديونية العميل (${Fmt.money(p.balance)}). الزيادة ستُسجل رصيداً دائناً لصالح العميل.'
            : 'المبلغ أكبر من المستحق للمورد (${Fmt.money(p.balance)}). الزيادة ستُسجل رصيداً لنا عند المورد.',
        confirmLabel: 'متابعة',
        icon: Icons.info_outline,
      );
      if (!ok || !mounted) return;
    }
    final repo = context.read<PartyRepository>();
    final payment = await submitWithRecovery<PartyPayment>(
      context,
      (_) => repo.addPayment(PaymentInput(partyId: p.id, amount: amount, method: _method, note: _note.text.trim())),
    );
    if (payment == null || !mounted) return;
    await _showDone(payment);
    if (mounted) Navigator.pop(context, payment);
  }

  Future<void> _showDone(PartyPayment pay) {
    final pal = context.palette;
    final text = '${p.isCustomer ? 'إيصال استلام نقدية' : 'سند صرف'} ${pay.number}\n'
        '${p.isCustomer ? 'استلمنا من' : 'صرف إلى'}: ${pay.partyName}\n'
        'المبلغ: ${Fmt.money(pay.amount)} (${pay.method.label})\n'
        'التاريخ: ${Fmt.dateTime(pay.date)}\n'
        'الرصيد المتبقي: ${Fmt.money(pay.balanceAfter)}';
    return showAppSheet<void>(
      context,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: pal.successBg, shape: BoxShape.circle),
                  child: Icon(Icons.check_rounded, color: pal.success, size: 32),
                ),
              ),
              const SizedBox(height: 12),
              Text(p.isCustomer ? 'تم تحصيل الدفعة' : 'تم سداد الدفعة', style: ctx.text.titleLarge, textAlign: TextAlign.center),
              Text(pay.number, style: ctx.text.bodySmall, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              InfoRow('المبلغ', Fmt.money(pay.amount), bold: true),
              InfoRow('الطريقة', pay.method.label),
              InfoRow('الرصيد السابق', Fmt.money(pay.balanceBefore)),
              InfoRow('الرصيد الحالي', Fmt.money(pay.balanceAfter), bold: true, valueColor: pay.balanceAfter > 0 ? pal.danger : pal.success),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.share_outlined),
                      label: const Text('مشاركة الإيصال'),
                      onPressed: () => shareText(ctx, text),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('تم'))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final amount = parseNum(_amount.text) ?? 0;
    final after = p.balance - amount;
    final quick = <(String, double)>[
      if (p.hasDebt) ('كامل الرصيد', p.balance),
      if (p.hasDebt && p.balance > 100) ('النصف', r2(p.balance / 2)),
      if (widget.suggested != null && widget.suggested != p.balance) ('متبقي الفاتورة', widget.suggested!),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(p.isCustomer ? 'تحصيل من عميل' : 'سداد لمورد')),
      body: Form(
        key: _form,
        child: MaxWidth(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              AppCard(
                child: Row(
                  children: [
                    Initials(p.name, size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.name, style: context.text.titleMedium),
                          Text(p.isCustomer ? 'المديونية الحالية' : 'المستحق للمورد', style: context.text.bodySmall),
                        ],
                      ),
                    ),
                    Text(Fmt.money(p.balance), style: context.text.titleLarge?.copyWith(color: p.hasDebt ? pal.danger : pal.success)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              MoneyField(
                controller: _amount,
                label: 'المبلغ',
                big: true,
                autofocus: widget.suggested == null,
                onChanged: (_) => setState(() {}),
                validator: (v) => requiredNumber(v, allowZero: false),
              ),
              if (quick.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (label, v) in quick)
                      ActionChip(label: Text('$label • ${Fmt.number(v)}'), onPressed: () => setState(() => _amount.text = Fmt.qty(v))),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              Text('طريقة الدفع', style: context.text.titleSmall),
              const SizedBox(height: 8),
              ChipsRow<PaymentMethod>(
                padding: EdgeInsets.zero,
                values: PaymentMethod.values,
                selected: _method,
                label: (m) => m.label,
                onSelected: (m) => setState(() => _method = m),
              ),
              const SizedBox(height: 14),
              TextField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)', prefixIcon: Icon(Icons.notes_rounded))),
              const SizedBox(height: 18),
              AppCard(
                color: pal.subtle,
                child: Column(
                  children: [
                    InfoRow('الرصيد قبل', Fmt.money(p.balance)),
                    InfoRow(p.isCustomer ? 'دفعة مستلمة' : 'دفعة مسددة', '- ${Fmt.money(amount)}', valueColor: pal.success),
                    const Divider(height: 18),
                    InfoRow(
                      after < -0.009 ? (p.isCustomer ? 'رصيد دائن للعميل' : 'رصيد لنا') : 'الرصيد بعد',
                      Fmt.money(after.abs()),
                      large: true,
                      valueColor: after > 0.009 ? pal.danger : pal.success,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                p.isCustomer
                    ? 'الدفعة تُخصم من أقدم الفواتير المفتوحة أولاً، و${_method == PaymentMethod.cash ? 'تُضاف للخزنة' : 'تُضاف لحساب البنك'}.'
                    : 'الدفعة تُخصم من أقدم فواتير الشراء المفتوحة أولاً، و${_method == PaymentMethod.cash ? 'تُصرف من الخزنة' : 'تُخصم من حساب البنك'}.',
                style: context.text.bodySmall,
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomBar(
        child: FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.check_circle_outline),
          label: Text(p.isCustomer ? 'تسجيل التحصيل' : 'تسجيل السداد'),
        ),
      ),
    );
  }
}
