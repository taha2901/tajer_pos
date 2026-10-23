import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'data_bus.dart';
import 'errors.dart';

enum ViewStatus { loading, success, failure }

class ViewState<T> {
  const ViewState._(this.status, this.data, this.error);
  const ViewState.loading([T? previous]) : this._(ViewStatus.loading, previous, null);
  const ViewState.success(T data) : this._(ViewStatus.success, data, null);
  const ViewState.failure(Object error, [T? previous]) : this._(ViewStatus.failure, previous, error);

  final ViewStatus status;
  final T? data;
  final Object? error;

  bool get isLoading => status == ViewStatus.loading;
  bool get hasData => data != null;
  String get errorText => error == null ? '' : errorMessage(error!);
}

/// Generic read-model cubit: loads data through a repository call, exposes
/// loading / success / failure, holds a filter, and silently reloads whenever
/// one of [topics] changes on the [DataBus].
class QueryCubit<T, F> extends Cubit<ViewState<T>> {
  QueryCubit(
    this._loader, {
    required this._filter,
    DataBus? bus,
    Set<DataTopic> topics = const {},
  }) : super(const ViewState.loading()) {
    if (bus != null && topics.isNotEmpty) {
      _sub = bus.watch(topics).listen((_) => load(silent: true));
    }
    load();
  }

  final Future<T> Function(F filter) _loader;
  StreamSubscription<void>? _sub;
  F _filter;
  int _request = 0;

  F get filter => _filter;

  void setFilter(F filter) {
    _filter = filter;
    load();
  }

  Future<void> load({bool silent = false}) async {
    final id = ++_request;
    if (!silent || state.data == null) emit(ViewState.loading(state.data));
    try {
      final data = await _loader(_filter);
      if (!isClosed && id == _request) emit(ViewState.success(data));
    } catch (e) {
      if (!isClosed && id == _request) emit(ViewState.failure(e, state.data));
    }
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}

/// Convenience for read models without a filter.
QueryCubit<T, Null> simpleQuery<T>(
  Future<T> Function() loader, {
  DataBus? bus,
  Set<DataTopic> topics = const {},
}) =>
    QueryCubit<T, Null>((_) => loader(), filter: null, bus: bus, topics: topics);
