/// A user-facing failure (validation / business rule). The message is shown as-is.
class BusinessException implements Exception {
  const BusinessException(this.message, {this.code});
  final String message;

  /// Machine-readable code so the UI can react (e.g. offer an override).
  final String? code;

  @override
  String toString() => message;
}

/// Simulated transport failure (what an API client would throw).
class NetworkException implements Exception {
  const NetworkException([this.message = 'تعذّر الاتصال بالخادم. تحقق من الاتصال وحاول مرة أخرى.']);
  final String message;

  @override
  String toString() => message;
}

class NotFoundException implements Exception {
  const NotFoundException([this.message = 'العنصر غير موجود أو تم حذفه.']);
  final String message;

  @override
  String toString() => message;
}

abstract final class ErrorCodes {
  static const creditLimit = 'credit_limit';
  static const insufficientStock = 'insufficient_stock';
  static const drawerClosed = 'drawer_closed';
  static const insufficientCash = 'insufficient_cash';
  static const hasTransactions = 'has_transactions';
}

String errorMessage(Object error) => switch (error) {
      BusinessException e => e.message,
      NetworkException e => e.message,
      NotFoundException e => e.message,
      _ => 'حدث خطأ غير متوقع. حاول مرة أخرى.',
    };
