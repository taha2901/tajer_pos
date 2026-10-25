import 'dart:async';

/// What changed. Read models subscribe to the topics they depend on.
enum DataTopic { products, parties, invoices, cash, settings, alerts, search, shopping }

/// Broadcasts data changes after successful mutations so every open screen
/// refreshes (stock, balances, drawer...). An API implementation can emit the
/// same topics after a request succeeds or when a push event arrives.
class DataBus {
  final _controller = StreamController<Set<DataTopic>>.broadcast();

  Stream<Set<DataTopic>> get stream => _controller.stream;

  void emit(Set<DataTopic> topics) => _controller.add(topics);

  Stream<void> watch(Set<DataTopic> topics) =>
      stream.where((changed) => changed.any(topics.contains));

  void dispose() => _controller.close();
}
