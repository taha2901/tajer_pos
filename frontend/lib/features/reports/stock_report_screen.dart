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
import '../common/product_widgets.dart';
import '../products/product_details_screen.dart';

typedef _Cubit = QueryCubit<StockReport, DateRange>;

class StockReportScreen extends StatefulWidget {
  const StockReportScreen({super.key});

  @override
  State<StockReportScreen> createState() => _StockReportScreenState();
}

class _StockReportScreenState extends State<StockReportScreen> {
  StockReportView _view = StockReportView.current;
  Period _period = Period.week;
  DateRange? _custom;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => _Cubit(
        (r) => c.read<ReportRepository>().getStockReport(movementRange: r),
        filter: Period.week.range!,
        bus: c.read<DataBus>(),
        topics: const {DataTopic.products},
      ),
      child: BlocBuilder<_Cubit, ViewState<StockReport>>(
        builder: (context, state) {
          final cubit = context.read<_Cubit>();
          return Scaffold(
            appBar: AppBar(
              title: const Text('تقرير المخزون'),
              actions: [
                if (state.data != null)
                  IconButton(tooltip: 'تصدير', icon: const Icon(Icons.ios_share_rounded), onPressed: () => showExportSheet(context, _table(state.data!))),
              ],
            ),
            body: Column(
              children: [
                const SizedBox(height: 8),
                ChipsRow<StockReportView>(
                  values: StockReportView.values,
                  selected: _view,
                  label: (v) => v.label,
                  count: (v) => switch (v) {
                    StockReportView.low => state.data?.low.length,
                    StockReportView.out => state.data?.out.length,
                    _ => null,
                  },
                  onSelected: (v) => setState(() => _view = v),
                ),
                if (_view == StockReportView.movement) ...[
                  const SizedBox(height: 6),
                  PeriodSelector(
                    period: _period,
                    customRange: _custom,
                    allowAll: false,
                    onChanged: (p, r) {
                      setState(() {
                        _period = p;
                        if (p == Period.custom) _custom = r;
                      });
                      if (r != null) cubit.setFilter(r);
                    },
                  ),
                ],
                const SizedBox(height: 8),
                Expanded(
                  child: AsyncBody<StockReport>(state: state, onRetry: cubit.load, builder: _body),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _body(StockReport r) {
    final isAdmin = context.perms.isAdmin;
    if (_view == StockReportView.movement) {
      final ins = r.movements.where((m) => m.qty > 0).fold(0.0, (s, m) => s + m.qty);
      final outs = r.movements.where((m) => m.qty < 0).fold(0.0, (s, m) => s - m.qty);
      return ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: KpiTile(label: 'حركات', value: '${r.movements.length}', icon: Icons.swap_vert_rounded, tone: Tone.neutral)),
                const SizedBox(width: 8),
                Expanded(child: KpiTile(label: 'وارد', value: Fmt.qty(ins), icon: Icons.south_west_rounded, tone: Tone.success)),
                const SizedBox(width: 8),
                Expanded(child: KpiTile(label: 'منصرف', value: Fmt.qty(outs), icon: Icons.north_east_rounded, tone: Tone.danger)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (r.movements.isEmpty)
            const EmptyView(icon: Icons.history, title: 'لا توجد حركات في هذه الفترة', compact: true)
          else
            ListGroup(
              children: [
                for (final m in r.movements.take(150))
                  ListTile(
                    title: Text(r.productNames[m.productId] ?? '-'),
                    subtitle: Text('${m.type.label} • ${m.refNumber ?? ''} • ${Fmt.relative(m.date)}'),
                    trailing: Text(
                      '${m.qty > 0 ? '+' : ''}${Fmt.qty(m.qty)}',
                      style: context.text.titleSmall?.copyWith(color: m.qty > 0 ? context.palette.success : context.palette.danger),
                    ),
                    onTap: () => context.push(ProductDetailsScreen(productId: m.productId)),
                  ),
              ],
            ),
        ],
      );
    }

    final list = switch (_view) {
      StockReportView.low => r.low,
      StockReportView.out => r.out,
      _ => r.products,
    };
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        TileGrid(
          children: [
            KpiTile(label: 'عدد الأصناف', value: '${r.products.length}', icon: Icons.inventory_2_outlined, tone: Tone.neutral),
            if (isAdmin) KpiTile(label: 'قيمة المخزون (تكلفة)', value: Fmt.money(r.costValue), icon: Icons.account_balance_wallet_outlined),
            KpiTile(label: 'قيمة المخزون (بيع)', value: Fmt.money(r.retailValue), icon: Icons.sell_outlined, tone: Tone.info),
            KpiTile(label: 'منخفض / نفد', value: '${r.low.length} / ${r.out.length}', icon: Icons.warning_amber_rounded, tone: Tone.warning),
          ],
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          EmptyView(
            icon: Icons.check_circle_outline,
            title: _view == StockReportView.out ? 'لا توجد أصناف نافدة' : 'لا توجد أصناف منخفضة',
            compact: true,
          )
        else
          ListGroup(
            children: [
              for (final p in list)
                ListTile(
                  leading: ProductThumb(p, size: 38),
                  title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${r.categoryNames[p.categoryId] ?? ''} • الحد ${Fmt.qty(p.minStock)}${isAdmin ? ' • القيمة ${Fmt.money(p.stockValue)}' : ''}'),
                  trailing: StockPill(p),
                  onTap: () => context.push(ProductDetailsScreen(productId: p.id)),
                ),
            ],
          ),
      ],
    );
  }

  ExportTable _table(StockReport r) {
    if (_view == StockReportView.movement) {
      return ExportTable(
        title: 'حركة المخزون',
        headers: const ['التاريخ', 'المنتج', 'النوع', 'المرجع', 'الكمية', 'الرصيد'],
        rows: [
          for (final m in r.movements)
            [Fmt.dateTime(m.date), r.productNames[m.productId] ?? '', m.type.label, m.refNumber ?? '', Fmt.qty(m.qty), Fmt.qty(m.stockAfter)],
        ],
      );
    }
    final list = switch (_view) { StockReportView.low => r.low, StockReportView.out => r.out, _ => r.products };
    return ExportTable(
      title: 'تقرير المخزون — ${_view.label}',
      headers: const ['المنتج', 'SKU', 'الفئة', 'الرصيد', 'الحد الأدنى', 'التكلفة', 'القيمة'],
      rows: [
        for (final p in list)
          [p.name, p.sku, r.categoryNames[p.categoryId] ?? '', Fmt.qty(p.stock), Fmt.qty(p.minStock), Fmt.number(p.purchasePrice), Fmt.number(p.stockValue)],
      ],
      summary: [('قيمة المخزون بالتكلفة', Fmt.money(r.costValue)), ('قيمة المخزون بسعر البيع', Fmt.money(r.retailValue))],
    );
  }
}
