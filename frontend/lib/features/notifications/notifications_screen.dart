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
import '../cash/cash_screen.dart';
import '../cash/transactions_screen.dart';
import '../parties/party_details_screen.dart';
import '../products/product_details_screen.dart';

typedef _Cubit = QueryCubit<List<AppAlert>, Null>;

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _filter = 'all';

  static const _filters = {'all': 'الكل', 'unread': 'غير مقروء', 'stock': 'المخزون', 'debts': 'المديونيات', 'cash': 'الخزنة'};

  bool _match(AppAlert a) => switch (_filter) {
        'unread' => !a.isRead,
        'stock' => a.kind == AlertKind.lowStock || a.kind == AlertKind.outOfStock,
        'debts' => a.kind == AlertKind.customerDebtDue || a.kind == AlertKind.customerOverLimit || a.kind == AlertKind.supplierPaymentDue,
        'cash' => a.kind == AlertKind.largeExpense || a.kind == AlertKind.closingReminder,
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => simpleQuery(() => c.read<AlertRepository>().getAlerts(), bus: c.read<DataBus>(), topics: const {DataTopic.alerts}),
      child: BlocBuilder<_Cubit, ViewState<List<AppAlert>>>(
        builder: (context, state) {
          final repo = context.read<AlertRepository>();
          final unread = state.data?.where((a) => !a.isRead).length ?? 0;
          return Scaffold(
            appBar: AppBar(
              title: const Text('التنبيهات'),
              actions: [
                if (unread > 0) TextButton(onPressed: repo.markAllRead, child: const Text('تعليم الكل كمقروء')),
              ],
            ),
            body: Column(
              children: [
                const SizedBox(height: 8),
                ChipsRow<String>(
                  values: _filters.keys.toList(),
                  selected: _filter,
                  label: (k) => _filters[k]!,
                  count: (k) => k == 'unread' ? unread : null,
                  onSelected: (k) => setState(() => _filter = k),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: AsyncBody<List<AppAlert>>(
                    state: state,
                    onRetry: context.read<_Cubit>().load,
                    isEmpty: (d) => d.where(_match).isEmpty,
                    empty: const EmptyView(
                      icon: Icons.notifications_none_rounded,
                      title: 'لا توجد تنبيهات',
                      message: 'كل شيء على ما يرام — ستظهر هنا تنبيهات المخزون والمديونيات والخزنة',
                    ),
                    builder: (list) {
                      final items = list.where(_match).toList();
                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _AlertTile(alert: items[i], onOpen: () => _open(context, items[i])),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _open(BuildContext context, AppAlert a) {
    context.read<AlertRepository>().markRead(a.id);
    final target = a.targetId;
    if (target == null) return;
    switch (a.kind) {
      case AlertKind.lowStock:
      case AlertKind.outOfStock:
        context.push(ProductDetailsScreen(productId: target));
      case AlertKind.customerDebtDue:
      case AlertKind.customerOverLimit:
      case AlertKind.supplierPaymentDue:
        context.push(PartyDetailsScreen(partyId: target));
      case AlertKind.largeExpense:
        context.push(const TransactionsScreen(type: TxType.expense));
      case AlertKind.closingReminder:
        context.push(const CashScreen());
    }
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({required this.alert, required this.onOpen});
  final AppAlert alert;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final a = alert;
    final tone = switch (a.severity) {
      AlertSeverity.critical => Tone.danger,
      AlertSeverity.warning => Tone.warning,
      AlertSeverity.info => Tone.info,
    };
    final icon = switch (a.kind) {
      AlertKind.lowStock => Icons.inventory_outlined,
      AlertKind.outOfStock => Icons.remove_shopping_cart_outlined,
      AlertKind.customerDebtDue => Icons.schedule_rounded,
      AlertKind.customerOverLimit => Icons.credit_card_off_outlined,
      AlertKind.supplierPaymentDue => Icons.local_shipping_outlined,
      AlertKind.largeExpense => Icons.receipt_long_outlined,
      AlertKind.closingReminder => Icons.lock_clock_outlined,
    };
    final (fg, bg) = context.tone(tone);
    return AppCard(
      padding: const EdgeInsets.all(14),
      color: a.isRead ? null : context.colors.primary.withValues(alpha: 0.03),
      onTap: onOpen,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: fg, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(a.title, style: context.text.titleSmall?.copyWith(fontWeight: a.isRead ? FontWeight.w500 : FontWeight.w700))),
                    if (!a.isRead)
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: context.colors.primary, shape: BoxShape.circle)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(a.body, style: context.text.bodySmall),
                const SizedBox(height: 6),
                Row(
                  children: [
                    StatusPill(a.kind.label, tone: tone),
                    const Spacer(),
                    Text(Fmt.relative(a.date), style: context.text.labelSmall?.copyWith(color: context.palette.muted)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
