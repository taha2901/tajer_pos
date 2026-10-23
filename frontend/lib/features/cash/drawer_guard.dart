import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/session_cubit.dart';
import '../../app/theme.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/repositories/repositories.dart';

/// Asks for the opening balance and opens a cash session. Returns true if opened.
Future<bool> promptOpenDrawer(BuildContext context, {bool fromError = true}) async {
  final repo = context.read<CashRepository>();
  final suggested = await repo.suggestedOpening();
  if (!context.mounted) return false;
  final ctrl = TextEditingController(text: Fmt.qty(suggested));
  final form = GlobalKey<FormState>();
  final opened = await showAppSheet<bool>(
    context,
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: ctx.palette.warningBg, borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.lock_open_rounded, color: ctx.palette.warning),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fromError ? 'الخزنة مغلقة' : 'فتح وردية جديدة', style: ctx.text.titleLarge),
                        Text('أدخل النقدية الموجودة بالدرج لبدء الوردية', style: ctx.text.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              MoneyField(
                controller: ctrl,
                label: 'رصيد الافتتاح',
                autofocus: true,
                big: true,
                helper: 'آخر رصيد مُقفل: ${Fmt.money(suggested)}',
                validator: (v) => requiredNumber(v),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('فتح الوردية'),
                onPressed: () async {
                  if (!form.currentState!.validate()) return;
                  final ok = await runTask(ctx, () => repo.openSession(parseNum(ctrl.text)!), success: 'تم فتح الوردية');
                  if (ok != null && ctx.mounted) Navigator.pop(ctx, true);
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
  return opened ?? false;
}

/// Runs a mutation and recovers from the common business blocks:
/// closed drawer → offer to open it and retry; credit limit → admin override.
Future<T?> submitWithRecovery<T>(
  BuildContext context,
  Future<T> Function(bool overrideCreditLimit) task, {
  String? success,
}) async {
  var override = false;
  while (true) {
    if (!context.mounted) return null;
    Object? error;
    final result = await runTask<T>(context, () => task(override), success: success, onError: (e) => error = e);
    if (error == null) return result;
    if (!context.mounted) return null;
    final code = error is BusinessException ? (error as BusinessException).code : null;
    if (code == ErrorCodes.drawerClosed) {
      if (await promptOpenDrawer(context)) continue;
      return null;
    }
    if (code == ErrorCodes.creditLimit && !override && context.perms.canOverrideCreditLimit) {
      final ok = await confirmDialog(
        context,
        title: 'تجاوز حد الائتمان',
        message: '${errorMessage(error!)}\n\nهل تريد المتابعة بصلاحية المدير؟',
        confirmLabel: 'متابعة',
        icon: Icons.warning_amber_rounded,
      );
      if (ok && context.mounted) {
        override = true;
        continue;
      }
      return null;
    }
    await showErrorDialog(context, error!);
    return null;
  }
}
