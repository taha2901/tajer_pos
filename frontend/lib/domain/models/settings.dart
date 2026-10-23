import 'package:flutter/material.dart' show ThemeMode;

class AppUser {
  const AppUser({required this.id, required this.name, required this.username, this.email = ''});
  final String id;
  final String name;
  final String username;
  final String email;
}

class AppSettings {
  const AppSettings({
    this.storeName = 'سوبر ماركت التاجر',
    this.storePhone = '01001234567',
    this.storeAddress = 'القاهرة - مدينة نصر - شارع عباس العقاد',
    this.invoiceFooter = 'شكراً لزيارتكم • البضاعة المباعة تُرد خلال 14 يوماً',
    this.allowNegativeStock = false,
    this.largeExpenseThreshold = 2000,
    this.debtDueDays = 30,
    this.closingReminderHour = 22,
    this.themeMode = ThemeMode.light,
    this.simulateLatency = true,
    this.simulateErrors = false,
  });

  final String storeName;
  final String storePhone;
  final String storeAddress;
  final String invoiceFooter;
  final bool allowNegativeStock;
  final double largeExpenseThreshold;

  /// Invoices unpaid older than this are flagged as due.
  final int debtDueDays;
  final int closingReminderHour;
  final ThemeMode themeMode;

  /// Developer options for the mock data layer.
  final bool simulateLatency;
  final bool simulateErrors;

  AppSettings copyWith({
    String? storeName,
    String? storePhone,
    String? storeAddress,
    String? invoiceFooter,
    bool? allowNegativeStock,
    double? largeExpenseThreshold,
    int? debtDueDays,
    int? closingReminderHour,
    ThemeMode? themeMode,
    bool? simulateLatency,
    bool? simulateErrors,
  }) =>
      AppSettings(
        storeName: storeName ?? this.storeName,
        storePhone: storePhone ?? this.storePhone,
        storeAddress: storeAddress ?? this.storeAddress,
        invoiceFooter: invoiceFooter ?? this.invoiceFooter,
        allowNegativeStock: allowNegativeStock ?? this.allowNegativeStock,
        largeExpenseThreshold: largeExpenseThreshold ?? this.largeExpenseThreshold,
        debtDueDays: debtDueDays ?? this.debtDueDays,
        closingReminderHour: closingReminderHour ?? this.closingReminderHour,
        themeMode: themeMode ?? this.themeMode,
        simulateLatency: simulateLatency ?? this.simulateLatency,
        simulateErrors: simulateErrors ?? this.simulateErrors,
      );
}

/// Permission helpers. Every signed-in user has the same full access.
class Permissions {
  const Permissions(this.user, this.settings);
  final AppUser? user;
  final AppSettings settings;

  bool get isAdmin => user != null;
  bool get canEditPrice => isAdmin;
  double get maxDiscountPercent => 100;
  bool get canOverrideCreditLimit => isAdmin;
  bool get canDelete => isAdmin;
  bool get canAdjustStock => isAdmin;
  bool get canEditSettings => isAdmin;
}
