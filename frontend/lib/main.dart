import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/di.dart';
import 'data/remote/api_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = await ApiClient.create();
  runApp(TajerApp(deps: AppDependencies.remote(api)));
}