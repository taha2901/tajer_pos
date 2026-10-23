import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/models/models.dart';
import '../domain/repositories/repositories.dart';

class SessionState {
  const SessionState({this.user, this.settings = const AppSettings(), this.ready = false});

  final AppUser? user;
  final AppSettings settings;

  /// Initial data loaded.
  final bool ready;

  Permissions get permissions => Permissions(user, settings);

  SessionState copyWith({AppUser? Function()? user, AppSettings? settings, bool? ready}) => SessionState(
        user: user != null ? user() : this.user,
        settings: settings ?? this.settings,
        ready: ready ?? this.ready,
      );
}

/// Current user, settings and permissions — app-wide.
class SessionCubit extends Cubit<SessionState> {
  SessionCubit(this._auth, this._settings, this._bootstrap) : super(const SessionState());

  final AuthRepository _auth;
  final SettingsRepository _settings;
  final Future<void> Function() _bootstrap;

  Future<void> start() async {
    await Future.wait([_bootstrap(), Future<void>.delayed(const Duration(milliseconds: 1200))]);
    // Restores the saved session (if the token is still valid).
    final user = await _auth.currentUser();
    emit(state.copyWith(settings: await _settings.load(), user: () => user, ready: true));
  }

  Future<void> login(String username, String pin) async {
    final user = await _auth.login(username, pin);
    emit(state.copyWith(user: () => user, settings: await _settings.load()));
  }

  Future<void> register({required String name, required String username, required String email, required String pin}) async {
    final user = await _auth.register(name: name, username: username, email: email, pin: pin);
    emit(state.copyWith(user: () => user, settings: await _settings.load()));
  }

  Future<void> logout() async {
    await _auth.logout();
    emit(state.copyWith(user: () => null));
  }

  Future<void> updateSettings(AppSettings settings) async {
    emit(state.copyWith(settings: await _settings.save(settings)));
  }

  Future<void> resetDemoData() => _settings.resetDemoData();
}

extension SessionX on BuildContext {
  Permissions get perms => read<SessionCubit>().state.permissions;
  AppSettings get settings => read<SessionCubit>().state.settings;
  AppUser? get currentUser => read<SessionCubit>().state.user;
}
