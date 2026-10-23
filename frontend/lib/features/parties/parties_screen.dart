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
import 'party_details_screen.dart';
import 'party_form_screen.dart';

typedef PartiesCubit = QueryCubit<List<Party>, PartyQuery>;

/// Customers or suppliers list.
class PartiesScreen extends StatelessWidget {
  const PartiesScreen({super.key, required this.type, this.isTab = false});
  final PartyType type;
  final bool isTab;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (c) => PartiesCubit(
        (q) => c.read<PartyRepository>().getParties(q),
        filter: PartyQuery(type),
        bus: c.read<DataBus>(),
        topics: const {DataTopic.parties},
      ),
      child: _View(type: type, isTab: isTab),
    );
  }
}

class _View extends StatelessWidget {
  const _View({required this.type, required this.isTab});
  final PartyType type;
  final bool isTab;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PartiesCubit>();
    final isCustomer = type == PartyType.customer;
    return Scaffold(
      appBar: AppBar(title: Text(type.plural), automaticallyImplyLeading: !isTab),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SearchField(hint: 'ابحث بالاسم أو الهاتف', onChanged: (v) => cubit.setFilter(cubit.filter.copyWith(search: v))),
          ),
          BlocBuilder<PartiesCubit, ViewState<List<Party>>>(
            builder: (context, _) => ChipsRow<PartyFilter>(
              values: isCustomer ? PartyFilter.values : PartyFilter.values.where((f) => f != PartyFilter.overLimit).toList(),
              selected: cubit.filter.filter,
              label: (f) => f == PartyFilter.withBalance && !isCustomer ? 'مستحق لهم' : f.label,
              onSelected: (f) => cubit.setFilter(cubit.filter.copyWith(filter: f)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: BlocBuilder<PartiesCubit, ViewState<List<Party>>>(
              builder: (context, state) => AsyncBody<List<Party>>(
                state: state,
                onRetry: cubit.load,
                isEmpty: (d) => d.isEmpty,
                empty: cubit.filter.search.isEmpty && cubit.filter.filter == PartyFilter.all
                    ? EmptyView(
                        icon: isCustomer ? Icons.people_outline : Icons.local_shipping_outlined,
                        title: isCustomer ? 'لا يوجد عملاء بعد' : 'لا يوجد موردين بعد',
                        message: isCustomer ? 'أضف عملاءك لتتمكن من البيع الآجل ومتابعة حساباتهم' : 'أضف الموردين لتسجيل المشتريات والمستحقات',
                        actionLabel: 'إضافة ${type.label}',
                        onAction: () => context.push(PartyFormScreen(type: type)),
                      )
                    : const EmptyView(icon: Icons.search_off_rounded, title: 'لا توجد نتائج مطابقة'),
                builder: (list) {
                  final totalBalance = list.where((p) => p.balance > 0).fold(0.0, (s, p) => s + p.balance);
                  return RefreshIndicator(
                    onRefresh: cubit.load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      itemCount: list.length + 1,
                      separatorBuilder: (_, i) => SizedBox(height: i == 0 ? 10 : 6),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return AppCard(
                            color: context.palette.subtle,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            child: Row(
                              children: [
                                Text('${list.length} ${type.label}', style: context.text.labelLarge),
                                const Spacer(),
                                Text(isCustomer ? 'إجمالي المديونيات ' : 'إجمالي المستحقات ', style: context.text.bodySmall),
                                Text(Fmt.money(totalBalance), style: context.text.titleSmall?.copyWith(color: context.palette.danger)),
                              ],
                            ),
                          );
                        }
                        return PartyTile(party: list[i - 1]);
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'party_fab_${type.name}',
        onPressed: () => context.push(PartyFormScreen(type: type)),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text('${type.label} جديد'),
      ),
    );
  }
}

class PartyTile extends StatelessWidget {
  const PartyTile({super.key, required this.party});
  final Party party;

  @override
  Widget build(BuildContext context) {
    final p = party;
    final pal = context.palette;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => context.push(PartyDetailsScreen(partyId: p.id)),
      child: Row(
        children: [
          Initials(p.name, tone: p.overLimit ? Tone.danger : Tone.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name, style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  [if (p.phone.isNotEmpty) p.phone, if (!p.isCustomer && p.company.isNotEmpty) p.company].join(' • '),
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
              Text(
                p.hasDebt ? Fmt.money(p.balance) : p.balance < -0.009 ? 'دائن ${Fmt.money(-p.balance)}' : 'لا يوجد رصيد',
                style: context.text.titleSmall?.copyWith(color: p.hasDebt ? pal.danger : p.balance < 0 ? pal.success : pal.muted),
              ),
              if (p.overLimit) const StatusPill('تجاوز الحد', tone: Tone.danger),
            ],
          ),
        ],
      ),
    );
  }
}
