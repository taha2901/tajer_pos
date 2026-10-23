import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/nav.dart';
import '../../app/theme.dart';
import '../../core/data_bus.dart';
import '../../core/format.dart';
import '../../core/query_cubit.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../common/export.dart';
import '../purchases/purchase_form_screen.dart';
import '../shell/home_shell.dart';
import 'invoice_details_screen.dart';

typedef InvoicesCubit = QueryCubit<List<Invoice>, InvoiceQuery>;

/// Sales history / purchases list with filters, plus a returns tab.
class InvoicesListScreen extends StatelessWidget {
  const InvoicesListScreen({super.key, required this.type, this.embedded = false});
  final InvoiceType type;

  /// Shown as a root tab (no back button) — not used currently but kept for tablets.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final isSale = type == InvoiceType.sale;
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (c) => InvoicesCubit(
            (q) => c.read<InvoiceRepository>().getInvoices(q),
            filter: InvoiceQuery(type, from: Period.month.range!.from, to: Period.month.range!.to),
            bus: c.read<DataBus>(),
            topics: const {DataTopic.invoices},
          ),
        ),
        BlocProvider(
          create: (c) => simpleQuery(() => c.read<InvoiceRepository>().getReturns(type: type), bus: c.read<DataBus>(), topics: const {DataTopic.invoices}),
        ),
      ],
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: Text(isSale ? 'فواتير البيع' : 'المشتريات'),
            actions: [
              Builder(
                builder: (context) => IconButton(
                  tooltip: 'تصدير',
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: () {
                    final list = context.read<InvoicesCubit>().state.data ?? const <Invoice>[];
                    showExportSheet(
                      context,
                      ExportTable(
                        title: isSale ? 'سجل المبيعات' : 'سجل المشتريات',
                        headers: const ['الرقم', 'التاريخ', 'الطرف', 'الإجمالي', 'المدفوع', 'المتبقي'],
                        rows: [
                          for (final i in list)
                            [i.number, Fmt.dateTime(i.date), i.partyName, Fmt.number(i.total), Fmt.number(i.paid), Fmt.number(i.due)],
                        ],
                        summary: [('عدد الفواتير', '${list.length}'), ('الإجمالي', Fmt.money(list.fold(0.0, (s, i) => s + i.total)))],
                      ),
                    );
                  },
                ),
              ),
            ],
            bottom: TabBar(tabs: [Tab(text: isSale ? 'الفواتير' : 'فواتير الشراء'), const Tab(text: 'المرتجعات')]),
          ),
          body: TabBarView(children: [_InvoicesTab(type: type), _ReturnsTab(type: type)]),
          floatingActionButton: FloatingActionButton.extended(
            heroTag: 'inv_fab_$type',
            onPressed: () {
              if (isSale) {
                context.read<ShellCubit>().go(ShellTab.pos);
                Navigator.of(context).popUntil((r) => r.isFirst);
              } else {
                context.push(const PurchaseFormScreen());
              }
            },
            icon: Icon(isSale ? Icons.add_shopping_cart_rounded : Icons.add_rounded),
            label: Text(isSale ? 'مبيعات' : 'فاتورة شراء'),
          ),
        ),
      ),
    );
  }
}

class _InvoicesTab extends StatefulWidget {
  const _InvoicesTab({required this.type});
  final InvoiceType type;

  @override
  State<_InvoicesTab> createState() => _InvoicesTabState();
}

class _InvoicesTabState extends State<_InvoicesTab> with AutomaticKeepAliveClientMixin {
  Period _period = Period.month;
  DateRange? _custom;

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cubit = context.read<InvoicesCubit>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SearchField(
            hint: 'رقم الفاتورة أو اسم ${widget.type.partyType.label}',
            onChanged: (v) => cubit.setFilter(cubit.filter.copyWith(search: v)),
          ),
        ),
        PeriodSelector(
          period: _period,
          customRange: _custom,
          onChanged: (p, r) {
            setState(() {
              _period = p;
              if (p == Period.custom) _custom = r;
            });
            cubit.setFilter(cubit.filter.copyWith(from: () => r?.from, to: () => r?.to));
          },
        ),
        const SizedBox(height: 8),
        BlocBuilder<InvoicesCubit, ViewState<List<Invoice>>>(
          builder: (context, s) => ChipsRow<InvoiceStatusFilter>(
            values: InvoiceStatusFilter.values,
            selected: cubit.filter.status,
            label: (v) => v.label,
            onSelected: (v) => cubit.setFilter(cubit.filter.copyWith(status: v)),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: BlocBuilder<InvoicesCubit, ViewState<List<Invoice>>>(
            builder: (context, state) => AsyncBody<List<Invoice>>(
              state: state,
              onRetry: cubit.load,
              isEmpty: (d) => d.isEmpty,
              empty: EmptyView(
                icon: Icons.receipt_long_outlined,
                title: widget.type == InvoiceType.sale ? 'لا توجد مبيعات في هذه الفترة' : 'لا توجد مشتريات في هذه الفترة',
                message: 'غيّر الفترة أو الفلاتر لعرض فواتير أخرى',
              ),
              builder: (list) => _InvoiceList(invoices: list),
            ),
          ),
        ),
      ],
    );
  }
}

class _InvoiceList extends StatelessWidget {
  const _InvoiceList({required this.invoices});
  final List<Invoice> invoices;

  @override
  Widget build(BuildContext context) {
    final total = invoices.fold(0.0, (s, i) => s + i.total);
    final due = invoices.fold(0.0, (s, i) => s + i.due);
    final items = <Object>[];
    DateTime? day;
    for (final i in invoices) {
      final d = DateTime(i.date.year, i.date.month, i.date.day);
      if (d != day) {
        items.add(d);
        day = d;
      }
      items.add(i);
    }
    return RefreshIndicator(
      onRefresh: () => context.read<InvoicesCubit>().load(),
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: items.length + 1,
        itemBuilder: (context, idx) {
          if (idx == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(
                children: [
                  Expanded(child: _Stat('عدد الفواتير', '${invoices.length}')),
                  Expanded(child: _Stat('الإجمالي', Fmt.money(total))),
                  Expanded(child: _Stat('المتبقي', Fmt.money(due), color: due > 0 ? context.palette.danger : null)),
                ],
              ),
            );
          }
          final item = items[idx - 1];
          if (item is DateTime) {
            final dayTotal = invoices.where((i) => DateUtils.isSameDay(i.date, item)).fold(0.0, (s, i) => s + i.total);
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
              child: Row(
                children: [
                  Expanded(child: Text(Fmt.dayLabel(item), style: context.text.labelLarge?.copyWith(color: context.palette.muted))),
                  Text(Fmt.money(dayTotal), style: context.text.labelMedium?.copyWith(color: context.palette.muted)),
                ],
              ),
            );
          }
          final inv = item as Invoice;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            child: InvoiceTile(invoice: inv),
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.labelSmall?.copyWith(color: context.palette.muted)),
          FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: context.text.titleSmall?.copyWith(color: color))),
        ],
      );
}

class InvoiceTile extends StatelessWidget {
  const InvoiceTile({super.key, required this.invoice, this.showDate = false});
  final Invoice invoice;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final i = invoice;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => context.push(InvoiceDetailsScreen(invoiceId: i.id)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(i.number, style: context.text.titleSmall),
                    const SizedBox(width: 8),
                    PaymentStatusPill(i),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${i.partyName} • ${showDate ? Fmt.relative(i.date) : Fmt.time(i.date)} • ${i.lines.length} صنف',
                  style: context.text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Fmt.money(i.total), style: context.text.titleSmall),
              if (i.due > 0) Text('متبقي ${Fmt.money(i.due)}', style: context.text.labelSmall?.copyWith(color: context.palette.danger)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReturnsTab extends StatelessWidget {
  const _ReturnsTab({required this.type});
  final InvoiceType type;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<QueryCubit<List<ReturnDoc>, Null>, ViewState<List<ReturnDoc>>>(
      builder: (context, state) => AsyncBody<List<ReturnDoc>>(
        state: state,
        onRetry: context.read<QueryCubit<List<ReturnDoc>, Null>>().load,
        isEmpty: (d) => d.isEmpty,
        empty: const EmptyView(
          icon: Icons.assignment_return_outlined,
          title: 'لا توجد مرتجعات',
          message: 'لعمل مرتجع افتح الفاتورة واضغط "مرتجع"',
        ),
        builder: (list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 6),
          itemBuilder: (context, i) {
            final r = list[i];
            return AppCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              onTap: () => showReturnDetails(context, r),
              child: Row(
                children: [
                  Icon(Icons.assignment_return_outlined, color: context.palette.info),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${r.number} • من ${r.invoiceNumber}', style: context.text.titleSmall),
                        Text('${r.partyName} • ${Fmt.relative(r.date)}', style: context.text.bodySmall),
                      ],
                    ),
                  ),
                  Text(Fmt.money(r.total), style: context.text.titleSmall),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
