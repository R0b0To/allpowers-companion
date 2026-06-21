import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A settings text field that debounces [onChangedDebounced] so SharedPreferences
/// is not hit on every keystroke.
///
/// Optionally displays an inline validation message via [validator].
class DebouncedSettingsField extends StatefulWidget {
  const DebouncedSettingsField({
    super.key,
    required this.controller,
    required this.label,
    required this.prefixIcon,
    required this.onChangedDebounced,
    this.keyboardType = TextInputType.text,
    this.suffixIcon,
    this.readOnly = false,
    this.obscureText = false,
    this.validator,
    this.hint,
    this.debounce = const Duration(milliseconds: 500),
  });

  final TextEditingController controller;
  final String label;
  final IconData prefixIcon;
  final VoidCallback onChangedDebounced;
  final TextInputType keyboardType;
  final Widget? suffixIcon;
  final bool readOnly;
  final bool obscureText;

  /// Optional validator; returning a non-null string shows an error hint.
  final String? Function(String value)? validator;
  final String? hint;
  final Duration debounce;

  @override
  State<DebouncedSettingsField> createState() => _DebouncedSettingsFieldState();
}

class _DebouncedSettingsFieldState extends State<DebouncedSettingsField> {
  Timer? _debounce;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    final error = widget.validator?.call(value);
    if (error != _error) setState(() => _error = error);

    if (error != null) return; // Don't persist invalid values.

    _debounce?.cancel();
    _debounce = Timer(widget.debounce, widget.onChangedDebounced);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      onChanged: _onChanged,
      keyboardType: widget.keyboardType,
      readOnly: widget.readOnly,
      obscureText: widget.obscureText,
      style: AppTypography.bodyLg,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        errorText: _error,
        prefixIcon: Icon(widget.prefixIcon, size: 18),
        suffixIcon: widget.suffixIcon,
      ),
    );
  }
}