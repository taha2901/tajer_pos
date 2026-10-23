import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../errors.dart';

enum ToastKind { success, error, info }

void showToast(BuildContext context, String message, {ToastKind kind = ToastKind.success}) {
  final p = context.palette;
  final (icon, color) = switch (kind) {
    ToastKind.success => (Icons.check_circle_rounded, p.success),
    ToastKind.error => (Icons.error_rounded, p.danger),
    ToastKind.info => (Icons.info_rounded, p.info),
  };
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      backgroundColor: context.colors.inverseSurface,
      duration: Duration(milliseconds: kind == ToastKind.error ? 3500 : 2200),
      content: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: context.colors.onInverseSurface))),
        ],
      ),
    ));
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'تأكيد',
  String cancelLabel = 'إلغاء',
  bool destructive = false,
  IconData? icon,
}) async {
  final p = context.palette;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: icon == null
          ? null
          : Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: destructive ? p.dangerBg : p.infoBg, shape: BoxShape.circle),
              child: Icon(icon, color: destructive ? p.danger : p.info),
            ),
      title: Text(title, textAlign: icon == null ? null : TextAlign.center),
      content: Text(message, style: ctx.text.bodyMedium?.copyWith(color: p.muted)),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        Row(
          children: [
            Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: Text(cancelLabel))),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                style: destructive ? FilledButton.styleFrom(backgroundColor: p.danger) : null,
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmLabel),
              ),
            ),
          ],
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<void> showErrorDialog(BuildContext context, Object error) {
  final p = context.palette;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: p.dangerBg, shape: BoxShape.circle),
        child: Icon(error is NetworkException ? Icons.wifi_off_rounded : Icons.block_rounded, color: p.danger),
      ),
      title: Text(error is NetworkException ? 'مشكلة في الاتصال' : 'لا يمكن إتمام العملية', textAlign: TextAlign.center),
      content: Text(errorMessage(error), textAlign: TextAlign.center),
      actions: [
        SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))),
      ],
    ),
  );
}

/// Runs a mutation with a blocking progress indicator.
/// Returns the result, or null if it failed (error already shown).
Future<T?> runTask<T>(
  BuildContext context,
  Future<T> Function() task, {
  String? success,
  bool showErrors = true,
  void Function(Object error)? onError,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  var open = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => PopScope(
      canPop: false,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: context.colors.surface, borderRadius: BorderRadius.circular(16)),
          child: const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3)),
        ),
      ),
    ),
  ).then((_) => open = false);

  try {
    final result = await task();
    if (open) navigator.pop();
    if (success != null && context.mounted) showToast(context, success);
    return result;
  } catch (e) {
    if (open) navigator.pop();
    onError?.call(e);
    if (showErrors && onError == null && context.mounted) await showErrorDialog(context, e);
    return null;
  }
}

/// Standard modal bottom sheet with title and safe keyboard padding.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext ctx) builder,
  String? title,
  bool expand = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) {
      final content = Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(title, style: ctx.text.titleLarge),
              ),
            Flexible(child: builder(ctx)),
          ],
        ),
      );
      return expand ? SizedBox(height: MediaQuery.sizeOf(ctx).height * 0.88, child: content) : content;
    },
  );
}
