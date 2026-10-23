import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/di.dart';
import '../../app/theme.dart';
import '../../core/widgets/widgets.dart';

/// Lets the user point the app at the shop server (PC running the backend on the same Wi-Fi).
Future<void> showServerDialog(BuildContext context) async {
  final api = context.read<AppDependencies>().api;
  if (api == null) return;
  final ctrl = TextEditingController(text: api.baseUrl);
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      var testing = false;
      bool? ok;
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('عنوان خادم المحل'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('اكتب عنوان الجهاز الذي يعمل عليه السيرفر على نفس الشبكة، مثال: 192.168.1.14:3000',
                  style: ctx.text.bodySmall),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.dns_outlined), hintText: 'http://192.168.1.14:3000/api'),
              ),
              if (ok != null) ...[
                const SizedBox(height: 10),
                Text(ok! ? 'تم الاتصال بالخادم بنجاح' : 'تعذّر الاتصال بهذا العنوان',
                    style: TextStyle(color: ok! ? ctx.palette.success : ctx.palette.danger)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            TextButton(
              onPressed: testing
                  ? null
                  : () async {
                      setState(() => testing = true);
                      await api.setBaseUrl(ctrl.text);
                      final res = await api.ping();
                      setState(() {
                        testing = false;
                        ok = res;
                      });
                    },
              child: const Text('اختبار'),
            ),
            FilledButton(
              onPressed: () async {
                await api.setBaseUrl(ctrl.text);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) showToast(context, 'تم حفظ عنوان الخادم');
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      );
    },
  );
}
