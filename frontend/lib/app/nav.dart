import 'package:flutter/material.dart';

extension NavX on BuildContext {
  Future<T?> push<T>(Widget page) => Navigator.of(this).push<T>(MaterialPageRoute(builder: (_) => page));

  Future<T?> replace<T>(Widget page) =>
      Navigator.of(this).pushReplacement<T, Object?>(MaterialPageRoute(builder: (_) => page));

  void pop<T>([T? result]) => Navigator.of(this).pop<T>(result);
}
