import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/di.dart';
import '../../app/session_cubit.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../auth/server_dialog.dart';
import '../pos/cart_cubit.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SessionCubit, SessionState>(
      builder: (context, s) {
        final cubit = context.read<SessionCubit>();
        final st = s.settings;
        final admin = s.permissions.canEditSettings;
        void save(AppSettings next) => cubit.updateSettings(next);

        return Scaffold(
          appBar: AppBar(title: const Text('الإعدادات')),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              if (!admin)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: context.palette.infoBg, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline, color: context.palette.info, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text('تعديل إعدادات المحل والصلاحيات متاح للمدير فقط', style: TextStyle(color: context.palette.info))),
                      ],
                    ),
                  ),
                ),
              const SectionHeader('بيانات المحل'),
              ListGroup(
                children: [
                  _textTile(context, 'اسم المحل', st.storeName, Icons.storefront_outlined, admin, (v) => save(st.copyWith(storeName: v))),
                  _textTile(context, 'الهاتف', st.storePhone, Icons.phone_outlined, admin, (v) => save(st.copyWith(storePhone: v))),
                  _textTile(context, 'العنوان', st.storeAddress, Icons.location_on_outlined, admin, (v) => save(st.copyWith(storeAddress: v))),
                  _textTile(context, 'تذييل الفاتورة', st.invoiceFooter, Icons.receipt_outlined, admin, (v) => save(st.copyWith(invoiceFooter: v))),
                ],
              ),
              const SectionHeader('البيع'),
              ListGroup(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.remove_shopping_cart_outlined),
                    title: const Text('السماح بالبيع بدون رصيد'),
                    subtitle: const Text('بيع كمية أكبر من المخزون المتاح'),
                    value: st.allowNegativeStock,
                    onChanged: admin ? (v) => save(st.copyWith(allowNegativeStock: v)) : null,
                  ),
                ],
              ),
              const SectionHeader('التنبيهات والخزنة'),
              ListGroup(
                children: [
                  _numberTile(context, 'حد تنبيه المصروف الكبير', st.largeExpenseThreshold, Fmt.currency, Icons.receipt_long_outlined, admin,
                      (v) => save(st.copyWith(largeExpenseThreshold: v))),
                  _numberTile(context, 'استحقاق المديونية بعد', st.debtDueDays.toDouble(), 'يوم', Icons.schedule_rounded, admin,
                      (v) => save(st.copyWith(debtDueDays: v.round()))),
                  _numberTile(context, 'تذكير إقفال اليومية الساعة', st.closingReminderHour.toDouble(), '', Icons.alarm_rounded, admin,
                      (v) => save(st.copyWith(closingReminderHour: v.round().clamp(0, 23)))),
                ],
              ),
              const SectionHeader('المظهر'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.light, label: Text('فاتح'), icon: Icon(Icons.light_mode_outlined)),
                    ButtonSegment(value: ThemeMode.dark, label: Text('داكن'), icon: Icon(Icons.dark_mode_outlined)),
                    ButtonSegment(value: ThemeMode.system, label: Text('النظام'), icon: Icon(Icons.brightness_auto_outlined)),
                  ],
                  selected: {st.themeMode},
                  onSelectionChanged: (v) => save(st.copyWith(themeMode: v.first)),
                ),
              ),
              const SectionHeader('المستخدم'),
              ListGroup(
                children: [
                  ListTile(
                    leading: Initials(s.user?.name ?? '?', size: 38),
                    title: Text(s.user?.name ?? ''),
                    subtitle: Text(s.user?.username ?? ''),
                    trailing: TextButton(
                      onPressed: () async {
                        final ok = await confirmDialog(context, title: 'تسجيل الخروج؟', message: 'سيتم إفراغ السلة الحالية.', confirmLabel: 'خروج');
                        if (!ok || !context.mounted) return;
                        context.read<CartCubit>().clear();
                        Navigator.of(context).popUntil((r) => r.isFirst);
                        cubit.logout();
                      },
                      child: const Text('تبديل المستخدم'),
                    ),
                  ),
                ],
              ),
              const SectionHeader('الخادم والبيانات'),
              ListGroup(
                children: [
                  if (context.read<AppDependencies>().api case final api?)
                    ListTile(
                      leading: const Icon(Icons.dns_outlined),
                      title: const Text('عنوان خادم المحل'),
                      subtitle: Text(api.baseUrl, textDirection: TextDirection.ltr),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => showServerDialog(context),
                    ),
                  ListTile(
                    leading: Icon(Icons.restart_alt_rounded, color: context.palette.danger),
                    title: Text('إعادة تعيين البيانات التجريبية', style: TextStyle(color: context.palette.danger)),
                    subtitle: const Text('مسح كل العمليات وإعادة توليد 30 يوماً من البيانات'),
                    onTap: () async {
                      final ok = await confirmDialog(
                        context,
                        title: 'إعادة تعيين البيانات؟',
                        message: 'سيتم حذف كل ما أضفته وإعادة البيانات التجريبية الأصلية.',
                        confirmLabel: 'إعادة تعيين',
                        destructive: true,
                        icon: Icons.restart_alt_rounded,
                      );
                      if (!ok || !context.mounted) return;
                      context.read<CartCubit>().clear();
                      await runTask(context, cubit.resetDemoData, success: 'تمت إعادة تعيين البيانات');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Center(child: Text('تاجر POS • إصدار تجريبي 1.0.0', style: context.text.bodySmall)),
            ],
          ),
        );
      },
    );
  }

  Widget _textTile(BuildContext context, String label, String value, IconData icon, bool enabled, ValueChanged<String> onSave) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: enabled ? const Icon(Icons.edit_outlined, size: 18) : null,
      enabled: enabled,
      onTap: () async {
        final ctrl = TextEditingController(text: value);
        final v = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(label),
            content: TextField(controller: ctrl, autofocus: true, maxLines: null),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('حفظ')),
            ],
          ),
        );
        if (v != null && v.isNotEmpty) onSave(v);
      },
    );
  }

  Widget _numberTile(BuildContext context, String label, double value, String suffix, IconData icon, bool enabled, ValueChanged<double> onSave) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      trailing: Text('${Fmt.number(value)} $suffix', style: context.text.titleSmall),
      enabled: enabled,
      onTap: () async {
        final ctrl = TextEditingController(text: Fmt.qty(value));
        final v = await showDialog<double>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(label),
            content: MoneyField(controller: ctrl, label: label, suffix: suffix, autofocus: true),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              FilledButton(onPressed: () => Navigator.pop(ctx, parseNum(ctrl.text)), child: const Text('حفظ')),
            ],
          ),
        );
        if (v != null) onSave(v);
      },
    );
  }
}
