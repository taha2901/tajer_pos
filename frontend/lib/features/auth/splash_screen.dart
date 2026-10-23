import 'package:flutter/material.dart';

import '../../app/theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: context.colors.primary, borderRadius: BorderRadius.circular(size * 0.28)),
      child: Icon(Icons.point_of_sale_rounded, color: context.colors.onPrimary, size: size * 0.5),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const BrandMark(size: 84),
            const SizedBox(height: 20),
            Text('تاجر', style: context.text.headlineMedium),
            const SizedBox(height: 4),
            Text('نظام نقاط البيع وإدارة المحل', style: context.text.bodySmall),
            const SizedBox(height: 36),
            const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.6)),
            const SizedBox(height: 12),
            Text('جارِ تجهيز البيانات...', style: context.text.labelSmall?.copyWith(color: context.palette.muted)),
          ],
        ),
      ),
    );
  }
}
