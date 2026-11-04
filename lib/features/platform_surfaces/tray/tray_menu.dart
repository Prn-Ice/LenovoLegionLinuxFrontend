/// A desktop menu entry. Callbacks must use the application's existing
/// confirmation and authorization flows; this layer never changes hardware.
class TrayMenuItem {
  TrayMenuItem({
    required this.id,
    required this.label,
    this.enabled = false,
    this.toggleType,
    this.checked,
    this.onActivate,
    List<TrayMenuItem> children = const [],
  }) : children = List.unmodifiable(children);

  final int id;
  final String label;
  final bool enabled;

  /// `radio`, `checkmark`, or null. Null checked means unknown, not unchecked.
  final String? toggleType;
  final bool? checked;
  final void Function()? onActivate;
  final List<TrayMenuItem> children;
}
