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
import '../common/export.dart';
import '../parties/party_details_screen.dart';
import '../parties/party_payment_screen.dart';
import 'receipt_screen.dart';
import 'return_screen.dart';

typedef _Data = (Invoice, List<ReturnDoc>);

class InvoiceDetailsScreen extends StatelessWidget {
  const InvoiceDetailsScreen({super.key, required this.invoiceId});
  final String invoiceId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => simpleQuery<_Data>(
        () async {
          final repo = c.read<InvoiceRepository>();
          final inv = await repo.getInvoice(invoiceId);
          return (inv, await repo.getReturns(invoiceId: invoiceId));
        },
        bus: c.read<DataBus>(),
        topics: const {DataTopic.invoices},
      ),
      child: BlocBuilder<QueryCubit<_Data, Null>, ViewState<_Data>>(
        builder: (context, state) {
          final inv = state.data?.$1;
          return Scaffold(
            appBar: AppBar(
              title: Text(inv?.number ?? 'الفاتورة'),
              actions: [
                if (inv != null) ...[
                  IconButton(tooltip: 'طباعة', icon: const Icon(Icons.print_outlined), onPressed: () => printInvoice(context, inv)),
                  IconButton(
                    tooltip: 'مشاركة',
                    icon: const Icon(Icons.share_outlined),
                    onPressed: () => shareText(context, invoiceShareText(inv, context.settings), subject: inv.number),
                  ),
                ],
              ],
            ),
            body: AsyncBody<_Data>(
              state: state,
              onRetry: context.read<QueryCubit<_Data, Null>>().load,
              builder: (d) => _Body(invoice: d.$1, returns: d.$2),
            ),
            bottomNavigationBar: inv == null ? null : _Actions(invoice: inv),
          );
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.invoice, required this.returns});
  final Invoice invoice;
  final List<ReturnDoc> returns;

  @override
  Widget build(BuildContext context) {
    final i = invoice;
    final p = context.palette;
    final isSale = i.type == InvoiceType.sale;
    return MaxWidth(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(i.type.label, style: context.text.labelLarge?.copyWith(color: p.muted))),
                      PaymentStatusPill(i),
                      if (i.hasReturns && !i.fullyReturned) ...[const SizedBox(width: 6), const StatusPill('بها مرتجع', tone: Tone.info)],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(Fmt.money(i.total), style: context.text.headlineMedium),
                  const SizedBox(height: 4),
                  Text('${Fmt.dateTime(i.date)} • ${i.user}', style: context.text.bodySmall),
                  if (i.supplierRef.isNotEmpty) Text('فاتورة المورد: ${i.supplierRef}', style: context.text.bodySmall),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          ListGroup(
            children: [
              ListTile(
                leading: Initials(i.partyName, tone: i.isWalkIn ? Tone.neutral : Tone.primary),
                title: Text(i.partyName),
                subtitle: Text(isSale ? 'العميل' : 'المورد'),
                trailing: i.partyId == null ? null : const Icon(Icons.chevron_left),
                onTap: i.partyId == null ? null : () => context.push(PartyDetailsScreen(partyId: i.partyId!)),
              ),
            ],
          ),
          SectionHeader('الأصناف (${i.lines.length})'),
          ListGroup(
            children: [
              for (final l in i.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l.productName, style: context.text.titleSmall),
                            const SizedBox(height: 2),
                            Text('${Fmt.qty(l.qty)} ${l.unit} × ${Fmt.money(l.unitPrice)}', style: context.text.bodySmall),
                            if (l.discount > 0 || l.returnedQty > 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Wrap(spacing: 6, children: [
                                  if (l.discount > 0) StatusPill('خصم ${Fmt.money(l.discount)}', tone: Tone.success),
                                  if (l.returnedQty > 0) StatusPill('مرتجع ${Fmt.qty(l.returnedQty)}', tone: Tone.info),
                                ]),
                              ),
                          ],
                        ),
                      ),
                      Text(Fmt.money(l.total), style: context.text.titleSmall),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppCard(
              child: Column(
                children: [
                  InfoRow('إجمالي الأصناف', Fmt.money(i.subtotal)),
                  if (i.discount > 0) InfoRow('خصم الفاتورة', '- ${Fmt.money(i.discount)}', valueColor: p.success),
                  InfoRow('الإجمالي', Fmt.money(i.total), bold: true),
                  if (i.hasReturns) InfoRow('المرتجعات', '- ${Fmt.money(i.returnedAmount)}', valueColor: p.info),
                  InfoRow('المدفوع', Fmt.money(i.paid), valueColor: p.success),
                  const Divider(height: 20),
                  InfoRow('المتبقي', Fmt.money(i.due), large: true, valueColor: i.due > 0 ? p.danger : p.success),
                  if (isSale && context.perms.isAdmin) ...[
                    const Divider(height: 20),
                    InfoRow('التكلفة', Fmt.money(i.cost)),
                    InfoRow('الربح', Fmt.money(i.profit), valueColor: i.profit >= 0 ? p.success : p.danger),
                  ],
                ],
              ),
            ),
          ),
          if (i.payments.isNotEmpty) ...[
            const SectionHeader('المدفوعات عند الإصدار'),
            ListGroup(
              children: [
                for (final pay in i.payments)
                  ListTile(
                    leading: Icon(_methodIcon(pay.method)),
                    title: Text(pay.method.label),
                    subtitle: pay.reference.isEmpty ? null : Text('مرجع ${pay.reference}'),
                    trailing: Text(Fmt.money(pay.amount), style: context.text.titleSmall),
                  ),
              ],
            ),
          ],
          if (returns.isNotEmpty) ...[
            const SectionHeader('المرتجعات'),
            ListGroup(
              children: [
                for (final r in returns)
                  ListTile(
                    leading: Icon(Icons.assignment_return_outlined, color: p.info),
                    title: Text(r.number),
                    subtitle: Text('${Fmt.relative(r.date)} • ${r.lines.length} صنف'),
                    trailing: Text(Fmt.money(r.total), style: context.text.titleSmall),
                    onTap: () => showReturnDetails(context, r),
                  ),
              ],
            ),
          ],
          if (i.note.isNotEmpty) ...[
            const SectionHeader('ملاحظات'),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: AppCard(child: Text(i.note))),
          ],
          if (isSale) ...[
            SectionHeader('رأي العميل', actionLabel: i.hasFeedback ? 'تعديل' : 'إضافة', onAction: () => showFeedbackSheet(context, i)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppCard(
                onTap: () => showFeedbackSheet(context, i),
                child: i.hasFeedback
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (i.rating > 0) _Stars(rating: i.rating),
                          if (i.rating > 0 && i.feedback.isNotEmpty) const SizedBox(height: 6),
                          if (i.feedback.isNotEmpty) Text(i.feedback),
                        ],
                      )
                    : Text('اختياري — سجّل تقييم العميل أو ملاحظته على الفاتورة', style: context.text.bodySmall?.copyWith(color: p.muted)),
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({required this.rating, this.size = 22, this.onTap});
  final int rating;
  final double size;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final color = context.palette.warning;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var n = 1; n <= 5; n++)
          InkResponse(
            onTap: onTap == null ? null : () => onTap!(n == rating ? 0 : n),
            radius: size,
            child: Padding(
              padding: EdgeInsets.all(onTap == null ? 0 : 4),
              child: Icon(n <= rating ? Icons.star_rounded : Icons.star_outline_rounded, color: color, size: size),
            ),
          ),
      ],
    );
  }
}

/// Optional customer rating + comment on a sale.
Future<void> showFeedbackSheet(BuildContext context, Invoice invoice) {
  final ctrl = TextEditingController(text: invoice.feedback);
  var rating = invoice.rating;
  return showAppSheet<void>(
    context,
    title: 'رأي العميل',
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('التقييم (اختياري)', style: ctx.text.labelLarge),
            const SizedBox(height: 6),
            Center(child: _Stars(rating: rating, size: 34, onTap: (n) => setState(() => rating = n))),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              maxLines: 3,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'ملاحظة العميل (اختياري)', alignLabelWithHint: true),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () async {
                final saved = await runTask(
                  ctx,
                  () => ctx.read<InvoiceRepository>().setFeedback(invoice.id, rating: rating, feedback: ctrl.text),
                  success: 'تم حفظ رأي العميل',
                );
                if (saved != null && ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    ),
  );
}

IconData _methodIcon(PaymentMethod m) => switch (m) {
      PaymentMethod.cash => Icons.payments_outlined,
      PaymentMethod.card => Icons.credit_card,
      PaymentMethod.bank => Icons.account_balance_outlined,
    };

class _Actions extends StatelessWidget {
  const _Actions({required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final i = invoice;
    final canReturn = !i.fullyReturned;
    final canCollect = i.due > 0.009 && i.partyId != null;
    if (!canReturn && !canCollect) return const SizedBox.shrink();
    final isSale = i.type == InvoiceType.sale;
    return BottomBar(
      child: Row(
        children: [
          if (canReturn)
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.assignment_return_outlined),
                label: Text(isSale ? 'مرتجع بيع' : 'مرتجع شراء'),
                onPressed: () => context.push(ReturnScreen(invoiceId: i.id)),
              ),
            ),
          if (canReturn && canCollect) const SizedBox(width: 10),
          if (canCollect)
            Expanded(
              child: FilledButton.icon(
                icon: const Icon(Icons.payments_outlined),
                label: Text(isSale ? 'تحصيل' : 'سداد'),
                onPressed: () => context.push(PartyPaymentScreen(partyId: i.partyId!, suggestedAmount: i.due)),
              ),
            ),
        ],
      ),
    );
  }
}

void showReturnDetails(BuildContext context, ReturnDoc r) {
  final p = context.palette;
  showAppSheet<void>(
    context,
    title: '${r.type == InvoiceType.sale ? 'مرتجع بيع' : 'مرتجع شراء'} ${r.number}',
    builder: (ctx) => ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text('${Fmt.dateTime(r.date)} • ${r.user}', style: ctx.text.bodySmall),
        Text('من الفاتورة ${r.invoiceNumber} • ${r.partyName}', style: ctx.text.bodySmall),
        if (r.reason.isNotEmpty) Text('السبب: ${r.reason}', style: ctx.text.bodySmall),
        const Divider(height: 24),
        for (final l in r.lines) InfoRow('${l.productName} × ${Fmt.qty(l.qty)}', Fmt.money(l.total)),
        const Divider(height: 24),
        InfoRow('قيمة المرتجع', Fmt.money(r.total), bold: true),
        InfoRow('خُصم من المتبقي على الفاتورة', Fmt.money(r.creditApplied)),
        InfoRow(r.type == InvoiceType.sale ? 'مبلغ مردود للعميل' : 'مبلغ مسترد من المورد', '${Fmt.money(r.cashRefund)}${r.cashRefund > 0 ? ' (${r.refundMethod.label})' : ''}',
            valueColor: r.cashRefund > 0 ? p.warning : null),
      ],
    ),
  );
}
