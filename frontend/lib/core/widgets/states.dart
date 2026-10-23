import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../query_cubit.dart';

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 52 : 72,
          height: compact ? 52 : 72,
          decoration: BoxDecoration(color: p.subtle, shape: BoxShape.circle),
          child: Icon(icon, size: compact ? 26 : 34, color: p.muted),
        ),
        SizedBox(height: compact ? 10 : 16),
        Text(title, style: context.text.titleMedium, textAlign: TextAlign.center),
        if (message != null) ...[
          const SizedBox(height: 6),
          Text(message!, style: context.text.bodySmall, textAlign: TextAlign.center),
        ],
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 16),
          FilledButton.tonalIcon(onPressed: onAction, icon: const Icon(Icons.add), label: Text(actionLabel!)),
        ],
      ],
    );
    return Center(
      child: Padding(padding: EdgeInsets.all(compact ? 16 : 32), child: body),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry, this.compact = false});
  final String message;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: p.dangerBg, shape: BoxShape.circle),
              child: Icon(Icons.cloud_off_rounded, color: p.danger, size: 30),
            ),
            const SizedBox(height: 14),
            Text('تعذّر تحميل البيانات', style: context.text.titleMedium),
            const SizedBox(height: 6),
            Text(message, style: context.text.bodySmall, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Pulsing placeholder rows shown on first load.
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.count = 7, this.padding = const EdgeInsets.all(16), this.shrinkWrap = false});
  final int count;
  final EdgeInsets padding;
  final bool shrinkWrap;

  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = context.palette.subtle;
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: context.palette.border, borderRadius: BorderRadius.circular(6)),
        );
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
      child: ListView.separated(
        shrinkWrap: widget.shrinkWrap,
        physics: widget.shrinkWrap ? const NeverScrollableScrollPhysics() : null,
        padding: widget.padding,
        itemCount: widget.count,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              Container(width: 40, height: 40, decoration: BoxDecoration(color: context.palette.border, borderRadius: BorderRadius.circular(10))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [bar(140.0 + (i % 3) * 30, 12), const SizedBox(height: 8), bar(90, 10)],
                ),
              ),
              bar(56, 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders a [ViewState]: skeleton on first load, error with retry, empty
/// state, or content (with a thin progress bar while refreshing).
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({
    super.key,
    required this.state,
    required this.builder,
    this.onRetry,
    this.isEmpty,
    this.empty,
    this.loading,
  });

  final ViewState<T> state;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  final bool Function(T data)? isEmpty;
  final Widget? empty;
  final Widget? loading;

  @override
  Widget build(BuildContext context) {
    final data = state.data;
    if (data == null) {
      if (state.status == ViewStatus.failure) return ErrorView(message: state.errorText, onRetry: onRetry);
      return loading ?? const SkeletonList();
    }
    final content = (isEmpty?.call(data) ?? false) && empty != null ? empty! : builder(data);
    return Stack(
      children: [
        Positioned.fill(child: content),
        if (state.isLoading)
          const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
        if (state.status == ViewStatus.failure)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Material(
              color: context.palette.dangerBg,
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.error_outline, color: context.palette.danger),
                title: Text(state.errorText, style: context.text.bodySmall?.copyWith(color: context.palette.danger)),
                trailing: onRetry == null ? null : TextButton(onPressed: onRetry, child: const Text('إعادة')),
              ),
            ),
          ),
      ],
    );
  }
}
