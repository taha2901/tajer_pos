import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import '../../domain/models/models.dart';
import '../format.dart';

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction, this.padding, this.trailing});
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsetsGeometry? padding;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(20, 24, 12, 8),
      child: Row(
        children: [
          Expanded(child: Text(title, style: context.text.labelLarge?.copyWith(color: context.palette.muted))),
          ?trailing,
          if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ),
    );
  }
}

enum Tone { neutral, success, warning, danger, info, primary }

extension ToneColors on BuildContext {
  (Color fg, Color bg) tone(Tone t) {
    final p = palette;
    return switch (t) {
      Tone.success => (p.success, p.successBg),
      Tone.warning => (p.warning, p.warningBg),
      Tone.danger => (p.danger, p.dangerBg),
      Tone.info => (p.info, p.infoBg),
      Tone.primary => (colors.primary, colors.primary.withValues(alpha: 0.1)),
      Tone.neutral => (p.muted, p.subtle),
    };
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.label, {super.key, this.tone = Tone.neutral, this.icon});
  final String label;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = context.tone(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
          Text(label, style: context.text.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class PaymentStatusPill extends StatelessWidget {
  const PaymentStatusPill(this.invoice, {super.key});
  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    if (invoice.fullyReturned) return const StatusPill('مرتجعة', tone: Tone.neutral);
    return switch (invoice.paymentStatus) {
      PaymentStatus.paid => StatusPill(PaymentStatus.paid.label, tone: Tone.success),
      PaymentStatus.partial => StatusPill(PaymentStatus.partial.label, tone: Tone.warning),
      PaymentStatus.unpaid => StatusPill(PaymentStatus.unpaid.label, tone: Tone.danger),
    };
  }
}

class StockPill extends StatelessWidget {
  const StockPill(this.product, {super.key});
  final Product product;

  @override
  Widget build(BuildContext context) {
    if (product.isOutOfStock) return const StatusPill('نفد', tone: Tone.danger);
    if (product.isLowStock) return StatusPill('${Fmt.qty(product.stock)} منخفض', tone: Tone.warning);
    return StatusPill('${Fmt.qty(product.stock)} ${product.unit}', tone: Tone.neutral);
  }
}

/// Compact metric used on dashboards and summaries.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone = Tone.primary,
    this.caption,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Tone tone;
  final String? caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (fg, _) = context.tone(tone);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: fg.withValues(alpha: 0.8)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(label, style: context.text.labelMedium?.copyWith(color: context.palette.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value, style: context.text.titleLarge?.copyWith(fontSize: 18)),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(caption!, style: context.text.labelSmall?.copyWith(color: context.palette.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.bold = false, this.valueColor, this.large = false, this.icon});
  final String label;
  final String value;
  final bool bold;
  final bool large;
  final Color? valueColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final style = large
        ? context.text.titleLarge
        : bold
            ? context.text.titleSmall
            : context.text.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, size: 18, color: context.palette.muted), const SizedBox(width: 8)],
          Expanded(
            child: Text(label, style: (bold || large ? context.text.titleSmall : context.text.bodyMedium)?.copyWith(color: bold || large ? null : context.palette.muted)),
          ),
          const SizedBox(width: 12),
          Flexible(child: Text(value, style: style?.copyWith(color: valueColor), textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}

class Initials extends StatelessWidget {
  const Initials(this.name, {super.key, this.size = 42, this.tone = Tone.primary});
  final String name;
  final double size;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final (fg, bg) = context.tone(tone);
    final parts = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    final text = parts.isEmpty ? '?' : parts.take(2).map((e) => e.characters.first).join(' ');
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Text(text, style: context.text.titleSmall?.copyWith(color: fg, fontSize: size * 0.32)),
    );
  }
}

class QtyStepper extends StatelessWidget {
  const QtyStepper({super.key, required this.value, required this.onChanged, this.min = 0, this.max, this.onTapValue, this.compact = false});
  final double value;
  final double min;
  final double? max;
  final ValueChanged<double> onChanged;
  final VoidCallback? onTapValue;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 32.0 : 38.0;
    Widget btn(IconData icon, VoidCallback? onTap) => SizedBox(
          width: size,
          height: size,
          child: IconButton.filledTonal(
            padding: EdgeInsets.zero,
            iconSize: compact ? 16 : 18,
            onPressed: onTap == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap();
                  },
            icon: Icon(icon),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.remove, value - 1 >= min ? () => onChanged(value - 1) : null),
        InkWell(
          onTap: onTapValue,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: BoxConstraints(minWidth: compact ? 36 : 44),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            alignment: Alignment.center,
            child: Text(Fmt.qty(value), style: context.text.titleMedium),
          ),
        ),
        btn(Icons.add, max == null || value + 1 <= max! ? () => onChanged(value + 1) : null),
      ],
    );
  }
}

/// Search box with debounce and optional scan button.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.onScan,
    this.autofocus = false,
    this.controller,
    this.onSubmitted,
    this.debounce = const Duration(milliseconds: 300),
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback? onScan;
  final bool autofocus;
  final TextEditingController? controller;
  final ValueChanged<String>? onSubmitted;
  final Duration debounce;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final _c = widget.controller ?? TextEditingController();
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    if (widget.controller == null) _c.dispose();
    super.dispose();
  }

  void _changed(String v) {
    setState(() {});
    _t?.cancel();
    _t = Timer(widget.debounce, () => widget.onChanged(v));
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      autofocus: widget.autofocus,
      onChanged: _changed,
      onSubmitted: widget.onSubmitted,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search_rounded),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_c.text.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () {
                  _c.clear();
                  _changed('');
                },
              ),
            if (widget.onScan != null)
              IconButton(
                tooltip: 'مسح الباركود',
                icon: Icon(Icons.qr_code_scanner_rounded, color: context.colors.primary),
                onPressed: widget.onScan,
              ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal single-select chips.
class ChipsRow<T> extends StatelessWidget {
  const ChipsRow({
    super.key,
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
    this.count,
  });

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelected;
  final EdgeInsetsGeometry padding;
  final int? Function(T)? count;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (final v in values)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: ChoiceChip(
                label: Text(count?.call(v) == null ? label(v) : '${label(v)} (${count!(v)})'),
                selected: v == selected,
                labelStyle: TextStyle(
                  color: v == selected ? context.colors.primary : null,
                  fontWeight: v == selected ? FontWeight.w700 : FontWeight.w500,
                ),
                side: BorderSide.none,
                onSelected: (_) => onSelected(v),
              ),
            ),
        ],
      ),
    );
  }
}

class MoneyField extends StatelessWidget {
  const MoneyField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.onChanged,
    this.autofocus = false,
    this.suffix = Fmt.currency,
    this.helper,
    this.decimal = true,
    this.textInputAction,
    this.big = false,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final String? suffix;
  final String? helper;
  final bool decimal;
  final bool big;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.٠-٩٫]'))],
      textInputAction: textInputAction,
      style: big ? context.text.headlineSmall : null,
      decoration: InputDecoration(labelText: label, suffixText: suffix, helperText: helper),
      validator: validator,
      onChanged: onChanged,
    );
  }
}

String? requiredNumber(String? v, {double min = 0, bool allowZero = true}) {
  final n = parseNum(v);
  if (n == null) return 'أدخل رقماً صحيحاً';
  if (n < min || (!allowZero && n == 0)) return 'القيمة غير صحيحة';
  return null;
}

String? requiredText(String? v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null;

/// Period selector used across lists and reports.
enum Period {
  today('اليوم'),
  week('7 أيام'),
  month('30 يوم'),
  thisMonth('هذا الشهر'),
  all('الكل'),
  custom('مخصص');

  const Period(this.label);
  final String label;

  DateRange? get range => switch (this) {
        Period.today => DateRange.today(),
        Period.week => DateRange.lastDays(7),
        Period.month => DateRange.lastDays(30),
        Period.thisMonth => DateRange.thisMonth(),
        _ => null,
      };
}

class PeriodSelector extends StatelessWidget {
  const PeriodSelector({
    super.key,
    required this.period,
    required this.onChanged,
    this.customRange,
    this.allowAll = true,
  });

  final Period period;
  final DateRange? customRange;
  final bool allowAll;
  final void Function(Period period, DateRange? range) onChanged;

  @override
  Widget build(BuildContext context) {
    final values = Period.values.where((p) => allowAll || p != Period.all).toList();
    return ChipsRow<Period>(
      values: values,
      selected: period,
      label: (p) => p == Period.custom && period == Period.custom && customRange != null
          ? '${Fmt.shortDate(customRange!.from)} - ${Fmt.shortDate(customRange!.to)}'
          : p.label,
      onSelected: (p) async {
        if (p != Period.custom) return onChanged(p, p.range);
        final now = DateTime.now();
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(now.year - 2),
          lastDate: now,
          initialDateRange: customRange == null ? null : DateTimeRange(start: customRange!.from, end: customRange!.to),
          helpText: 'اختر الفترة',
          saveText: 'تم',
        );
        if (picked != null) {
          onChanged(Period.custom, DateRange(DateRange.startOfDay(picked.start), DateRange.endOfDay(picked.end)));
        }
      },
    );
  }
}

/// Bordered group of list rows (iOS-like settings group, flat).
class ListGroup extends StatelessWidget {
  const ListGroup({super.key, required this.children, this.margin = const EdgeInsets.symmetric(horizontal: 16)});
  final List<Widget> children;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i < children.length - 1) items.add(const Divider(indent: 16, endIndent: 16));
    }
    return Padding(
      padding: margin,
      child: Card(clipBehavior: Clip.antiAlias, child: Column(children: items)),
    );
  }
}

/// Two-column responsive grid for metric tiles.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, this.padding = const EdgeInsets.symmetric(horizontal: 16), this.minTileWidth = 160});
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: LayoutBuilder(builder: (context, c) {
        final cols = (c.maxWidth / minTileWidth).floor().clamp(2, 4);
        final w = (c.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [for (final child in children) SizedBox(width: w, child: child)],
        );
      }),
    );
  }
}

/// Sticky bottom action area.
class BottomBar extends StatelessWidget {
  const BottomBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.palette.border)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
      child: child,
    );
  }
}

/// Limits content width on tablets / desktop.
class MaxWidth extends StatelessWidget {
  const MaxWidth({super.key, required this.child, this.width = 720});
  final Widget child;
  final double width;

  @override
  Widget build(BuildContext context) =>
      Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: width), child: child));
}

/// Calm content block: white surface, generous padding, no border.
class SoftPanel extends StatelessWidget {
  const SoftPanel({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.onTap});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
      );
}
