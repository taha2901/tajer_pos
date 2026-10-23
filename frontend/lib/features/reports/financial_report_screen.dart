import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/theme.dart';
import '../../core/data_bus.dart';
import '../../core/format.dart';
import '../../core/query_cubit.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../common/export.dart';

typedef _Cubit = QueryCubit<FinancialReport, DateRange>;

/// Revenue, profit, expenses, debts and cash flow.
class FinancialReportScreen extends StatefulWidget {
  const FinancialReportScreen({super.key});

  @override
  State<FinancialReportScreen> createState() => _FinancialReportScreenState();
}

class _FinancialReportScreenState extends State<FinancialReportScreen> {
  Period _period = Period.month;
  DateRange? _custom;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => _Cubit(
        (r) => c.read<ReportRepository>().getFinancialReport(r),
        filter: Period.month.range!,
        bus: c.read<DataBus>(),
        topics: const {DataTopic.invoices, DataTopic.cash, DataTopic.parties},
      ),
      child: BlocBuilder<_Cubit, ViewState<FinancialReport>>(
        builder: (context, state) {
          final cubit = context.read<_Cubit>();
          return Scaffold(
            appBar: AppBar(
              title: const Text('التقرير المالي'),
              actions: [
                if (state.data != null) ...[
                  IconButton(icon: const Icon(Icons.print_outlined), onPressed: () => showPrintPreview(context, _table(state.data!))),
                  IconButton(icon: const Icon(Icons.ios_share_rounded), onPressed: () => showExportSheet(context, _table(state.data!))),
                ],
              ],
            ),
            body: Column(
              children: [
                const SizedBox(height: 8),
                PeriodSelector(
                  period: _period,
                  customRange: _custom,
                  allowAll: false,
                  onChanged: (p, r) {
                    setState(() {
                      _period = p;
                      if (p == Period.custom) _custom = r;
                    });
                    if (r != null) cubit.setFilter(r);
                  },
                ),
                const SizedBox(height: 8),
                Expanded(child: AsyncBody<FinancialReport>(state: state, onRetry: cubit.load, builder: (r) => _Body(report: r))),
              ],
            ),
          );
        },
      ),
    );
  }

  ExportTable _table(FinancialReport r) => ExportTable(
        title: 'التقرير المالي ${Fmt.date(r.range.from)} - ${Fmt.date(r.range.to)}',
        headers: const ['البند', 'القيمة'],
        rows: [
          ['المبيعات', Fmt.number(r.revenue)],
          ['مرتجعات المبيعات', Fmt.number(r.salesReturns)],
          ['صافي المبيعات', Fmt.number(r.netRevenue)],
          ['تكلفة البضاعة المباعة', Fmt.number(r.cogs)],
          ['مجمل الربح', Fmt.number(r.grossProfit)],
          for (final e in r.expensesByCategory) ['مصروف: ${e.name}', Fmt.number(e.value)],
          ['صافي الربح', Fmt.number(r.netProfit)],
          ['مديونيات العملاء', Fmt.number(r.customerDebts)],
          ['مستحقات الموردين', Fmt.number(r.supplierDebts)],
          ['إجمالي الوارد', Fmt.number(r.cashIn)],
          ['إجمالي المنصرف', Fmt.number(r.cashOut)],
        ],
      );
}

class _Body extends StatelessWidget {
  const _Body({required this.report});
  final FinancialReport report;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final pal = context.palette;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        TileGrid(
          children: [
            KpiTile(label: 'صافي المبيعات', value: Fmt.money(r.netRevenue), icon: Icons.trending_up_rounded),
            KpiTile(label: 'مجمل الربح', value: Fmt.money(r.grossProfit), icon: Icons.savings_outlined, tone: Tone.success, caption: r.netRevenue == 0 ? null : 'هامش ${Fmt.percent(r.grossProfit / r.netRevenue * 100)}'),
            KpiTile(label: 'المصروفات', value: Fmt.money(r.expenses), icon: Icons.receipt_outlined, tone: Tone.warning),
            KpiTile(label: 'صافي الربح', value: Fmt.money(r.netProfit), icon: Icons.account_balance_wallet_outlined, tone: r.netProfit >= 0 ? Tone.success : Tone.danger),
          ],
        ),
        const SectionHeader('قائمة الدخل'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppCard(
            child: Column(
              children: [
                InfoRow('المبيعات', Fmt.money(r.revenue)),
                InfoRow('مرتجعات المبيعات', '- ${Fmt.money(r.salesReturns)}', valueColor: pal.danger),
                InfoRow('صافي المبيعات', Fmt.money(r.netRevenue), bold: true),
                InfoRow('تكلفة البضاعة المباعة', '- ${Fmt.money(r.cogs)}', valueColor: pal.danger),
                const Divider(height: 18),
                InfoRow('مجمل الربح', Fmt.money(r.grossProfit), bold: true),
                for (final e in r.expensesByCategory) InfoRow('  ${e.name}', '- ${Fmt.money(e.value)}', valueColor: pal.danger),
                const Divider(height: 18),
                InfoRow('صافي الربح', Fmt.money(r.netProfit), large: true, valueColor: r.netProfit >= 0 ? pal.success : pal.danger),
              ],
            ),
          ),
        ),
        if (r.expensesByCategory.isNotEmpty) ...[
          const SectionHeader('المصروفات حسب البند'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: RankedBars(color: pal.warning, items: [for (final e in r.expensesByCategory) (e.name, e.value, '')]),
            ),
          ),
        ],
        const SectionHeader('الديون'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(child: KpiTile(label: 'لنا عند العملاء', value: Fmt.money(r.customerDebts), icon: Icons.call_received_rounded, tone: Tone.warning)),
              const SizedBox(width: 10),
              Expanded(child: KpiTile(label: 'علينا للموردين', value: Fmt.money(r.supplierDebts), icon: Icons.call_made_rounded, tone: Tone.danger)),
            ],
          ),
        ),
        const SectionHeader('التدفق النقدي (الخزنة + البنك)'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    LegendDot('وارد', context.colors.primary),
                    const SizedBox(width: 14),
                    LegendDot('منصرف', pal.muted),
                  ],
                ),
                const SizedBox(height: 12),
                SimpleBarChart(
                  labels: [for (final d in r.flowByDay) d.name],
                  values: [for (final d in r.flowByDay) d.value],
                  secondValues: [for (final d in r.flowByDay) d.extra],
                  valueLabel: 'وارد',
                  secondLabel: 'منصرف',
                ),
                const SizedBox(height: 12),
                InfoRow('إجمالي الوارد', '+ ${Fmt.money(r.cashIn)}', valueColor: pal.success),
                InfoRow('إجمالي المنصرف', '- ${Fmt.money(r.cashOut)}', valueColor: pal.danger),
                InfoRow('صافي التدفق', Fmt.money(r.netFlow), bold: true),
                const Divider(height: 18),
                InfoRow('رصيد الخزنة الحالي', Fmt.money(r.cashBalance)),
                InfoRow('رصيد البنك الحالي', Fmt.money(r.bankBalance)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
