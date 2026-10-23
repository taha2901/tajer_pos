import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme.dart';
import '../../core/widgets/widgets.dart';

/// Tabular data that can be exported / printed / shared.
class ExportTable {
  const ExportTable({required this.title, required this.headers, required this.rows, this.summary = const []});
  final String title;
  final List<String> headers;
  final List<List<String>> rows;
  final List<(String, String)> summary;

  String toCsv() {
    String esc(String s) => s.contains(',') || s.contains('"') ? '"${s.replaceAll('"', '""')}"' : s;
    final b = StringBuffer()..writeln(esc(title));
    for (final (k, v) in summary) {
      b.writeln('${esc(k)},${esc(v)}');
    }
    b.writeln(headers.map(esc).join(','));
    for (final r in rows) {
      b.writeln(r.map(esc).join(','));
    }
    return b.toString();
  }

  String toText() {
    final b = StringBuffer()..writeln('*$title*');
    for (final (k, v) in summary) {
      b.writeln('$k: $v');
    }
    b.writeln('');
    for (final r in rows) {
      b.writeln(r.join(' | '));
    }
    return b.toString();
  }
}

Future<void> shareText(BuildContext context, String text, {String? subject}) async {
  try {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  } catch (_) {
    if (context.mounted) showToast(context, 'المشاركة غير متاحة على هذا الجهاز', kind: ToastKind.error);
  }
}

/// Export options sheet (CSV is real via share; PDF / Excel are UI placeholders
/// until a backend or PDF service is connected).
Future<void> showExportSheet(BuildContext context, ExportTable table) {
  return showAppSheet<void>(
    context,
    title: 'تصدير "${table.title}"',
    builder: (ctx) => SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _option(ctx, Icons.table_view_outlined, 'ملف CSV', 'يفتح في Excel و Google Sheets', () {
            Navigator.pop(ctx);
            shareText(context, table.toCsv(), subject: table.title);
          }),
          _option(ctx, Icons.picture_as_pdf_outlined, 'PDF', 'تقرير جاهز للطباعة', () {
            Navigator.pop(ctx);
            showPrintPreview(context, table);
          }),
          _option(ctx, Icons.grid_on_outlined, 'Excel (xlsx)', 'سيتوفر عند ربط الخادم', null),
          _option(ctx, Icons.chat_outlined, 'مشاركة كنص', 'واتساب، رسائل...', () {
            Navigator.pop(ctx);
            shareText(context, table.toText(), subject: table.title);
          }),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Widget _option(BuildContext context, IconData icon, String title, String sub, VoidCallback? onTap) => ListTile(
      enabled: onTap != null,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: context.palette.subtle, borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: onTap == null ? context.palette.muted : context.colors.primary),
      ),
      title: Text(title),
      subtitle: Text(sub),
      onTap: onTap,
    );

/// Print preview: paper-like rendering + printer selection (UI only).
Future<void> showPrintPreview(BuildContext context, ExportTable table) {
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => PrintPreviewScreen(
      title: table.title,
      child: _TablePaper(table: table),
    ),
  ));
}

class PrintPreviewScreen extends StatefulWidget {
  const PrintPreviewScreen({super.key, required this.title, required this.child, this.receipt = false});
  final String title;
  final Widget child;
  final bool receipt;

  @override
  State<PrintPreviewScreen> createState() => _PrintPreviewScreenState();
}

class _PrintPreviewScreenState extends State<PrintPreviewScreen> {
  late String _printer = widget.receipt ? 'طابعة حرارية 80mm (Bluetooth)' : 'طابعة المكتب A4 (Wi‑Fi)';
  int _copies = 1;

  @override
  Widget build(BuildContext context) {
    final printers = ['طابعة حرارية 80mm (Bluetooth)', 'طابعة حرارية 58mm (USB)', 'طابعة المكتب A4 (Wi‑Fi)', 'حفظ كملف PDF'];
    return Scaffold(
      appBar: AppBar(title: const Text('معاينة الطباعة')),
      backgroundColor: context.palette.subtle,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Container(
            constraints: BoxConstraints(maxWidth: widget.receipt ? 340 : 640),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: Theme(data: Theme.of(context).copyWith(extensions: [AppPalette.light]), child: DefaultTextStyle.merge(style: const TextStyle(color: Colors.black87), child: widget.child)),
          ),
        ),
      ),
      bottomNavigationBar: BottomBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _printer,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'الطابعة', prefixIcon: Icon(Icons.print_outlined)),
                    items: [for (final p in printers) DropdownMenuItem(value: p, child: Text(p, overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => setState(() => _printer = v!),
                  ),
                ),
                const SizedBox(width: 10),
                QtyStepper(value: _copies.toDouble(), min: 1, max: 5, compact: true, onChanged: (v) => setState(() => _copies = v.toInt())),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.print_rounded),
                label: const Text('طباعة'),
                onPressed: () async {
                  await runTask(context, () => Future<void>.delayed(const Duration(milliseconds: 900)));
                  if (!context.mounted) return;
                  showToast(context, 'تم إرسال $_copies نسخة إلى "$_printer"');
                  Navigator.pop(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TablePaper extends StatelessWidget {
  const _TablePaper({required this.table});
  final ExportTable table;

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: Colors.black);
    const cell = TextStyle(fontSize: 11.5, color: Colors.black87);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(table.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.black)),
        const SizedBox(height: 10),
        for (final (k, v) in table.summary)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(children: [Expanded(child: Text(k, style: cell)), Text(v, style: head)]),
          ),
        const SizedBox(height: 12),
        Table(
          border: TableBorder.all(color: Colors.black26, width: 0.6),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFFF0F0F0)),
              children: [for (final h in table.headers) Padding(padding: const EdgeInsets.all(6), child: Text(h, style: head))],
            ),
            for (final r in table.rows.take(200))
              TableRow(children: [for (final c in r) Padding(padding: const EdgeInsets.all(6), child: Text(c, style: cell))]),
          ],
        ),
      ],
    );
  }
}
