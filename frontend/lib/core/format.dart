import 'package:intl/intl.dart';

abstract final class Fmt {
  static final _money = NumberFormat('#,##0.##', 'en');
  static final _money2 = NumberFormat('#,##0.00', 'en');
  static final _compact = NumberFormat.compact(locale: 'en');

  static const currency = 'ج.م';

  static const _months = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];
  static const _weekdays = ['الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];

  static String money(num v, {bool symbol = true}) {
    final s = _money.format(v);
    return symbol ? '$s $currency' : s;
  }

  static String money2(num v) => '${_money2.format(v)} $currency';

  static String compact(num v) => v.abs() < 10000 ? _money.format(v) : _compact.format(v);

  static String number(num v) => _money.format(v);

  static String qty(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  static String percent(num v) => '${v.toStringAsFixed(v.abs() >= 10 ? 0 : 1)}%';

  static String date(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  static String shortDate(DateTime d) => '${d.day}/${d.month}';

  static String dayMonth(DateTime d) => '${d.day} ${_months[d.month - 1]}';

  static String monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

  static String weekday(DateTime d) => _weekdays[d.weekday - 1];

  static String time(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour < 12 ? 'ص' : 'م'}';
  }

  static String dateTime(DateTime d) => '${date(d)} • ${time(d)}';

  static String relative(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'اليوم ${time(d)}';
    if (diff == 1) return 'أمس ${time(d)}';
    if (diff < 7) return '${weekday(d)} ${time(d)}';
    return date(d);
  }

  static String dayLabel(DateTime d) {
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (diff == 0) return 'اليوم';
    if (diff == 1) return 'أمس';
    return '${weekday(d)} ${dayMonth(d)}';
  }
}

/// Round to 2 decimals (money).
double r2(num v) => (v * 100).roundToDouble() / 100;

/// Parses user input that may contain Arabic-Indic digits or commas.
double? parseNum(String? s) {
  if (s == null) return null;
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  final b = StringBuffer();
  for (final ch in s.trim().split('')) {
    final i = arabic.indexOf(ch);
    if (i >= 0) {
      b.write(i);
    } else if (ch == '٫') {
      b.write('.');
    } else if (ch != ',' && ch != '٬') {
      b.write(ch);
    }
  }
  return double.tryParse(b.toString());
}
