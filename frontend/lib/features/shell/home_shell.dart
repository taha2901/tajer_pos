import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/models/models.dart';
import '../dashboard/dashboard_screen.dart';
import '../parties/parties_screen.dart';
import '../pos/cart_cubit.dart';
import '../pos/pos_screen.dart';
import '../products/products_screen.dart';
import 'more_screen.dart';

enum ShellTab { home, pos, products, customers, more }

/// Which bottom tab is visible — lets any screen jump to e.g. the POS.
class ShellCubit extends Cubit<ShellTab> {
  ShellCubit() : super(ShellTab.home);
  void go(ShellTab tab) => emit(tab);
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  // Tabs are built lazily on first visit, then kept alive.
  final _visited = <ShellTab>{ShellTab.home};

  @override
  void initState() {
    super.initState();
    context.read<ShellCubit>().go(ShellTab.home);
  }

  Widget _page(ShellTab t) => switch (t) {
        ShellTab.home => const DashboardScreen(),
        ShellTab.pos => const PosScreen(),
        ShellTab.products => const ProductsScreen(isTab: true),
        ShellTab.customers => const PartiesScreen(type: PartyType.customer, isTab: true),
        ShellTab.more => const MoreScreen(),
      };

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ShellCubit, ShellTab>(
      builder: (context, tab) {
        _visited.add(tab);
        return PopScope(
          canPop: tab == ShellTab.home,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) context.read<ShellCubit>().go(ShellTab.home);
          },
          child: Scaffold(
            body: IndexedStack(
              index: tab.index,
              children: [for (final t in ShellTab.values) _visited.contains(t) ? _page(t) : const SizedBox.shrink()],
            ),
            bottomNavigationBar: BlocBuilder<CartCubit, CartState>(
              buildWhen: (a, b) => a.lines.length != b.lines.length,
              builder: (context, cart) => NavigationBar(
                selectedIndex: tab.index,
                onDestinationSelected: (i) => context.read<ShellCubit>().go(ShellTab.values[i]),
                destinations: [
                  const NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard_rounded), label: 'الرئيسية'),
                  NavigationDestination(
                    icon: Badge(isLabelVisible: cart.lines.isNotEmpty, label: Text('${cart.lines.length}'), child: const Icon(Icons.point_of_sale_outlined)),
                    selectedIcon: Badge(isLabelVisible: cart.lines.isNotEmpty, label: Text('${cart.lines.length}'), child: const Icon(Icons.point_of_sale_rounded)),
                    label: 'البيع',
                  ),
                  const NavigationDestination(icon: Icon(Icons.inventory_2_outlined), selectedIcon: Icon(Icons.inventory_2_rounded), label: 'المنتجات'),
                  const NavigationDestination(icon: Icon(Icons.people_outline_rounded), selectedIcon: Icon(Icons.people_rounded), label: 'العملاء'),
                  const NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'المزيد'),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
