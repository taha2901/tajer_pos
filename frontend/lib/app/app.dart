import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/pos/cart_cubit.dart';
import '../features/shell/home_shell.dart';
import 'di.dart';
import 'session_cubit.dart';
import 'theme.dart';

class TajerApp extends StatelessWidget {
  const TajerApp({super.key, required this.deps});
  final AppDependencies deps;

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: deps.providers,
      // App-wide state lives above MaterialApp so pushed routes can reach it.
      child: MultiBlocProvider(
        providers: [
          BlocProvider(create: (_) => SessionCubit(deps.auth, deps.settings, deps.bootstrap)..start()),
          BlocProvider(
            create: (c) => CartCubit(allowNegativeStock: () => c.read<SessionCubit>().state.settings.allowNegativeStock),
          ),
          BlocProvider(create: (_) => ShellCubit()),
        ],
        child: BlocBuilder<SessionCubit, SessionState>(
          buildWhen: (a, b) =>
              a.settings.themeMode != b.settings.themeMode || a.ready != b.ready || a.user?.id != b.user?.id,
          builder: (context, s) {
            return MaterialApp(
              title: 'تاجر POS',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              darkTheme: AppTheme.dark(),
              themeMode: s.settings.themeMode,
              locale: const Locale('ar', 'EG'),
              supportedLocales: const [Locale('ar', 'EG'), Locale('en')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              home: !s.ready
                  ? const SplashScreen()
                  : s.user == null
                      ? const LoginScreen()
                      : HomeShell(key: ValueKey(s.user!.id)),
            );
          },
        ),
      ),
    );
  }
}
