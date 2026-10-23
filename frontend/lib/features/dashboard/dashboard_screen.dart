import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/nav.dart';
import '../../app/session_cubit.dart';
import '../../app/theme.dart';
import '../../core/data_bus.dart';
import '../../core/format.dart';
import '../../core/query_cubit.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../cash/cash_screen.dart';
import '../cash/drawer_guard.dart';
import '../common/pickers.dart';
import '../common/product_widgets.dart';
import '../invoices/invoices_list_screen.dart';
import '../notifications/notifications_screen.dart';
import '../parties/parties_screen.dart';
import '../parties/party_payment_screen.dart';
import '../products/product_details_screen.dart';
import '../products/products_screen.dart';
import '../purchases/purchase_form_screen.dart';
import '../reports/financial_report_screen.dart';
import '../shell/home_shell.dart';

typedef _Cubit = QueryCubit<DashboardData, Null>;
typedef AlertsCubit = QueryCubit<List<AppAlert>, Null>;

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (c) => simpleQuery(
            () => c.read<ReportRepository>().getDashboard(),
            bus: c.read<DataBus>(),
            topics: const {DataTopic.invoices, DataTopic.cash, DataTopic.products, DataTopic.parties},
          ),
        ),
        BlocProvider(
          create: (c) => simpleQuery(() => c.read<AlertRepository>().getAlerts(), bus: c.read<DataBus>(), topics: const {DataTopic.alerts}),
        ),
      ],
      child: const _View(),
    );
  }
}

class _View extends StatelessWidget {
  const _View();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionCubit>().state;
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'صباح الخير' : 'مساء الخير';
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$greeting، ${session.user?.name.split(' ').first ?? ''}', style: context.text.titleLarge),
            Text('${session.settings.storeName} • ${Fmt.weekday(DateTime.now())} ${Fmt.date(DateTime.now())}', style: context.text.bodySmall),
          ],
        ),
        actions: [
          BlocBuilder<AlertsCubit, ViewState<List<AppAlert>>>(
            builder: (context, s) {
              final unread = s.data?.where((a) => !a.isRead).length ?? 0;
              return IconButton(
                tooltip: 'التنبيهات',
                icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.notifications_outlined)),
                onPressed: () => context.push(const NotificationsScreen()),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: BlocBuilder<_Cubit, ViewState<DashboardData>>(
        builder: (context, state) => AsyncBody<DashboardData>(
          state: state,
          onRetry: context.read<_Cubit>().load,
          builder: (d) => RefreshIndicator(
            onRefresh: context.read<_Cubit>().load,
            child: _Content(data: d),
          ),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.data});
  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final pal = context.palette;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (!d.drawerOpen) ...[
          Material(
            color: pal.warningBg,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              leading: Icon(Icons.lock_outline_rounded, color: pal.warning),
              title: Text('الخزنة مغلقة', style: TextStyle(color: pal.warning)),
              subtitle: const Text('افتح وردية لبدء البيع النقدي'),
              trailing: FilledButton.tonal(onPressed: () => promptOpenDrawer(context, fromError: false), child: const Text('فتح')),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _TodayCard(data: d),
        const SizedBox(height: 16),
        const _QuickActions(),
        const SizedBox(height: 22),
        Text('الأرصدة', style: context.text.titleMedium),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _BalanceRow(
                icon: Icons.point_of_sale_rounded,
                tone: Tone.primary,
                label: d.drawerOpen ? 'رصيد الخزنة' : 'رصيد الخزنة (مُقفلة)',
                value: Fmt.money(d.cashBalance),
                onTap: () => context.push(const CashScreen()),
              ),
              const Divider(indent: 64),
              _BalanceRow(
                icon: Icons.call_received_rounded,
                tone: Tone.warning,
                label: 'ديون العملاء',
                value: Fmt.money(d.customerDebts),
                onTap: () => context.read<ShellCubit>().go(ShellTab.customers),
              ),
              const Divider(indent: 64),
              _BalanceRow(
                icon: Icons.call_made_rounded,
                tone: Tone.danger,
                label: 'ديون الموردين',
                value: Fmt.money(d.supplierDebts),
                onTap: () => context.push(const PartiesScreen(type: PartyType.supplier)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(child: Text('مخزون منخفض', style: context.text.titleMedium)),
            if (d.lowStock.isNotEmpty)
              TextButton(
                onPressed: () => context.push(const ProductsScreen(initialFilter: ProductStockFilter.low)),
                child: const Text('عرض الكل'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (d.lowStock.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, color: pal.success),
                  const SizedBox(width: 10),
                  const Text('كل المنتجات في الحدود الآمنة'),
                ],
              ),
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < d.lowStock.length && i < 4; i++) ...[
                  if (i > 0) const Divider(indent: 64),
                  ListTile(
                    leading: ProductThumb(d.lowStock[i], size: 38),
                    title: Text(d.lowStock[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('الحد الأدنى ${Fmt.qty(d.lowStock[i].minStock)} ${d.lowStock[i].unit}'),
                    trailing: StockPill(d.lowStock[i]),
                    onTap: () => context.push(ProductDetailsScreen(productId: d.lowStock[i].id)),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// Today at a glance: sales (headline), profit and purchases.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.data});
  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final on = context.colors.onPrimary;
    final soft = on.withValues(alpha: 0.75);
    final change = d.yesterdaySales == 0 ? null : (d.todaySales - d.yesterdaySales) / d.yesterdaySales * 100;
    final isAdmin = context.perms.isAdmin;

    Widget metric(String label, String value, VoidCallback onTap) => Expanded(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: context.text.labelMedium?.copyWith(color: soft)),
                  const SizedBox(height: 2),
                  FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: context.text.titleMedium?.copyWith(color: on))),
                ],
              ),
            ),
          ),
        );

    return Material(
      color: context.colors.primary,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(const InvoicesListScreen(type: InvoiceType.sale)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('مبيعات اليوم', style: context.text.labelLarge?.copyWith(color: soft)),
                  const Spacer(),
                  if (change != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        '${change >= 0 ? '▲' : '▼'} ${Fmt.percent(change.abs())} عن أمس',
                        style: context.text.labelSmall?.copyWith(color: on),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(Fmt.money(d.todaySales), style: context.text.headlineMedium?.copyWith(color: on, fontSize: 30)),
              ),
              Text('${d.todaySalesCount} فاتورة', style: context.text.bodySmall?.copyWith(color: soft)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Divider(color: on.withValues(alpha: 0.2), height: 1),
              ),
              Row(
                children: [
                  if (isAdmin) ...[
                    metric('الربح', Fmt.money(d.todayProfit), () => context.push(const FinancialReportScreen())),
                    Container(width: 1, height: 34, color: on.withValues(alpha: 0.2), margin: const EdgeInsets.symmetric(horizontal: 12)),
                  ],
                  metric('المشتريات', Fmt.money(d.todayPurchases), () => context.push(const InvoicesListScreen(type: InvoiceType.purchase))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({required this.icon, required this.tone, required this.label, required this.value, required this.onTap});
  final IconData icon;
  final Tone tone;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = context.tone(tone);
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: fg, size: 20),
      ),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: context.text.titleSmall),
          const SizedBox(width: 4),
          Icon(Icons.chevron_left_rounded, color: context.palette.muted),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final actions = <(IconData, String, VoidCallback)>[
      (Icons.add_shopping_cart_rounded, 'مبيعات', () => context.read<ShellCubit>().go(ShellTab.pos)),
      (Icons.local_shipping_outlined, 'شراء', () => context.push(const PurchaseFormScreen())),
      (
        Icons.call_received_rounded,
        'تحصيل',
        () async {
          final p = await pickParty(context, PartyType.customer);
          if (p != null && context.mounted) context.push(PartyPaymentScreen(partyId: p.id));
        }
      ),
    ];
    return Row(
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(
            child: Material(
              color: context.colors.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: context.palette.border)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: actions[i].$3,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: context.colors.primary.withValues(alpha: 0.1), shape: BoxShape.circle),
                        child: Icon(actions[i].$1, color: context.colors.primary, size: 22),
                      ),
                      const SizedBox(height: 8),
                      Text(actions[i].$2, style: context.text.labelMedium, maxLines: 1),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
