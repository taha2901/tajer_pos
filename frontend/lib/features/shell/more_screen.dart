import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/nav.dart';
import '../../app/session_cubit.dart';
import '../../app/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../cash/cash_screen.dart';
import '../cash/transactions_screen.dart';
import '../invoices/invoices_list_screen.dart';
import '../notifications/notifications_screen.dart';
import '../parties/parties_screen.dart';
import '../pos/cart_cubit.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<SessionCubit>().state.user;
    final items = <(String, List<(IconData, String, String, Widget)>)>[
      (
        'العمليات',
        [
          (Icons.local_shipping_outlined, 'المشتريات', 'فواتير الشراء والمرتجعات', const InvoicesListScreen(type: InvoiceType.purchase)),
          (Icons.receipt_long_outlined, 'فواتير البيع', 'السجل والمرتجعات', const InvoicesListScreen(type: InvoiceType.sale)),
          (Icons.store_mall_directory_outlined, 'الموردين', 'الحسابات والمستحقات', const PartiesScreen(type: PartyType.supplier)),
        ],
      ),
      (
        'المالية',
        [
          (Icons.point_of_sale_rounded, 'الخزنة', 'الوردية والإقفال اليومي', const CashScreen()),
          (Icons.receipt_outlined, 'المصروفات', 'تسجيل ومتابعة المصروفات', const TransactionsScreen(type: TxType.expense)),
          (Icons.insights_outlined, 'التقارير', 'المبيعات والمخزون والأرباح', const ReportsScreen()),
        ],
      ),
      (
        'النظام',
        [
          (Icons.notifications_outlined, 'التنبيهات', 'المخزون والمديونيات', const NotificationsScreen()),
          (Icons.settings_outlined, 'الإعدادات', 'المحل والصلاحيات', const SettingsScreen()),
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('المزيد')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (user != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: AppCard(
                child: Row(
                  children: [
                    Initials(user.name, size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user.name, style: context.text.titleMedium),
                          Text(user.username, style: context.text.bodySmall),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final ok = await confirmDialog(context, title: 'تسجيل الخروج؟', message: 'سيتم إفراغ السلة الحالية.', confirmLabel: 'خروج');
                        if (!ok || !context.mounted) return;
                        context.read<CartCubit>().clear();
                        context.read<SessionCubit>().logout();
                      },
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('خروج'),
                    ),
                  ],
                ),
              ),
            ),
          for (final (title, entries) in items) ...[
            SectionHeader(title),
            ListGroup(
              children: [
                for (final (icon, label, _, page) in entries)
                  ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: context.colors.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                      child: Icon(icon, color: context.colors.primary, size: 22),
                    ),
                    title: Text(label),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => context.push(page),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
