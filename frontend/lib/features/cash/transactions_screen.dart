import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/data_bus.dart';
import '../../core/format.dart';
import '../../core/query_cubit.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../common/export.dart';
import 'cash_screen.dart';
import 'cash_tx_sheet.dart';

typedef _Cubit = QueryCubit<List<MoneyTx>, TxQuery>;

/// All money movements (cash + bank) with filters. Also used for "Expenses".
class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({super.key, this.account, this.type, this.sessionId, this.title});
  final MoneyAccount? account;
  final TxType? type;
  final String? sessionId;
  final String? title;

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  Period _period = Period.month;
  DateRange? _custom;

  @override
  Widget build(BuildContext context) {
    final isExpenses = widget.type == TxType.expense;
    return BlocProvider(
      create: (c) => _Cubit(
        (q) => c.read<CashRepository>().getTransactions(q),
        filter: TxQuery(
          account: widget.account,
          type: widget.type,
          sessionId: widget.sessionId,
          from: widget.sessionId == null ? Period.month.range!.from : null,
        ),
        bus: c.read<DataBus>(),
        topics: const {DataTopic.cash},
      ),
      child: BlocBuilder<_Cubit, ViewState<List<MoneyTx>>>(
        builder: (context, state) {
          final cubit = context.read<_Cubit>();
          final list = state.data ?? const <MoneyTx>[];
          final totalIn = list.where((t) => t.isIn).fold(0.0, (s, t) => s + t.amount);
          final totalOut = list.where((t) => !t.isIn).fold(0.0, (s, t) => s + t.amount);
          return Scaffold(
            appBar: AppBar(
              title: Text(widget.title ?? (isExpenses ? 'المصروفات' : 'الحركات المالية')),
              actions: [
                IconButton(
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: () => showExportSheet(
                    context,
                    ExportTable(
                      title: isExpenses ? 'المصروفات' : 'الحركات المالية',
                      headers: const ['التاريخ', 'النوع', 'الحساب', 'البيان', 'المرجع', 'المبلغ', 'المستخدم'],
                      rows: [
                        for (final t in list)
                          [Fmt.dateTime(t.date), t.category ?? t.type.label, t.account.label, t.note, t.refNumber ?? t.number, '${t.isIn ? '' : '-'}${Fmt.number(t.amount)}', t.user],
                      ],
                      summary: [('الوارد', Fmt.money(totalIn)), ('المنصرف', Fmt.money(totalOut))],
                    ),
                  ),
                ),
              ],
            ),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: SearchField(hint: 'بحث في البيان أو المرجع', onChanged: (v) => cubit.setFilter(cubit.filter.copyWith(search: v))),
                ),
                if (widget.sessionId == null) ...[
                  PeriodSelector(
                    period: _period,
                    customRange: _custom,
                    onChanged: (p, r) {
                      setState(() {
                        _period = p;
                        if (p == Period.custom) _custom = r;
                      });
                      cubit.setFilter(cubit.filter.copyWith(from: () => r?.from, to: () => r?.to));
                    },
                  ),
                  const SizedBox(height: 6),
                ],
                if (widget.type == null)
                  ChipsRow<MoneyAccount?>(
                    values: const [null, MoneyAccount.cash, MoneyAccount.bank],
                    selected: cubit.filter.account,
                    label: (a) => a?.label ?? 'كل الحسابات',
                    onSelected: (a) => cubit.setFilter(cubit.filter.copyWith(account: () => a)),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Row(
                    children: [
                      if (!isExpenses) ...[
                        Expanded(child: KpiTile(label: 'الوارد', value: Fmt.money(totalIn), icon: Icons.south_west_rounded, tone: Tone.success)),
                        const SizedBox(width: 8),
                      ],
                      Expanded(child: KpiTile(label: isExpenses ? 'إجمالي المصروفات' : 'المنصرف', value: Fmt.money(totalOut), icon: Icons.north_east_rounded, tone: Tone.danger)),
                      if (!isExpenses) ...[
                        const SizedBox(width: 8),
                        Expanded(child: KpiTile(label: 'الصافي', value: Fmt.money(totalIn - totalOut), icon: Icons.functions_rounded)),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: AsyncBody<List<MoneyTx>>(
                    state: state,
                    onRetry: cubit.load,
                    isEmpty: (d) => d.isEmpty,
                    empty: EmptyView(
                      icon: Icons.receipt_long_outlined,
                      title: isExpenses ? 'لا توجد مصروفات' : 'لا توجد حركات',
                      message: 'لا توجد حركات في هذه الفترة',
                    ),
                    builder: (list) => ListView.separated(
                      padding: const EdgeInsets.only(bottom: 96),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
                      itemBuilder: (_, i) => TxTile(tx: list[i], showAccount: true),
                    ),
                  ),
                ),
              ],
            ),
            floatingActionButton: widget.sessionId != null
                ? null
                : FloatingActionButton.extended(
                    heroTag: 'tx_fab',
                    onPressed: () => showCashTxSheet(context, type: widget.type ?? TxType.expense),
                    icon: const Icon(Icons.add),
                    label: Text(isExpenses ? 'مصروف جديد' : 'حركة جديدة'),
                  ),
          );
        },
      ),
    );
  }
}
