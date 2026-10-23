import 'package:flutter/material.dart';

import '../../app/nav.dart';
import '../../app/session_cubit.dart';
import '../../app/theme.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import 'financial_report_screen.dart';
import 'stock_report_screen.dart';
import 'trade_report_screen.dart';

/// Reports hub.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isAdmin = context.perms.isAdmin;
    final groups = <(String, List<(IconData, String, String, Widget)>)>[
      (
        'تقارير المبيعات',
        [
          (Icons.calendar_view_day_outlined, 'المبيعات اليومية / الأسبوعية / الشهرية', 'الاتجاه والمقارنة', const TradeReportScreen(type: InvoiceType.sale)),
        ],
      ),
      (
        'تقارير المشتريات',
        [
          (Icons.local_shipping_outlined, 'المشتريات اليومية / الشهرية', 'حركة التوريد', const TradeReportScreen(type: InvoiceType.purchase)),
        ],
      ),
      (
        'تقارير المخزون',
        [
          (Icons.warehouse_outlined, 'المخزون الحالي والقيمة', 'منخفض، نفد، حركة المخزون', const StockReportScreen()),
        ],
      ),
      if (isAdmin)
        (
          'التقارير المالية',
          [
            (Icons.account_balance_wallet_outlined, 'الإيرادات والأرباح والمصروفات', 'قائمة الدخل، الديون، التدفق النقدي', const FinancialReportScreen()),
          ],
        ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('التقارير')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (final (title, items) in groups) ...[
            SectionHeader(title),
            ListGroup(
              children: [
                for (final (icon, label, sub, page) in items)
                  ListTile(
                    leading: Icon(icon, color: context.colors.primary),
                    title: Text(label),
                    subtitle: Text(sub),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => context.push(page),
                  ),
              ],
            ),
          ],
          if (!isAdmin)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('التقارير المالية متاحة للمدير فقط', style: context.text.bodySmall, textAlign: TextAlign.center),
            ),
        ],
      ),
    );
  }
}
