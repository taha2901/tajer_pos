import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/data_bus.dart';
import '../../core/format.dart';
import '../../core/query_cubit.dart';
import '../../core/widgets/widgets.dart';
import '../../domain/models/models.dart';
import '../../domain/repositories/repositories.dart';
import '../common/export.dart';
import 'product_details_screen.dart';

typedef _Cubit = QueryCubit<List<StockMovement>, StockMoveType?>;

/// Every stock movement of a product: purchases, sales, returns, adjustments.
class StockHistoryScreen extends StatelessWidget {
  const StockHistoryScreen({super.key, required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => _Cubit(
        (type) => c.read<ProductRepository>().getStockMovements(product.id, type: type),
        filter: null,
        bus: c.read<DataBus>(),
        topics: const {DataTopic.products},
      ),
      child: BlocBuilder<_Cubit, ViewState<List<StockMovement>>>(
        builder: (context, state) {
          final cubit = context.read<_Cubit>();
          final list = state.data ?? const <StockMovement>[];
          final inQty = list.where((m) => m.qty > 0).fold(0.0, (s, m) => s + m.qty);
          final outQty = list.where((m) => m.qty < 0).fold(0.0, (s, m) => s - m.qty);
          return Scaffold(
            appBar: AppBar(
              title: Text('سجل مخزون ${product.name}', overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  tooltip: 'تصدير',
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: () => showExportSheet(
                    context,
                    ExportTable(
                      title: 'حركة مخزون ${product.name}',
                      headers: const ['التاريخ', 'النوع', 'المرجع', 'الكمية', 'الرصيد', 'المستخدم'],
                      rows: [
                        for (final m in list) [Fmt.dateTime(m.date), m.type.label, m.refNumber ?? '', Fmt.qty(m.qty), Fmt.qty(m.stockAfter), m.user],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            body: Column(
              children: [
                const SizedBox(height: 8),
                ChipsRow<StockMoveType?>(
                  values: const [null, StockMoveType.purchase, StockMoveType.sale, StockMoveType.saleReturn, StockMoveType.purchaseReturn, StockMoveType.adjustment],
                  selected: cubit.filter,
                  label: (t) => t?.label ?? 'الكل',
                  onSelected: cubit.setFilter,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: Row(
                    children: [
                      Expanded(child: KpiTile(label: 'وارد', value: Fmt.qty(inQty), icon: Icons.south_west_rounded, tone: Tone.success)),
                      const SizedBox(width: 8),
                      Expanded(child: KpiTile(label: 'منصرف', value: Fmt.qty(outQty), icon: Icons.north_east_rounded, tone: Tone.danger)),
                      const SizedBox(width: 8),
                      Expanded(child: KpiTile(label: 'الرصيد الحالي', value: Fmt.qty(product.stock), icon: Icons.inventory_2_outlined)),
                    ],
                  ),
                ),
                Expanded(
                  child: AsyncBody<List<StockMovement>>(
                    state: state,
                    onRetry: cubit.load,
                    isEmpty: (d) => d.isEmpty,
                    empty: const EmptyView(icon: Icons.history, title: 'لا توجد حركات', message: 'لا توجد حركات من هذا النوع'),
                    builder: (list) => ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(indent: 16, endIndent: 16),
                      itemBuilder: (_, i) => StockMoveTile(move: list[i], unit: product.unit),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
