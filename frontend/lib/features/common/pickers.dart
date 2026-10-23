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
import '../parties/party_form_screen.dart';
import 'product_widgets.dart';
import 'scanner.dart';

/// Bottom sheet to choose a customer / supplier, with search and quick add.
Future<Party?> pickParty(BuildContext context, PartyType type, {bool allowWalkIn = false}) {
  return showAppSheet<Party?>(
    context,
    expand: true,
    builder: (ctx) => BlocProvider(
      create: (c) => QueryCubit<List<Party>, PartyQuery>(
        (q) => c.read<PartyRepository>().getParties(q),
        filter: PartyQuery(type),
        bus: c.read<DataBus>(),
        topics: const {DataTopic.parties},
      ),
      child: _PartyPicker(type: type, allowWalkIn: allowWalkIn),
    ),
  );
}

/// Sentinel returned when "walk-in customer" is chosen.
final walkInCustomer = Party(id: '_walkin', type: PartyType.customer, name: 'عميل نقدي', createdAt: DateTime(2000));

class _PartyPicker extends StatelessWidget {
  const _PartyPicker({required this.type, required this.allowWalkIn});
  final PartyType type;
  final bool allowWalkIn;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<QueryCubit<List<Party>, PartyQuery>>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              Expanded(child: Text('اختر ${type.label}', style: context.text.titleLarge)),
              TextButton.icon(
                onPressed: () async {
                  final created = await context.push<Party>(PartyFormScreen(type: type));
                  if (created != null && context.mounted) Navigator.pop(context, created);
                },
                icon: const Icon(Icons.person_add_alt_1_outlined),
                label: Text('${type.label} جديد'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SearchField(
            hint: 'ابحث بالاسم أو الهاتف',
            onChanged: (v) => cubit.setFilter(cubit.filter.copyWith(search: v)),
          ),
        ),
        if (allowWalkIn)
          ListTile(
            leading: const Initials('عميل نقدي', tone: Tone.neutral),
            title: const Text('عميل نقدي (بدون حساب)'),
            subtitle: const Text('بيع نقدي فقط — لا يسمح بالآجل'),
            onTap: () => Navigator.pop(context, walkInCustomer),
          ),
        const Divider(),
        Expanded(
          child: BlocBuilder<QueryCubit<List<Party>, PartyQuery>, ViewState<List<Party>>>(
            builder: (context, state) => AsyncBody<List<Party>>(
              state: state,
              onRetry: cubit.load,
              isEmpty: (d) => d.isEmpty,
              empty: EmptyView(icon: Icons.people_outline, title: 'لا يوجد ${type.plural}', compact: true),
              builder: (list) => ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final p = list[i];
                  return ListTile(
                    leading: Initials(p.name),
                    title: Text(p.name),
                    subtitle: Text(p.phone.isEmpty ? p.type.label : p.phone),
                    trailing: p.hasDebt
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(Fmt.money(p.balance), style: context.text.labelLarge?.copyWith(color: context.palette.danger)),
                              if (p.overLimit) const StatusPill('تجاوز الحد', tone: Tone.danger),
                            ],
                          )
                        : null,
                    onTap: () => Navigator.pop(context, p),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Bottom sheet to choose a product (search / scan). Used by purchases.
Future<Product?> pickProduct(BuildContext context, {bool showCost = false}) {
  return showAppSheet<Product?>(
    context,
    expand: true,
    builder: (ctx) => BlocProvider(
      create: (c) => QueryCubit<List<Product>, ProductQuery>(
        (q) => c.read<ProductRepository>().getProducts(q),
        filter: const ProductQuery(includeInactive: false),
        bus: c.read<DataBus>(),
        topics: const {DataTopic.products},
      ),
      child: _ProductPicker(showCost: showCost),
    ),
  );
}

class _ProductPicker extends StatelessWidget {
  const _ProductPicker({required this.showCost});
  final bool showCost;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<QueryCubit<List<Product>, ProductQuery>>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(alignment: AlignmentDirectional.centerStart, child: Text('اختر منتج', style: context.text.titleLarge)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SearchField(
            hint: 'اسم المنتج، الباركود أو SKU',
            onChanged: (v) => cubit.setFilter(cubit.filter.copyWith(search: v)),
            onScan: () async {
              final code = await scanBarcode(context);
              if (code == null || !context.mounted) return;
              final p = await context.read<ProductRepository>().findByBarcode(code);
              if (!context.mounted) return;
              if (p == null) {
                showToast(context, 'لا يوجد منتج بالكود $code', kind: ToastKind.error);
              } else {
                Navigator.pop(context, p);
              }
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: BlocBuilder<QueryCubit<List<Product>, ProductQuery>, ViewState<List<Product>>>(
            builder: (context, state) => AsyncBody<List<Product>>(
              state: state,
              onRetry: cubit.load,
              isEmpty: (d) => d.isEmpty,
              empty: const EmptyView(icon: Icons.inventory_2_outlined, title: 'لا توجد منتجات مطابقة', compact: true),
              builder: (list) => ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final p = list[i];
                  return ListTile(
                    leading: ProductThumb(p, size: 42),
                    title: Text(p.name),
                    subtitle: Text('${p.sku} • المخزون ${Fmt.qty(p.stock)} ${p.unit}'),
                    trailing: Text(Fmt.money(showCost ? p.purchasePrice : p.sellingPrice), style: context.text.labelLarge),
                    onTap: () => Navigator.pop(context, p),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
