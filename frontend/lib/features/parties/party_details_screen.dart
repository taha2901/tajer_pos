import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../invoices/invoice_details_screen.dart';
import '../invoices/invoices_list_screen.dart';
import '../pos/cart_cubit.dart';
import '../purchases/purchase_form_screen.dart';
import '../shell/home_shell.dart';
import 'party_form_screen.dart';
import 'party_payment_screen.dart';
import 'statement_screen.dart';

class PartyDetailsData {
  const PartyDetailsData(this.party, this.stats, this.invoices, this.payments, this.returns);
  final Party party;
  final PartyStats stats;
  final List<Invoice> invoices;
  final List<PartyPayment> payments;
  final List<ReturnDoc> returns;
}

typedef _Cubit = QueryCubit<PartyDetailsData, Null>;

class PartyDetailsScreen extends StatelessWidget {
  const PartyDetailsScreen({super.key, required this.partyId});
  final String partyId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => simpleQuery<PartyDetailsData>(
        () async {
          final parties = c.read<PartyRepository>();
          final invoices = c.read<InvoiceRepository>();
          final party = await parties.getParty(partyId);
          final type = party.isCustomer ? InvoiceType.sale : InvoiceType.purchase;
          final r = await Future.wait([
            parties.getStats(partyId),
            invoices.getInvoices(InvoiceQuery(type, partyId: partyId)),
            parties.getPayments(partyId: partyId),
            invoices.getReturns(partyId: partyId),
          ]);
          return PartyDetailsData(party, r[0] as PartyStats, r[1] as List<Invoice>, r[2] as List<PartyPayment>, r[3] as List<ReturnDoc>);
        },
        bus: c.read<DataBus>(),
        topics: const {DataTopic.parties, DataTopic.invoices},
      ),
      child: BlocBuilder<_Cubit, ViewState<PartyDetailsData>>(
        builder: (context, state) {
          final party = state.data?.party;
          return Scaffold(
            appBar: AppBar(
              title: Text(party?.name ?? ''),
              actions: [if (party != null) _Menu(party: party)],
            ),
            body: AsyncBody<PartyDetailsData>(
              state: state,
              onRetry: context.read<_Cubit>().load,
              builder: (d) => _Body(data: d),
            ),
          );
        },
      ),
    );
  }
}

class _Menu extends StatelessWidget {
  const _Menu({required this.party});
  final Party party;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: (v) async {
        switch (v) {
          case 'edit':
            context.push(PartyFormScreen(type: party.type, party: party));
          case 'adjust':
            _adjust(context);
          case 'delete':
            final ok = await confirmDialog(
              context,
              title: 'حذف ${party.name}؟',
              message: 'سيتم حذف ${party.type.label} نهائياً. لا يمكن حذف طرف له فواتير أو رصيد مفتوح.',
              confirmLabel: 'حذف',
              destructive: true,
              icon: Icons.delete_outline,
            );
            if (!ok || !context.mounted) return;
            final done = await runTask(context, () async {
              await context.read<PartyRepository>().delete(party.id);
              return true;
            }, success: 'تم الحذف');
            if (done == true && context.mounted) Navigator.pop(context);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('تعديل البيانات'))),
        if (context.perms.isAdmin)
          const PopupMenuItem(value: 'adjust', child: ListTile(leading: Icon(Icons.tune_rounded), title: Text('تسوية الرصيد'))),
        if (context.perms.canDelete)
          const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('حذف'))),
      ],
    );
  }

  Future<void> _adjust(BuildContext context) async {
    var increase = true;
    final amount = TextEditingController();
    final note = TextEditingController();
    final form = GlobalKey<FormState>();
    await showAppSheet<void>(
      context,
      title: 'تسوية رصيد ${party.name}',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('الرصيد الحالي ${Fmt.money(party.balance)}', style: ctx.text.bodySmall),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: [
                      ButtonSegment(value: true, label: Text(party.isCustomer ? 'زيادة المديونية' : 'زيادة المستحق'), icon: const Icon(Icons.add)),
                      ButtonSegment(value: false, label: Text(party.isCustomer ? 'تخفيض المديونية' : 'تخفيض المستحق'), icon: const Icon(Icons.remove)),
                    ],
                    selected: {increase},
                    onSelectionChanged: (v) => set(() => increase = v.first),
                  ),
                  const SizedBox(height: 12),
                  MoneyField(controller: amount, label: 'المبلغ', autofocus: true, validator: (v) => requiredNumber(v, allowZero: false)),
                  const SizedBox(height: 12),
                  TextFormField(controller: note, decoration: const InputDecoration(labelText: 'سبب التسوية *'), validator: requiredText),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      if (!form.currentState!.validate()) return;
                      final a = parseNum(amount.text)!;
                      final r = await runTask(
                        ctx,
                        () => context.read<PartyRepository>().adjustBalance(party.id, amount: increase ? a : -a, note: note.text.trim()),
                        success: 'تم تسجيل التسوية',
                      );
                      if (r != null && ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('تسجيل التسوية'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.data});
  final PartyDetailsData data;

  @override
  Widget build(BuildContext context) {
    final p = data.party;
    final pal = context.palette;
    final isCustomer = p.isCustomer;
    return DefaultTabController(
      length: 3,
      child: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverToBoxAdapter(
            child: MaxWidth(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Initials(p.name, size: 52),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.name, style: context.text.titleLarge),
                              const SizedBox(height: 4),
                              Wrap(spacing: 6, runSpacing: 4, children: [
                                StatusPill(isCustomer ? 'عميل' : (p.company.isEmpty ? 'مورد' : p.company), tone: Tone.primary),
                                if (p.overLimit) const StatusPill('تجاوز حد الائتمان', tone: Tone.danger),
                              ]),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (p.phone.isNotEmpty || p.address.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      if (p.phone.isNotEmpty)
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: p.phone));
                            showToast(context, 'تم نسخ الرقم', kind: ToastKind.info);
                          },
                          child: InfoRow('الهاتف', p.phone, icon: Icons.phone_outlined),
                        ),
                      if (p.address.isNotEmpty) InfoRow('العنوان', p.address, icon: Icons.location_on_outlined),
                    ],
                    const SizedBox(height: 14),
                    _BalanceCard(party: p),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.payments_outlined, size: 20),
                            label: Text(isCustomer ? 'تحصيل دفعة' : 'سداد دفعة'),
                            onPressed: () => context.push(PartyPaymentScreen(partyId: p.id)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.summarize_outlined, size: 20),
                            label: const Text('كشف حساب'),
                            onPressed: () => context.push(StatementScreen(partyId: p.id)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          tooltip: isCustomer ? 'بيع جديد' : 'شراء جديد',
                          style: IconButton.styleFrom(minimumSize: const Size(50, 50), side: BorderSide(color: pal.border)),
                          onPressed: () {
                            if (isCustomer) {
                              context.read<CartCubit>().setCustomer(p);
                              context.read<ShellCubit>().go(ShellTab.pos);
                              Navigator.of(context).popUntil((r) => r.isFirst);
                            } else {
                              context.push(PurchaseFormScreen(supplier: p));
                            }
                          },
                          icon: Icon(isCustomer ? Icons.add_shopping_cart_rounded : Icons.add_box_outlined),
                        ),
                      ],
                    ),
                    if (p.notes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: pal.subtle, borderRadius: BorderRadius.circular(12)),
                        child: Text(p.notes, style: context.text.bodySmall),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabsHeader(
              TabBar(tabs: [
                Tab(text: 'الفواتير (${data.invoices.length})'),
                Tab(text: 'الدفعات (${data.payments.length})'),
                Tab(text: 'المرتجعات (${data.returns.length})'),
              ]),
              context.theme.scaffoldBackgroundColor,
            ),
          ),
        ],
        body: TabBarView(
          children: [
            data.invoices.isEmpty
                ? const EmptyView(icon: Icons.receipt_long_outlined, title: 'لا توجد فواتير', compact: true)
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: data.invoices.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => InvoiceTile(invoice: data.invoices[i], showDate: true),
                  ),
            data.payments.isEmpty
                ? const EmptyView(icon: Icons.payments_outlined, title: 'لا توجد دفعات', compact: true)
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: data.payments.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => PaymentTile(payment: data.payments[i]),
                  ),
            data.returns.isEmpty
                ? const EmptyView(icon: Icons.assignment_return_outlined, title: 'لا توجد مرتجعات', compact: true)
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: data.returns.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, i) {
                      final r = data.returns[i];
                      return AppCard(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        onTap: () => showReturnDetails(context, r),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${r.number} • من ${r.invoiceNumber}', style: context.text.titleSmall),
                                  Text(Fmt.relative(r.date), style: context.text.bodySmall),
                                ],
                              ),
                            ),
                            Text(Fmt.money(r.total), style: context.text.titleSmall),
                          ],
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}

class _TabsHeader extends SliverPersistentHeaderDelegate {
  _TabsHeader(this.tabBar, this.color);
  final TabBar tabBar;
  final Color color;

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(color: color, child: tabBar);

  @override
  bool shouldRebuild(_TabsHeader old) => old.tabBar != tabBar;
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.party});
  final Party party;

  @override
  Widget build(BuildContext context) {
    final p = party;
    final pal = context.palette;
    final label = p.isCustomer ? (p.balance < 0 ? 'رصيد دائن للعميل' : 'المديونية الحالية') : (p.balance < 0 ? 'رصيد لنا عند المورد' : 'المستحق للمورد');
    final color = p.hasDebt ? pal.danger : pal.success;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.labelLarge?.copyWith(color: pal.muted)),
          const SizedBox(height: 4),
          Text(Fmt.money(p.balance.abs()), style: context.text.headlineMedium?.copyWith(color: color)),
          if (p.creditLimit > 0) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (p.balance / p.creditLimit).clamp(0, 1).toDouble(),
                minHeight: 6,
                color: p.overLimit ? pal.danger : p.balance / p.creditLimit > 0.8 ? pal.warning : pal.success,
                backgroundColor: pal.subtle,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'حد الائتمان ${Fmt.money(p.creditLimit)} • المتاح ${Fmt.money((p.creditLimit - p.balance).clamp(0, double.infinity))}',
              style: context.text.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}


class PaymentTile extends StatelessWidget {
  const PaymentTile({super.key, required this.payment, this.showParty = false});
  final PartyPayment payment;
  final bool showParty;

  @override
  Widget build(BuildContext context) {
    final p = payment;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: context.palette.successBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(Icons.payments_outlined, color: context.palette.success, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${p.number} • ${p.method.label}${showParty ? ' • ${p.partyName}' : ''}', style: context.text.titleSmall),
                Text(
                  '${Fmt.relative(p.date)} • ${p.user}${p.note.isEmpty ? '' : ' • ${p.note}'}',
                  style: context.text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text('الرصيد: ${Fmt.money(p.balanceBefore)} ← ${Fmt.money(p.balanceAfter)}', style: context.text.labelSmall?.copyWith(color: context.palette.muted)),
              ],
            ),
          ),
          Text(Fmt.money(p.amount), style: context.text.titleSmall?.copyWith(color: context.palette.success)),
        ],
      ),
    );
  }
}
