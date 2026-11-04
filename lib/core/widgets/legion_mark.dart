import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The circular emblem from the Lenovo Legion wordmark.
class LegionMark extends StatelessWidget {
  const LegionMark({super.key, required this.color, this.size = 24});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/branding/legion_mark.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
  }
}
