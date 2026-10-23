import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../app/session_cubit.dart';
import '../../app/theme.dart';
import '../../core/data_bus.dart';
import '../../core/format.dart';
import '../../core/query_cubit.dart';
import '../../core/widgets/charts.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../common/export.dart';
import '../common/pickers.dart';

typedef _Cubit = QueryCubit<TradeReport, TradeReportFilter>;

/// Sales report or purchases report, with grouping and filters.
class TradeReportScreen extends StatefulWidget {
  const TradeReportScreen({super.key, required this.type, this.initialGroup = 0});
  final InvoiceType type;

  /// Index into the grouping options.
  final int initialGroup;

  @override
  State<TradeReportScreen> createState() => _TradeReportScreenState();
}

class _TradeReportScreenState extends State<TradeReportScreen> {
  Period _period = Period.month;
  DateRange? _custom;
  late int _group = widget.initialGroup;
  String? _partyName;
  String? _productName;
  String? _categoryName;

  bool get _isSale => widget.type == InvoiceType.sale;

  List<String> get _groups =>
      _isSale ? SalesGroupBy.values.map((g) => g.label).toList() : PurchasesGroupBy.values.map((g) => g.label).toList();

  List<NamedValue> _rows(TradeReport r) {
    if (_isSale) {
      return switch (SalesGroupBy.values[_group]) {
        SalesGroupBy.day => r.byDay,
        SalesGroupBy.week => r.byWeek,
        SalesGroupBy.month => r.byMonth,
        SalesGroupBy.customer => r.byParty,
        SalesGroupBy.product => r.byProduct,
        SalesGroupBy.category => r.byCategory,
        SalesGroupBy.paymentMethod => r.byPaymentMethod,
      };
    }
    return switch (PurchasesGroupBy.values[_group]) {
      PurchasesGroupBy.day => r.byDay,
      PurchasesGroupBy.month => r.byMonth,
      PurchasesGroupBy.supplier => r.byParty,
      PurchasesGroupBy.product => r.byProduct,
    };
  }

  bool get _isTime => _isSale ? SalesGroupBy.values[_group].isTime : PurchasesGroupBy.values[_group].isTime;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => _Cubit(
        (f) => c.read<ReportRepository>().getTradeReport(widget.type, f),
        filter: TradeReportFilter(range: Period.month.range!),
        bus: c.read<DataBus>(),
        topics: const {DataTopic.invoices},
      ),
      child: BlocBuilder<_Cubit, ViewState<TradeReport>>(
        builder: (context, state) {
          final cubit = context.read<_Cubit>();
          return Scaffold(
            appBar: AppBar(
              title: Text(_isSale ? 'تقرير المبيعات' : 'تقرير المشتريات'),
              actions: [
                if (state.data != null) ...[
                  IconButton(tooltip: 'طباعة', icon: const Icon(Icons.print_outlined), onPressed: () => showPrintPreview(context, _table(state.data!, cubit.filter))),
                  IconButton(tooltip: 'تصدير', icon: const Icon(Icons.ios_share_rounded), onPressed: () => showExportSheet(context, _table(state.data!, cubit.filter))),
                ],
              ],
            ),
            body: Column(
              children: [
                const SizedBox(height: 8),
                PeriodSelector(
                  period: _period,
                  customRange: _custom,
                  allowAll: false,
                  onChanged: (p, r) {
                    setState(() {
                      _period = p;
                      if (p == Period.custom) _custom = r;
                    });
                    if (r != null) cubit.setFilter(cubit.filter.copyWith(range: r));
                  },
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _FilterChip(
                        icon: Icons.person_outline,
                        label: _partyName ?? (_isSale ? 'كل العملاء' : 'كل الموردين'),
                        active: _partyName != null,
                        onTap: () async {
                          final p = await pickParty(context, widget.type.partyType);
                          if (p == null) return;
                          setState(() => _partyName = p.name);
                          cubit.setFilter(cubit.filter.copyWith(partyId: () => p.id));
                        },
                        onClear: () {
                          setState(() => _partyName = null);
                          cubit.setFilter(cubit.filter.copyWith(partyId: () => null));
                        },
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        icon: Icons.inventory_2_outlined,
                        label: _productName ?? 'كل المنتجات',
                        active: _productName != null,
                        onTap: () async {
                          final p = await pickProduct(context);
                          if (p == null) return;
                          setState(() => _productName = p.name);
                          cubit.setFilter(cubit.filter.copyWith(productId: () => p.id));
                        },
                        onClear: () {
                          setState(() => _productName = null);
                          cubit.setFilter(cubit.filter.copyWith(productId: () => null));
                        },
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        icon: Icons.category_outlined,
                        label: _categoryName ?? 'كل الفئات',
                        active: _categoryName != null,
                        onTap: () async {
                          final cats = await context.read<ProductRepository>().getCategories();
                          if (!context.mounted) return;
                          final c = await showAppSheet<Category>(
                            context,
                            title: 'اختر الفئة',
                            builder: (ctx) => ListView(
                              shrinkWrap: true,
                              children: [for (final c in cats) ListTile(title: Text(c.name), onTap: () => Navigator.pop(ctx, c))],
                            ),
                          );
                          if (c == null) return;
                          setState(() => _categoryName = c.name);
                          cubit.setFilter(cubit.filter.copyWith(categoryId: () => c.id));
                        },
                        onClear: () {
                          setState(() => _categoryName = null);
                          cubit.setFilter(cubit.filter.copyWith(categoryId: () => null));
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: AsyncBody<TradeReport>(
                    state: state,
                    onRetry: cubit.load,
                    builder: (r) => _body(context, r),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, TradeReport r) {
    final isAdmin = context.perms.isAdmin;
    final rows = _rows(r);
    final nonEmpty = rows.where((e) => e.value != 0).toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SizedBox(height: 8),
        TileGrid(
          children: [
            KpiTile(label: 'عدد الفواتير', value: '${r.invoicesCount}', icon: Icons.receipt_long_outlined, tone: Tone.neutral),
            KpiTile(label: _isSale ? 'إجمالي المبيعات' : 'إجمالي المشتريات', value: Fmt.money(r.gross), icon: Icons.payments_outlined),
            KpiTile(label: 'الصافي', value: Fmt.money(r.net), icon: Icons.functions_rounded, tone: Tone.info),
            if (_isSale && isAdmin) KpiTile(label: 'مجمل الربح', value: Fmt.money(r.profit), icon: Icons.savings_outlined, tone: Tone.success, caption: r.net == 0 ? null : 'هامش ${Fmt.percent(r.profit / r.net * 100)}'),
            KpiTile(label: 'المتبقي (آجل)', value: Fmt.money(r.due), icon: Icons.schedule_rounded, tone: Tone.danger, caption: 'خصومات ${Fmt.money(r.discounts)}'),
          ],
        ),
        const SizedBox(height: 14),
        ChipsRow<int>(
          values: List.generate(_groups.length, (i) => i),
          selected: _group,
          label: (i) => _groups[i],
          onSelected: (i) => setState(() => _group = i),
        ),
        const SizedBox(height: 12),
        if (nonEmpty.isEmpty)
          EmptyView(icon: Icons.insert_chart_outlined, title: _isSale ? 'لا توجد مبيعات في هذه الفترة' : 'لا توجد مشتريات في هذه الفترة', compact: true)
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_groups[_group], style: context.text.titleSmall),
                  const SizedBox(height: 12),
                  if (_isTime)
                    SimpleBarChart(
                      labels: [for (final e in rows) e.name],
                      values: [for (final e in rows) e.value],
                      valueLabel: _isSale ? 'المبيعات' : 'المشتريات',
                      color: _isSale ? null : context.palette.info,
                    )
                  else
                    RankedBars(
                      color: _isSale ? null : context.palette.info,
                      items: [
                        for (final e in nonEmpty.take(8))
                          (e.name, e.value, '${Fmt.qty(e.count)} ${_group == (_isSale ? 4 : 3) ? 'وحدة' : 'فاتورة'}'),
                      ],
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _Table(rows: _isTime ? rows.reversed.where((e) => e.value != 0).toList() : nonEmpty, showProfit: _isSale && isAdmin && _group != 6, countLabel: _group == (_isSale ? 4 : 3) || (_isSale && _group == 5) ? 'الكمية' : 'العدد'),
        ],
      ],
    );
  }

  ExportTable _table(TradeReport r, TradeReportFilter f) {
    final rows = _rows(r).where((e) => e.value != 0);
    return ExportTable(
      title: '${_isSale ? 'تقرير المبيعات' : 'تقرير المشتريات'} — ${_groups[_group]}',
      headers: ['البند', 'العدد/الكمية', 'القيمة', if (_isSale) 'الربح'],
      rows: [for (final e in rows) [e.name, Fmt.qty(e.count), Fmt.number(e.value), if (_isSale) Fmt.number(e.extra)]],
      summary: [
        ('الفترة', '${Fmt.date(f.range.from)} - ${Fmt.date(f.range.to)}'),
        ('عدد الفواتير', '${r.invoicesCount}'),
        ('الإجمالي', Fmt.money(r.gross)),
        ('المرتجعات', Fmt.money(r.returns)),
        ('الصافي', Fmt.money(r.net)),
        if (_isSale) ('مجمل الربح', Fmt.money(r.profit)),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.icon, required this.label, required this.active, required this.onTap, required this.onClear});
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      selected: active,
      onPressed: onTap,
      onDeleted: active ? onClear : null,
      showCheckmark: false,
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.rows, required this.showProfit, required this.countLabel});
  final List<NamedValue> rows;
  final bool showProfit;
  final String countLabel;

  @override
  Widget build(BuildContext context) {
    final pal = context.palette;
    final head = context.text.labelMedium?.copyWith(color: pal.muted);
    return ListGroup(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Expanded(flex: 5, child: Text('البند', style: head)),
              Expanded(flex: 2, child: Text(countLabel, style: head, textAlign: TextAlign.end)),
              Expanded(flex: 3, child: Text('القيمة', style: head, textAlign: TextAlign.end)),
              if (showProfit) Expanded(flex: 3, child: Text('الربح', style: head, textAlign: TextAlign.end)),
            ],
          ),
        ),
        for (final e in rows)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Expanded(flex: 5, child: Text(e.name, style: context.text.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis)),
                Expanded(flex: 2, child: Text(Fmt.qty(e.count), textAlign: TextAlign.end)),
                Expanded(flex: 3, child: Text(Fmt.number(e.value), style: context.text.titleSmall, textAlign: TextAlign.end)),
                if (showProfit)
                  Expanded(flex: 3, child: Text(Fmt.number(e.extra), style: TextStyle(color: e.extra >= 0 ? pal.success : pal.danger), textAlign: TextAlign.end)),
              ],
            ),
          ),
      ],
    );
  }
}
