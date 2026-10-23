import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../domain/models/models.dart';

/// Product image or a tinted initial.
class ProductThumb extends StatelessWidget {
  const ProductThumb(this.product, {super.key, this.size = 44});
  final Product product;
  final double size;

  static const _tints = [
    Color(0xFF0B7A66), Color(0xFF2E5AAC), Color(0xFFB54708), Color(0xFF7A3EA8),
    Color(0xFFC0362C), Color(0xFF0E7490), Color(0xFF4D7C0F),
  ];

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.24);
    final path = product.imagePath;
    if (path != null && path.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: SizedBox(
          width: size,
          height: size,
          child: kIsWeb
              ? Image.network(path, fit: BoxFit.cover, errorBuilder: (_, _, _) => _fallback(context, radius))
              : Image.file(File(path), fit: BoxFit.cover, errorBuilder: (_, _, _) => _fallback(context, radius)),
        ),
      );
    }
    return _fallback(context, radius);
  }

  Widget _fallback(BuildContext context, BorderRadius radius) {
    final c = _tints[product.categoryId.hashCode.abs() % _tints.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: radius),
      child: Text(
        product.name.characters.first,
        style: context.text.titleMedium?.copyWith(color: c, fontSize: size * 0.4),
      ),
    );
  }
}
