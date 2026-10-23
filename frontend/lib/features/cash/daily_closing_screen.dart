import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/query_cubit.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../common/export.dart';
import 'cash_screen.dart';

/// End-of-day: count the drawer, compare with expected, close the session.
class DailyClosingScreen extends StatelessWidget {
  const DailyClosingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => simpleQuery(() => c.read<CashRepository>().getOverview()),
      child: BlocBuilder<QueryCubit<CashOverview, Null>, ViewState<CashOverview>>(
        builder: (context, s) {
          final drawer = s.data?.drawer;
          if (drawer != null) return _ClosingForm(drawer: drawer);
          return Scaffold(
            appBar: AppBar(title: const Text('إقفال اليومية')),
            body: s.data != null
                ? const EmptyView(icon: Icons.lock_outline, title: 'لا توجد وردية مفتوحة')
                : AsyncBody<CashOverview>(state: s, onRetry: context.read<QueryCubit<CashOverview, Null>>().load, builder: (_) => const SizedBox()),
          );
        },
      ),
    );
  }
}

class _ClosingForm extends StatefulWidget {
  const _ClosingForm({required this.drawer});
  final DrawerSummary drawer;

  @override
  State<_ClosingForm> createState() => _ClosingFormState();
}

class _ClosingFormState extends State<_ClosingForm> {
  static const _denoms = [200.0, 100.0, 50.0, 20.0, 10.0, 5.0, 1.0, 0.5];
  final _counts = <double, int>{};
  final _total = TextEditingController();
  final _note = TextEditingController();
  bool _byDenoms = true;

  double get _counted => _byDenoms ? _counts.entries.fold(0.0, (s, e) => s + e.key * e.value) : (parseNum(_total.text) ?? 0);

  @override
  void dispose() {
    _total.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    final diff = r2(_counted - widget.drawer.expected);
    final ok = await confirmDialog(
      context,
      title: 'إقفال الوردية ${widget.drawer.session.number}',
      message: diff.abs() < 0.01
          ? 'النقدية الفعلية مطابقة للمتوقع (${Fmt.money(_counted)}).'
          : 'يوجد ${diff > 0 ? 'زيادة' : 'عجز'} بقيمة ${Fmt.money(diff.abs())}. سيتم تسجيله في تقرير الإقفال.',
      confirmLabel: 'إقفال',
      icon: Icons.lock_clock_outlined,
    );
    if (!ok || !mounted) return;
    final repo = context.read<CashRepository>();
    final s = await runTask(context, () => repo.closeSession(countedCash: _counted, note: _note.text.trim()), success: 'تم إقفال الوردية');
    if (s != null && mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => SessionReportScreen(sessionId: s.id)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.drawer;
    final pal = context.palette;
    final diff = r2(_counted - d.expected);
    return Scaffold(
      appBar: AppBar(title: const Text('إقفال اليومية')),
      body: MaxWidth(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SummaryCard(drawer: d),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: Text('جرد النقدية', style: context.text.titleMedium)),
                SegmentedButton<bool>(
                  segments: const [ButtonSegment(value: true, label: Text('بالفئات')), ButtonSegment(value: false, label: Text('مبلغ'))],
                  selected: {_byDenoms},
                  showSelectedIcon: false,
                  onSelectionChanged: (v) => setState(() => _byDenoms = v.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_byDenoms)
              AppCard(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(
                  children: [
                    for (final v in _denoms)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            SizedBox(width: 70, child: Text(v < 1 ? '50 قرش' : '${Fmt.qty(v)} ج', style: context.text.titleSmall)),
                            Expanded(
                              child: Text('= ${Fmt.money(v * (_counts[v] ?? 0))}', style: context.text.bodySmall),
                            ),
                            SizedBox(
                              width: 74,
                              child: TextField(
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                decoration: const InputDecoration(isDense: true, hintText: '0', contentPadding: EdgeInsets.symmetric(vertical: 10)),
                                onChanged: (t) => setState(() => _counts[v] = int.tryParse(t) ?? 0),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              )
            else
              MoneyField(controller: _total, label: 'النقدية الفعلية بالدرج', big: true, onChanged: (_) => setState(() {})),
            const SizedBox(height: 16),
            AppCard(
              color: diff.abs() < 0.01 ? pal.successBg : diff > 0 ? pal.infoBg : pal.dangerBg,
              child: Column(
                children: [
                  InfoRow('المتوقع', Fmt.money(d.expected)),
                  InfoRow('الفعلي', Fmt.money(_counted), bold: true),
                  const Divider(height: 18),
                  InfoRow(
                    diff.abs() < 0.01 ? 'مطابق' : diff > 0 ? 'زيادة' : 'عجز',
                    Fmt.money(diff.abs()),
                    large: true,
                    valueColor: diff.abs() < 0.01 ? pal.success : diff > 0 ? pal.info : pal.danger,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'ملاحظات الإقفال (سبب العجز/الزيادة)')),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: BottomBar(
        child: FilledButton.icon(icon: const Icon(Icons.lock_rounded), label: const Text('إقفال الوردية'), onPressed: _close),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.drawer});
  final DrawerSummary drawer;

  @override
  Widget build(BuildContext context) {
    final d = drawer;
    final pal = context.palette;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${d.session.number} • فُتحت ${Fmt.relative(d.session.openedAt)}', style: context.text.bodySmall),
          const SizedBox(height: 8),
          InfoRow('رصيد الافتتاح', Fmt.money(d.session.openingBalance)),
          InfoRow('المبيعات (نقدي + تحويل)', '+ ${Fmt.money(d.amount(TxType.sale))}', valueColor: pal.success),
          InfoRow('تحصيلات العملاء', '+ ${Fmt.money(d.amount(TxType.customerPayment))}', valueColor: pal.success),
          InfoRow('إيداعات أخرى', '+ ${Fmt.money(d.amount(TxType.cashIn) + d.amount(TxType.deposit) + d.amount(TxType.purchaseRefund))}', valueColor: pal.success),
          InfoRow('مشتريات ومدفوعات موردين', '- ${Fmt.money(d.amount(TxType.purchase) + d.amount(TxType.supplierPayment))}', valueColor: pal.danger),
          InfoRow('مصروفات', '- ${Fmt.money(d.amount(TxType.expense))}', valueColor: pal.danger),
          InfoRow('مرتجعات ومسحوبات وصرف', '- ${Fmt.money(d.amount(TxType.saleRefund) + d.amount(TxType.withdrawal) + d.amount(TxType.cashOut))}', valueColor: pal.danger),
          const Divider(height: 18),
          InfoRow('الرصيد المتوقع', Fmt.money(d.expected), large: true),
        ],
      ),
    );
  }
}

/// Closing report for a (closed or open) session.
class SessionReportScreen extends StatelessWidget {
  const SessionReportScreen({super.key, required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => simpleQuery(() => c.read<CashRepository>().getSessionSummary(sessionId)),
      child: BlocBuilder<QueryCubit<DrawerSummary, Null>, ViewState<DrawerSummary>>(
        builder: (context, state) {
          final d = state.data;
          return Scaffold(
            appBar: AppBar(
              title: Text(d == null ? 'تقرير الوردية' : 'تقرير ${d.session.number}'),
              actions: [
                if (d != null)
                  IconButton(
                    icon: const Icon(Icons.ios_share_rounded),
                    onPressed: () => showExportSheet(
                      context,
                      ExportTable(
                        title: 'تقرير إقفال ${d.session.number}',
                        headers: const ['الوقت', 'النوع', 'المرجع', 'المبلغ'],
                        rows: [for (final t in d.transactions) [Fmt.dateTime(t.date), t.type.label, t.refNumber ?? '', '${t.isIn ? '+' : '-'}${Fmt.number(t.amount)}']],
                        summary: [
                          ('رصيد الافتتاح', Fmt.money(d.session.openingBalance)),
                          ('الوارد', Fmt.money(d.totalIn)),
                          ('المنصرف', Fmt.money(d.totalOut)),
                          ('المتوقع', Fmt.money(d.session.expectedCash ?? d.expected)),
                          ('الفعلي', Fmt.money(d.session.countedCash ?? 0)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            body: AsyncBody<DrawerSummary>(
              state: state,
              onRetry: context.read<QueryCubit<DrawerSummary, Null>>().load,
              builder: (d) {
                final s = d.session;
                final pal = context.palette;
                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: AppCard(
                        child: Column(
                          children: [
                            InfoRow('الفتح', '${Fmt.dateTime(s.openedAt)} • ${s.openedBy}'),
                            if (s.closedAt != null) InfoRow('الإقفال', '${Fmt.dateTime(s.closedAt!)} • ${s.closedBy}'),
                            const Divider(height: 18),
                            InfoRow('رصيد الافتتاح', Fmt.money(s.openingBalance)),
                            InfoRow('إجمالي الوارد', '+ ${Fmt.money(d.totalIn)}', valueColor: pal.success),
                            InfoRow('إجمالي المنصرف', '- ${Fmt.money(d.totalOut)}', valueColor: pal.danger),
                            InfoRow('المتوقع', Fmt.money(s.expectedCash ?? d.expected), bold: true),
                            if (s.countedCash != null) ...[
                              InfoRow('الفعلي', Fmt.money(s.countedCash!), bold: true),
                              InfoRow(
                                s.difference.abs() < 0.01 ? 'مطابق' : s.difference > 0 ? 'زيادة' : 'عجز',
                                Fmt.money(s.difference.abs()),
                                valueColor: s.difference.abs() < 0.01 ? pal.success : s.difference > 0 ? pal.info : pal.danger,
                                bold: true,
                              ),
                            ],
                            if (s.note.isNotEmpty) InfoRow('ملاحظات', s.note),
                          ],
                        ),
                      ),
                    ),
                    SectionHeader('الحركات (${d.transactions.length})'),
                    if (d.transactions.isEmpty)
                      const EmptyView(icon: Icons.receipt_long_outlined, title: 'لا توجد حركات', compact: true)
                    else
                      ListGroup(children: [for (final t in d.transactions) TxTile(tx: t)]),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }
}
