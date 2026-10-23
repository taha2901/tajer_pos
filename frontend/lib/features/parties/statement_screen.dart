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
import '../invoices/invoice_details_screen.dart';

typedef _Cubit = QueryCubit<Statement, DateRange?>;

/// Customer / supplier statement: every movement with debit, credit, balance.
class StatementScreen extends StatefulWidget {
  const StatementScreen({super.key, required this.partyId});
  final String partyId;

  @override
  State<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends State<StatementScreen> {
  Period _period = Period.all;
  DateRange? _custom;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => _Cubit(
        (r) => c.read<PartyRepository>().getStatement(widget.partyId, from: r?.from, to: r?.to),
        filter: null,
        bus: c.read<DataBus>(),
        topics: const {DataTopic.parties},
      ),
      child: BlocBuilder<_Cubit, ViewState<Statement>>(
        builder: (context, state) {
          final st = state.data;
          return Scaffold(
            appBar: AppBar(
              title: Text(st == null ? 'كشف حساب' : 'كشف حساب ${st.party.name}'),
              actions: [
                if (st != null) ...[
                  IconButton(tooltip: 'طباعة', icon: const Icon(Icons.print_outlined), onPressed: () => showPrintPreview(context, _table(st))),
                  IconButton(tooltip: 'تصدير / مشاركة', icon: const Icon(Icons.ios_share_rounded), onPressed: () => showExportSheet(context, _table(st))),
                ],
              ],
            ),
            body: Column(
              children: [
                const SizedBox(height: 8),
                PeriodSelector(
                  period: _period,
                  customRange: _custom,
                  onChanged: (p, r) {
                    setState(() {
                      _period = p;
                      if (p == Period.custom) _custom = r;
                    });
                    context.read<_Cubit>().setFilter(r);
                  },
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: AsyncBody<Statement>(
                    state: state,
                    onRetry: context.read<_Cubit>().load,
                    builder: (s) => _StatementView(statement: s),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  ExportTable _table(Statement s) => ExportTable(
        title: 'كشف حساب ${s.party.name}',
        headers: const ['التاريخ', 'البيان', 'المرجع', 'مدين', 'دائن', 'الرصيد'],
        rows: [
          ['', 'رصيد أول المدة', '', '', '', Fmt.number(s.openingBalance)],
          for (final e in s.entries)
            [Fmt.date(e.date), e.description, e.refNumber ?? '', e.debit == 0 ? '' : Fmt.number(e.debit), e.credit == 0 ? '' : Fmt.number(e.credit), Fmt.number(e.balance)],
        ],
        summary: [
          ('الفترة', s.from == null ? 'كل الفترات' : '${Fmt.date(s.from!)} - ${Fmt.date(s.to!)}'),
          ('إجمالي مدين', Fmt.money(s.totalDebit)),
          ('إجمالي دائن', Fmt.money(s.totalCredit)),
          ('الرصيد الختامي', Fmt.money(s.closingBalance)),
        ],
      );
}

class _StatementView extends StatelessWidget {
  const _StatementView({required this.statement});
  final Statement statement;

  @override
  Widget build(BuildContext context) {
    final s = statement;
    final pal = context.palette;
    final isCustomer = s.party.isCustomer;
    final num = context.text.labelMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

    Widget header() => Container(
          color: pal.subtle,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(flex: 5, child: Text('البيان', style: context.text.labelMedium)),
              Expanded(flex: 3, child: Text('مدين', style: context.text.labelMedium, textAlign: TextAlign.end)),
              Expanded(flex: 3, child: Text('دائن', style: context.text.labelMedium, textAlign: TextAlign.end)),
              Expanded(flex: 3, child: Text('الرصيد', style: context.text.labelMedium, textAlign: TextAlign.end)),
            ],
          ),
        );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Row(
            children: [
              Expanded(child: KpiTile(label: 'إجمالي مدين', value: Fmt.money(s.totalDebit), icon: Icons.north_east_rounded, tone: Tone.danger)),
              const SizedBox(width: 8),
              Expanded(child: KpiTile(label: 'إجمالي دائن', value: Fmt.money(s.totalCredit), icon: Icons.south_west_rounded, tone: Tone.success)),
              const SizedBox(width: 8),
              Expanded(child: KpiTile(label: 'الرصيد', value: Fmt.money(s.closingBalance), icon: Icons.account_balance_wallet_outlined)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            isCustomer ? 'مدين = مبيعات وردود نقدية • دائن = تحصيلات ومرتجعات' : 'دائن = مشتريات واستردادات • مدين = سداد ومرتجعات',
            style: context.text.bodySmall,
          ),
        ),
        const SizedBox(height: 8),
        header(),
        Expanded(
          child: s.entries.isEmpty
              ? const EmptyView(icon: Icons.receipt_outlined, title: 'لا توجد حركات في هذه الفترة', compact: true)
              : ListView.separated(
                  itemCount: s.entries.length + 1,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(flex: 11, child: Text('رصيد أول المدة', style: context.text.titleSmall)),
                            Expanded(flex: 3, child: Text(Fmt.number(s.openingBalance), style: num, textAlign: TextAlign.end)),
                          ],
                        ),
                      );
                    }
                    final e = s.entries[i - 1];
                    // Invoice entries (and payments made with an invoice) reference the invoice itself.
                    final ref = e.refNumber ?? '';
                    final opensInvoice = e.refId != null && (ref.startsWith('S-') || ref.startsWith('P-'));
                    return InkWell(
                      onTap: opensInvoice ? () => context.push(InvoiceDetailsScreen(invoiceId: e.refId!)) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.description, style: context.text.labelLarge),
                                  Text('${Fmt.shortDate(e.date)} ${e.refNumber ?? ''}', style: context.text.labelSmall?.copyWith(color: pal.muted)),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(e.debit == 0 ? '-' : Fmt.number(e.debit), style: num?.copyWith(color: e.debit == 0 ? pal.muted : null), textAlign: TextAlign.end),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(e.credit == 0 ? '-' : Fmt.number(e.credit), style: num?.copyWith(color: e.credit == 0 ? pal.muted : null), textAlign: TextAlign.end),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(Fmt.number(e.balance), style: num?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.end),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        BottomBar(
          child: Row(
            children: [
              Expanded(child: Text('الرصيد الختامي', style: context.text.titleSmall)),
              Text(Fmt.money(s.closingBalance), style: context.text.titleLarge?.copyWith(color: s.closingBalance > 0 ? pal.danger : pal.success)),
            ],
          ),
        ),
      ],
    );
  }
}
