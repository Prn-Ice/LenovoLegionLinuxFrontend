import 'package:material_ui/material_ui.dart';

class SectionPlaceholderPage extends StatelessWidget {
  const SectionPlaceholderPage({
    super.key,
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(description, style: textTheme.bodyLarge),
        ],
      ),
    );
  }
}
