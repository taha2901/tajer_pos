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
import 'cash_tx_sheet.dart';
import 'daily_closing_screen.dart';
import 'drawer_guard.dart';
import 'transactions_screen.dart';

typedef _Cubit = QueryCubit<CashOverview, Null>;

/// Cash drawer: current session breakdown, quick movements, closing.
class CashScreen extends StatelessWidget {
  const CashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => simpleQuery(() => c.read<CashRepository>().getOverview(), bus: c.read<DataBus>(), topics: const {DataTopic.cash}),
      child: BlocBuilder<_Cubit, ViewState<CashOverview>>(
        builder: (context, state) => Scaffold(
          appBar: AppBar(
            title: const Text('الخزنة'),
            actions: [
              IconButton(
                tooltip: 'كل الحركات',
                icon: const Icon(Icons.list_alt_rounded),
                onPressed: () => context.push(const TransactionsScreen()),
              ),
            ],
          ),
          body: AsyncBody<CashOverview>(
            state: state,
            onRetry: context.read<_Cubit>().load,
            builder: (o) => RefreshIndicator(
              onRefresh: context.read<_Cubit>().load,
              child: o.drawer == null ? _Closed(overview: o) : _Open(overview: o, drawer: o.drawer!),
            ),
          ),
          bottomNavigationBar: state.data?.drawer == null
              ? null
              : BottomBar(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.lock_clock_outlined),
                    label: const Text('إقفال اليومية'),
                    onPressed: () => context.push(const DailyClosingScreen()),
                  ),
                ),
        ),
      ),
    );
  }
}

class _Closed extends StatelessWidget {
  const _Closed({required this.overview});
  final CashOverview overview;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AppCard(
          child: Column(
            children: [
              const SizedBox(height: 8),
              const EmptyView(
                icon: Icons.lock_outline_rounded,
                title: 'الخزنة مغلقة',
                message: 'افتح وردية جديدة لبدء تسجيل المبيعات النقدية والمصروفات',
                compact: true,
              ),
              InfoRow('آخر رصيد مُقفل', Fmt.money(overview.lastClosedCash), bold: true),
              InfoRow('رصيد البنك', Fmt.money(overview.bankBalance)),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.lock_open_rounded),
                  label: const Text('فتح وردية'),
                  onPressed: () => promptOpenDrawer(context, fromError: false),
                ),
              ),
            ],
          ),
        ),
        _SessionsHistory(sessions: overview.recentSessions),
      ],
    );
  }
}

class _Open extends StatelessWidget {
  const _Open({required this.overview, required this.drawer});
  final CashOverview overview;
  final DrawerSummary drawer;

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final s = drawer.session;
    final rows = <(TxType, String)>[
      (TxType.sale, 'مبيعات نقدية'),
      (TxType.customerPayment, 'تحصيلات العملاء'),
      (TxType.purchaseRefund, 'استردادات من موردين'),
      (TxType.deposit, 'إضافة رأس مال'),
      (TxType.cashIn, 'إيداعات أخرى'),
      (TxType.purchase, 'مشتريات نقدية'),
      (TxType.supplierPayment, 'مدفوعات الموردين'),
      (TxType.saleRefund, 'مرتجعات للعملاء'),
      (TxType.expense, 'المصروفات'),
      (TxType.withdrawal, 'مسحوبات'),
      (TxType.cashOut, 'صرف آخر'),
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AppCard(
            color: context.colors.primary,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.point_of_sale_rounded, color: context.colors.onPrimary.withValues(alpha: 0.85), size: 18),
                    const SizedBox(width: 6),
                    Text('النقدية المتوقعة بالدرج', style: context.text.labelLarge?.copyWith(color: context.colors.onPrimary.withValues(alpha: 0.85))),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
                      child: Text('${s.number} • مفتوحة', style: context.text.labelSmall?.copyWith(color: context.colors.onPrimary)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(Fmt.money(drawer.expected), style: context.text.headlineMedium?.copyWith(color: context.colors.onPrimary)),
                ),
                const SizedBox(height: 4),
                Text(
                  'فُتحت ${Fmt.relative(s.openedAt)} بواسطة ${s.openedBy}',
                  style: context.text.bodySmall?.copyWith(color: context.colors.onPrimary.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (final (t, icon) in [
                (TxType.cashIn, Icons.south_west_rounded),
                (TxType.cashOut, Icons.north_east_rounded),
                (TxType.expense, Icons.receipt_outlined),
              ])
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => showCashTxSheet(context, type: t),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: t.isIn ? pal.successBg : pal.dangerBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(icon, color: t.isIn ? pal.success : pal.danger, size: 20),
                          ),
                          const SizedBox(height: 6),
                          Text(t == TxType.cashIn ? 'إيداع' : t == TxType.cashOut ? 'صرف' : t.label,
                              style: context.text.labelSmall, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SectionHeader('ملخص الوردية'),
        ListGroup(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                children: [
                  InfoRow('رصيد الافتتاح', Fmt.money(s.openingBalance), bold: true),
                  for (final (t, label) in rows)
                    if (drawer.amount(t) > 0)
                      InfoRow(label, '${t.isIn ? '+' : '-'} ${Fmt.money(drawer.amount(t))}', valueColor: t.isIn ? pal.success : pal.danger),
                  const Divider(height: 20),
                  InfoRow('إجمالي الوارد', '+ ${Fmt.money(drawer.totalIn)}', valueColor: pal.success),
                  InfoRow('إجمالي المنصرف', '- ${Fmt.money(drawer.totalOut)}', valueColor: pal.danger),
                  const Divider(height: 20),
                  InfoRow('الرصيد الختامي المتوقع', Fmt.money(drawer.expected), large: true),
                ],
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            onTap: () => context.push(const TransactionsScreen(account: MoneyAccount.bank)),
            child: Row(
              children: [
                Icon(Icons.account_balance_outlined, color: pal.info),
                const SizedBox(width: 10),
                Expanded(child: Text('رصيد البنك / البطاقات', style: context.text.titleSmall)),
                Text(Fmt.money(overview.bankBalance), style: context.text.titleSmall),
                const Icon(Icons.chevron_left),
              ],
            ),
          ),
        ),
        SectionHeader(
          'حركات الوردية (${drawer.transactions.length})',
          actionLabel: 'الكل',
          onAction: () => context.push(TransactionsScreen(sessionId: s.id, title: 'حركات ${s.number}')),
        ),
        if (drawer.transactions.isEmpty)
          const EmptyView(icon: Icons.receipt_long_outlined, title: 'لا توجد حركات بعد', message: 'ستظهر هنا المبيعات النقدية والمصروفات', compact: true)
        else
          ListGroup(children: [for (final t in drawer.transactions.take(6)) TxTile(tx: t)]),
        _SessionsHistory(sessions: overview.recentSessions),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _SessionsHistory extends StatelessWidget {
  const _SessionsHistory({required this.sessions});
  final List<CashSession> sessions;

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader('الورديات السابقة'),
        ListGroup(
          children: [
            for (final s in sessions.take(3))
              ListTile(
                title: Text('${s.number} • ${Fmt.dayLabel(s.openedAt)}'),
                subtitle: Text('افتتاح ${Fmt.money(s.openingBalance)} • إقفال ${Fmt.money(s.countedCash ?? 0)} • ${s.closedBy ?? ''}'),
                trailing: s.difference.abs() < 0.01
                    ? const StatusPill('مطابق', tone: Tone.success)
                    : StatusPill('${s.difference > 0 ? 'زيادة' : 'عجز'} ${Fmt.money(s.difference.abs())}', tone: s.difference > 0 ? Tone.info : Tone.danger),
                onTap: () => context.push(SessionReportScreen(sessionId: s.id)),
              ),
          ],
        ),
      ],
    );
  }
}

class TxTile extends StatelessWidget {
  const TxTile({super.key, required this.tx, this.showAccount = false});
  final MoneyTx tx;
  final bool showAccount;

  @override
  Widget build(BuildContext context) {
    final t = tx;
    final pal = context.palette;
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: t.isIn ? pal.successBg : pal.dangerBg, borderRadius: BorderRadius.circular(10)),
        child: Icon(t.isIn ? Icons.south_west_rounded : Icons.north_east_rounded, color: t.isIn ? pal.success : pal.danger, size: 18),
      ),
      title: Text(t.type == TxType.expense && t.category != null ? '${t.type.label} • ${t.category}' : t.type.label),
      subtitle: Text(
        [Fmt.relative(t.date), if (t.refNumber != null) t.refNumber!, t.user, if (showAccount) t.account.label, if (t.note.isNotEmpty && t.note != t.category) t.note].join(' • '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        '${t.isIn ? '+' : '-'}${Fmt.money(t.amount)}',
        style: context.text.titleSmall?.copyWith(color: t.isIn ? pal.success : pal.danger),
      ),
    );
  }
}
