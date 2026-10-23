import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../cash/drawer_guard.dart';
import '../common/pickers.dart';
import '../invoices/receipt_screen.dart';
import 'cart_cubit.dart';

/// Sale payment: full cash, full credit, or cash + the rest on credit.
enum CheckoutMode {
  cash('كاش', Icons.payments_outlined),
  credit('آجل', Icons.schedule_rounded),
  mixed('مختلط', Icons.call_split_rounded);

  const CheckoutMode(this.label, this.icon);
  final String label;
  final IconData icon;
}

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  CheckoutMode _mode = CheckoutMode.cash;
  final _received = TextEditingController();
  final _mixedCash = TextEditingController();

  CartState get cart => context.read<CartCubit>().state;

  @override
  void initState() {
    super.initState();
    _received.text = Fmt.qty(context.read<CartCubit>().state.total);
  }

  @override
  void dispose() {
    _received.dispose();
    _mixedCash.dispose();
    super.dispose();
  }

  double _n(TextEditingController c) => parseNum(c.text) ?? 0;

  /// Cash actually kept for this sale (the rest, if any, goes on credit).
  List<PaymentLine> _payments(double total) {
    final cash = switch (_mode) {
      CheckoutMode.cash => total,
      CheckoutMode.credit => 0.0,
      CheckoutMode.mixed => _n(_mixedCash),
    };
    return [if (cash > 0) PaymentLine(PaymentMethod.cash, r2(cash))];
  }

  /// Blocking input problem for the current mode, if any.
  String? _inputError(double total) => switch (_mode) {
        CheckoutMode.cash when _n(_received) + 0.009 < total => 'المبلغ المستلم أقل من الإجمالي — استخدم "مختلط" لتسجيل الباقي آجل',
        CheckoutMode.mixed when _n(_mixedCash) <= 0 => 'أدخل المبلغ المدفوع كاش',
        CheckoutMode.mixed when _n(_mixedCash) >= total => 'المبلغ الكاش يغطي الإجمالي — اختر "كاش"',
        _ => null,
      };

  Future<void> _submit() async {
    final s = cart;
    final total = s.total;
    final payments = _payments(total);
    final paid = payments.fold(0.0, (a, p) => a + p.amount);
    final inputError = _inputError(total);
    if (inputError != null) {
      showToast(context, inputError, kind: ToastKind.error);
      return;
    }
    final remaining = r2(total - paid);
    if (remaining > 0.009 && s.customer == null) {
      final picked = await pickParty(context, PartyType.customer);
      if (picked == null || !mounted) return;
      context.read<CartCubit>().setCustomer(picked);
      return; // let the user review the credit summary before confirming
    }

    final repo = context.read<InvoiceRepository>();
    final change = _mode == CheckoutMode.cash ? r2(_n(_received) - total) : 0.0;
    final invoice = await submitWithRecovery<Invoice>(
      context,
      (override) => repo.create(context.read<CartCubit>().state.toDraft(payments: payments, overrideCreditLimit: override)),
    );
    if (invoice == null || !mounted) return;
    context.read<CartCubit>().clear();
    final navigator = Navigator.of(context)..popUntil((r) => r.isFirst);
    navigator.push(MaterialPageRoute(
      builder: (_) => ReceiptScreen(invoice: invoice, change: change > 0 ? change : 0, justCreated: true),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CartCubit, CartState>(
      builder: (context, s) {
        final total = s.total;
        final payments = _payments(total);
        final paid = payments.fold(0.0, (a, p) => a + p.amount);
        final remaining = r2(total - paid);
        final change = _mode == CheckoutMode.cash ? r2(_n(_received) - total) : 0.0;
        final inputError = _inputError(total);
        final needsCustomer = remaining > 0.009 && s.customer == null;

        return Scaffold(
          appBar: AppBar(title: const Text('الدفع')),
          body: MaxWidth(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _TotalHeader(state: s),
                const SizedBox(height: 18),
                Text('طريقة الدفع', style: context.text.titleMedium),
                const SizedBox(height: 10),
                _ModePicker(mode: _mode, onChanged: (m) => setState(() => _mode = m)),
                const SizedBox(height: 18),
                ..._modeFields(total),
                const SizedBox(height: 18),
                _Summary(total: total, paid: paid, remaining: remaining, change: change > 0 ? change : 0),
                if (remaining > 0.009) ...[
                  const SizedBox(height: 14),
                  _CreditPanel(customer: s.customer, remaining: remaining),
                ],
                if (inputError != null) ...[
                  const SizedBox(height: 12),
                  Text(inputError, style: TextStyle(color: context.palette.danger)),
                ],
              ],
            ),
          ),
          bottomNavigationBar: BottomBar(
            child: FilledButton.icon(
              onPressed: inputError != null || s.isEmpty ? null : _submit,
              icon: Icon(needsCustomer ? Icons.person_search_outlined : Icons.check_circle_outline),
              label: Text(needsCustomer ? 'اختر العميل لتسجيل الآجل' : 'إتمام البيع • ${Fmt.money(total)}'),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _modeFields(double total) {
    switch (_mode) {
      case CheckoutMode.cash:
        final quick = <double>{total, (total / 50).ceil() * 50, (total / 100).ceil() * 100, (total / 200).ceil() * 200, (total / 500).ceil() * 500}
            .where((v) => v >= total)
            .toList()
          ..sort();
        return [
          MoneyField(controller: _received, label: 'المبلغ المستلم', big: true, onChanged: (_) => setState(() {})),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in quick.take(4))
                ActionChip(
                  label: Text(v == total ? 'المبلغ بالضبط' : Fmt.number(v)),
                  onPressed: () => setState(() => _received.text = Fmt.qty(v)),
                ),
            ],
          ),
          const SizedBox(height: 6),
        ];
      case CheckoutMode.credit:
        return [
          Text('سيُسجل كامل المبلغ آجل على حساب العميل.', style: context.text.bodyMedium),
        ];
      case CheckoutMode.mixed:
        return [
          MoneyField(controller: _mixedCash, label: 'المدفوع كاش', big: true, autofocus: true, onChanged: (_) => setState(() {})),
          const SizedBox(height: 6),
          Text('الباقي يُسجّل آجل على العميل.', style: context.text.bodySmall),
        ];
    }
  }
}

class _TotalHeader extends StatelessWidget {
  const _TotalHeader({required this.state});
  final CartState state;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: context.colors.primary,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المطلوب', style: context.text.labelLarge?.copyWith(color: context.colors.onPrimary.withValues(alpha: 0.8))),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(Fmt.money(state.total), style: context.text.headlineMedium?.copyWith(color: context.colors.onPrimary)),
                ),
                const SizedBox(height: 4),
                Text(
                  '${state.lines.length} صنف • ${Fmt.qty(state.itemsCount)} قطعة${state.totalDiscount > 0 ? ' • خصم ${Fmt.money(state.totalDiscount)}' : ''}',
                  style: context.text.bodySmall?.copyWith(color: context.colors.onPrimary.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Icon(Icons.person_outline, color: context.colors.onPrimary.withValues(alpha: 0.8)),
              Text(state.customer?.name ?? 'عميل نقدي', style: context.text.labelMedium?.copyWith(color: context.colors.onPrimary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.mode, required this.onChanged});
  final CheckoutMode mode;
  final ValueChanged<CheckoutMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final n = CheckoutMode.values.length;
      final w = (c.maxWidth - (n - 1) * 8) / n;
      return Row(
        children: [
          for (final m in CheckoutMode.values) ...[
            SizedBox(
              width: w,
              child: Material(
                color: m == mode ? context.colors.primary.withValues(alpha: 0.1) : context.colors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: m == mode ? context.colors.primary : context.palette.border, width: m == mode ? 1.6 : 1),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onChanged(m),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      children: [
                        Icon(m.icon, color: m == mode ? context.colors.primary : context.palette.muted),
                        const SizedBox(height: 4),
                        Text(m.label, style: context.text.labelMedium?.copyWith(color: m == mode ? context.colors.primary : null)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (m != CheckoutMode.values.last) const SizedBox(width: 8),
          ],
        ],
      );
    });
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.total, required this.paid, required this.remaining, required this.change});
  final double total, paid, remaining, change;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          InfoRow('الإجمالي', Fmt.money(total), bold: true),
          InfoRow('المدفوع', Fmt.money(paid), valueColor: context.palette.success),
          if (remaining > 0.009) InfoRow('المتبقي (آجل)', Fmt.money(remaining), valueColor: context.palette.danger, bold: true),
          if (change > 0) ...[
            const Divider(height: 20),
            InfoRow('الباقي للعميل', Fmt.money(change), large: true, valueColor: context.palette.warning),
          ],
        ],
      ),
    );
  }
}

class _CreditPanel extends StatelessWidget {
  const _CreditPanel({required this.customer, required this.remaining});
  final Party? customer;
  final double remaining;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = customer;
    if (c == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: p.warningBg, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: p.warning),
            const SizedBox(width: 10),
            Expanded(child: Text('البيع الآجل يتطلب عميلاً مسجلاً. اختر العميل لتسجيل ${Fmt.money(remaining)} على حسابه.', style: TextStyle(color: p.warning))),
          ],
        ),
      );
    }
    final newBalance = c.balance + remaining;
    final over = c.creditLimit > 0 && newBalance > c.creditLimit;
    return AppCard(
      color: over ? p.dangerBg : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, color: over ? p.danger : context.colors.primary, size: 20),
              const SizedBox(width: 8),
              Text('حساب ${c.name}', style: context.text.titleSmall),
            ],
          ),
          const SizedBox(height: 8),
          InfoRow('الرصيد الحالي', Fmt.money(c.balance)),
          InfoRow('يضاف آجل', '+ ${Fmt.money(remaining)}'),
          InfoRow('الرصيد بعد البيع', Fmt.money(newBalance), bold: true, valueColor: over ? p.danger : null),
          if (c.creditLimit > 0) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (newBalance / c.creditLimit).clamp(0, 1).toDouble(),
                minHeight: 6,
                color: over ? p.danger : newBalance / c.creditLimit > 0.8 ? p.warning : p.success,
                backgroundColor: p.subtle,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              over ? 'سيتجاوز حد الائتمان (${Fmt.money(c.creditLimit)}) — يتطلب موافقة المدير' : 'حد الائتمان ${Fmt.money(c.creditLimit)}',
              style: context.text.bodySmall?.copyWith(color: over ? p.danger : null),
            ),
          ],
        ],
      ),
    );
  }
}
