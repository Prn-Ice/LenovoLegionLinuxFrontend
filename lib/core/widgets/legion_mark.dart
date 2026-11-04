import 'package:flutter/material.dart';

/// The circular emblem from the Lenovo Legion wordmark.
class LegionMark extends StatelessWidget {
  const LegionMark({super.key, required this.color, this.size = 24});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/legion_mark.png',
      width: size,
      height: size,
      color: color,
      excludeFromSemantics: true,
    );
  }
}
