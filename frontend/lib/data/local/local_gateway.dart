import 'dart:math';

import '../../core/data_bus.dart';
import '../../core/errors.dart';
import 'local_store.dart';
import 'pos_engine.dart';

/// Shared plumbing for local repositories: simulated network latency and
/// failures (toggled from Settings → Developer) and change notifications.
class LocalGateway {
  LocalGateway(this.db, this.engine, this.bus);

  final LocalStore db;
  final PosEngine engine;
  final DataBus bus;
  final _rnd = Random();

  Future<void> _network({required bool write}) async {
    if (db.settings.simulateLatency) {
      await Future<void>.delayed(Duration(milliseconds: write ? 450 : 220 + _rnd.nextInt(180)));
    }
    if (db.settings.simulateErrors && _rnd.nextDouble() < 0.25) {
      throw const NetworkException();
    }
  }

  Future<T> read<T>(T Function() body) async {
    await _network(write: false);
    return body();
  }

  /// Runs [body] atomically (engine validates before mutating) then notifies.
  Future<T> write<T>(T Function() body, Set<DataTopic> topics) async {
    await _network(write: true);
    final result = body();
    bus.emit({...topics, DataTopic.alerts, DataTopic.search});
    return result;
  }
}
