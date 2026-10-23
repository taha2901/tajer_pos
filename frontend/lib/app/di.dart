import 'package:flutter_bloc/flutter_bloc.dart';

import '../core/data_bus.dart';
import '../data/local/local_gateway.dart';
import '../data/local/local_read_models.dart';
import '../data/local/local_repositories.dart';
import '../data/local/local_store.dart';
import '../data/local/pos_engine.dart';
import '../data/remote/api_client.dart';
import '../data/remote/api_repositories.dart';
import '../domain/repositories/repositories.dart';

/// Composition root. This is the only place that knows which implementation
/// backs each repository: [AppDependencies.remote] talks to the shop server
/// (Node.js + MongoDB on the LAN), [AppDependencies.local] is the in-memory demo.
class AppDependencies {
  AppDependencies._({
    required this.bus,
    required this.auth,
    required this.settings,
    required this.products,
    required this.parties,
    required this.invoices,
    required this.cash,
    required this.reports,
    required this.alerts,
    required this.search,
    required this._bootstrap,
    this.api,
  });

  factory AppDependencies.local() {
    final store = LocalStore();
    final engine = PosEngine(store);
    final bus = DataBus();
    final g = LocalGateway(store, engine, bus);
    return AppDependencies._(
      bus: bus,
      auth: LocalAuthRepository(g),
      settings: LocalSettingsRepository(g),
      products: LocalProductRepository(g),
      parties: LocalPartyRepository(g),
      invoices: LocalInvoiceRepository(g),
      cash: LocalCashRepository(g),
      reports: LocalReportRepository(g),
      alerts: LocalAlertRepository(g),
      search: LocalSearchRepository(g),
      bootstrap: () async {},
    );
  }

  factory AppDependencies.remote(ApiClient api) {
    final bus = DataBus();
    final g = ApiGateway(api, bus);
    return AppDependencies._(
      bus: bus,
      auth: ApiAuthRepository(g),
      settings: ApiSettingsRepository(g),
      products: ApiProductRepository(g),
      parties: ApiPartyRepository(g),
      invoices: ApiInvoiceRepository(g),
      cash: ApiCashRepository(g),
      reports: ApiReportRepository(g),
      alerts: ApiAlertRepository(g),
      search: ApiSearchRepository(g),
      bootstrap: () async {},
      api: api,
    );
  }

  /// Null in local (demo) mode.
  final ApiClient? api;
  final DataBus bus;
  final AuthRepository auth;
  final SettingsRepository settings;
  final ProductRepository products;
  final PartyRepository parties;
  final InvoiceRepository invoices;
  final CashRepository cash;
  final ReportRepository reports;
  final AlertRepository alerts;
  final SearchRepository search;
  final Future<void> Function() _bootstrap;

  /// Loads initial data (mock seed today, warm caches / token refresh later).
  Future<void> bootstrap() => _bootstrap();

  List<RepositoryProvider<Object>> get providers => [
        RepositoryProvider<AppDependencies>.value(value: this),
        RepositoryProvider<DataBus>.value(value: bus),
        RepositoryProvider<AuthRepository>.value(value: auth),
        RepositoryProvider<SettingsRepository>.value(value: settings),
        RepositoryProvider<ProductRepository>.value(value: products),
        RepositoryProvider<PartyRepository>.value(value: parties),
        RepositoryProvider<InvoiceRepository>.value(value: invoices),
        RepositoryProvider<CashRepository>.value(value: cash),
        RepositoryProvider<ReportRepository>.value(value: reports),
        RepositoryProvider<AlertRepository>.value(value: alerts),
        RepositoryProvider<SearchRepository>.value(value: search),
      ];
}
