import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/nav.dart';
import '../../app/session_cubit.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../common/export.dart';
import '../shell/home_shell.dart';
import 'invoice_details_screen.dart';

/// Shown right after checkout / purchase: success + receipt + next actions.
class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({super.key, required this.invoice, this.change = 0, this.justCreated = false});
  final Invoice invoice;
  final double change;
  final bool justCreated;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isSale = invoice.type == InvoiceType.sale;
    return Scaffold(
      appBar: AppBar(title: Text(invoice.number)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (justCreated) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: p.successBg, shape: BoxShape.circle),
                child: Icon(Icons.check_rounded, color: p.success, size: 36),
              ),
            ),
            const SizedBox(height: 12),
            Text(isSale ? 'تمت عملية البيع' : 'تم تسجيل فاتورة الشراء', style: context.text.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              invoice.due > 0
                  ? 'تم تسجيل ${Fmt.money(invoice.due)} آجل على ${invoice.partyName}'
                  : 'تم تحديث المخزون${isSale ? ' والخزنة' : ''} بنجاح',
              style: context.text.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (change > 0) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: p.warningBg, borderRadius: BorderRadius.circular(14)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('الباقي للعميل: ', style: context.text.titleMedium?.copyWith(color: p.warning)),
                    Text(Fmt.money(change), style: context.text.headlineSmall?.copyWith(color: p.warning)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
          ],
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: AppCard(child: InvoicePaper(invoice: invoice, settings: context.settings, change: change)),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('طباعة'),
                  onPressed: () => printInvoice(context, invoice),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('مشاركة'),
                  onPressed: () => shareText(context, invoiceShareText(invoice, context.settings), subject: invoice.number),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('تفاصيل الفاتورة'),
            onPressed: () => context.replace(InvoiceDetailsScreen(invoiceId: invoice.id)),
          ),
        ],
      ),
      bottomNavigationBar: justCreated && isSale
          ? BottomBar(
              child: FilledButton.icon(
                icon: const Icon(Icons.add_shopping_cart_rounded),
                label: const Text('مبيعات'),
                onPressed: () {
                  context.read<ShellCubit>().go(ShellTab.pos);
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
              ),
            )
          : null,
    );
  }
}

void printInvoice(BuildContext context, Invoice invoice) {
  context.push(PrintPreviewScreen(
    title: invoice.number,
    receipt: true,
    child: InvoicePaper(invoice: invoice, settings: context.settings),
  ));
}

/// Receipt-style rendering used on screen and in print preview.
class InvoicePaper extends StatelessWidget {
  const InvoicePaper({super.key, required this.invoice, required this.settings, this.change = 0});
  final Invoice invoice;
  final AppSettings settings;
  final double change;

  @override
  Widget build(BuildContext context) {
    final i = invoice;
    final small = context.text.bodySmall?.copyWith(color: context.palette.muted);
    final isSale = i.type == InvoiceType.sale;
    Widget dashed() => Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: LayoutBuilder(
            builder: (_, c) => Row(
              children: List.generate(
                (c.maxWidth / 7).floor(),
                (_) => Expanded(child: Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 1.5), color: context.palette.border)),
              ),
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(settings.storeName, style: context.text.titleLarge, textAlign: TextAlign.center),
        Text(settings.storeAddress, style: small, textAlign: TextAlign.center),
        Text('هاتف ${settings.storePhone}', style: small, textAlign: TextAlign.center),
        dashed(),
        Text(i.type.label, style: context.text.titleSmall, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        _kv(context, 'رقم الفاتورة', i.number),
        _kv(context, 'التاريخ', Fmt.dateTime(i.date)),
        _kv(context, isSale ? 'العميل' : 'المورد', i.partyName),
        if (i.supplierRef.isNotEmpty) _kv(context, 'فاتورة المورد', i.supplierRef),
        _kv(context, isSale ? 'الكاشير' : 'المستخدم', i.user),
        dashed(),
        Row(
          children: [
            Expanded(flex: 5, child: Text('الصنف', style: context.text.labelMedium)),
            Expanded(flex: 2, child: Text('كمية', style: context.text.labelMedium, textAlign: TextAlign.center)),
            Expanded(flex: 3, child: Text('الإجمالي', style: context.text.labelMedium, textAlign: TextAlign.end)),
          ],
        ),
        const SizedBox(height: 6),
        for (final l in i.lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.productName, style: context.text.bodyMedium?.copyWith(height: 1.3)),
                      Text(
                        '${Fmt.money(l.unitPrice)}${l.discount > 0 ? ' • خصم ${Fmt.money(l.discount)}' : ''}${l.returnedQty > 0 ? ' • مرتجع ${Fmt.qty(l.returnedQty)}' : ''}',
                        style: small,
                      ),
                    ],
                  ),
                ),
                Expanded(flex: 2, child: Text(Fmt.qty(l.qty), textAlign: TextAlign.center)),
                Expanded(flex: 3, child: Text(Fmt.money(l.total), textAlign: TextAlign.end)),
              ],
            ),
          ),
        dashed(),
        if (i.totalDiscount > 0) ...[
          _kv(context, 'الإجمالي قبل الخصم', Fmt.money(i.subtotal + i.linesDiscount)),
          _kv(context, 'الخصم', '- ${Fmt.money(i.totalDiscount)}'),
        ],
        _kv(context, 'الإجمالي', Fmt.money(i.total), strong: true),
        if (i.hasReturns) _kv(context, 'المرتجعات', '- ${Fmt.money(i.returnedAmount)}'),
        for (final p in i.payments) _kv(context, 'مدفوع ${p.method.label}', Fmt.money(p.amount)),
        if (i.paid != i.payments.fold<double>(0, (s, p) => s + p.amount)) _kv(context, 'إجمالي المسدد', Fmt.money(i.paid)),
        if (change > 0) _kv(context, 'الباقي', Fmt.money(change)),
        if (i.due > 0) _kv(context, 'المتبقي (آجل)', Fmt.money(i.due), strong: true),
        if (i.note.isNotEmpty) ...[dashed(), Text('ملاحظة: ${i.note}', style: small)],
        dashed(),
        Center(
          child: BarcodeWidget(
            barcode: Barcode.code128(),
            data: i.number,
            width: 200,
            height: 44,
            drawText: false,
            color: context.colors.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Text(settings.invoiceFooter, style: small, textAlign: TextAlign.center),
      ],
    );
  }

  Widget _kv(BuildContext context, String k, String v, {bool strong = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(k, style: strong ? context.text.titleSmall : context.text.bodySmall)),
            Text(v, style: strong ? context.text.titleMedium : context.text.bodyMedium),
          ],
        ),
      );
}

String invoiceShareText(Invoice i, AppSettings s) {
  final b = StringBuffer()
    ..writeln('*${s.storeName}*')
    ..writeln('${i.type.label} ${i.number}')
    ..writeln(Fmt.dateTime(i.date))
    ..writeln('${i.type == InvoiceType.sale ? 'العميل' : 'المورد'}: ${i.partyName}')
    ..writeln('──────────');
  for (final l in i.lines) {
    b.writeln('${l.productName}\n  ${Fmt.qty(l.qty)} × ${Fmt.money(l.unitPrice)} = ${Fmt.money(l.total)}');
  }
  b.writeln('──────────');
  if (i.totalDiscount > 0) b.writeln('الخصم: ${Fmt.money(i.totalDiscount)}');
  b.writeln('*الإجمالي: ${Fmt.money(i.total)}*');
  if (i.hasReturns) b.writeln('المرتجعات: ${Fmt.money(i.returnedAmount)}');
  b.writeln('المدفوع: ${Fmt.money(i.paid)}');
  if (i.due > 0) b.writeln('المتبقي: ${Fmt.money(i.due)}');
  b.writeln(s.invoiceFooter);
  return b.toString();
}
