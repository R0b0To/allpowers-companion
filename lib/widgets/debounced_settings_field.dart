import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A settings text field that debounces its `onChangedDebounced` callback
/// so we don't hit SharedPreferences on every single keystroke (the
/// original implementation called `setState` + a full preferences write on
/// every character typed).
class DebouncedSettingsField extends StatefulWidget {
  const DebouncedSettingsField({
    super.key,
    required this.controller,
    required this.label,
    required this.prefixIcon,
    required this.onChangedDebounced,
    this.keyboardType = TextInputType.text,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String label;
  final IconData prefixIcon;
  final VoidCallback onChangedDebounced;
  final TextInputType keyboardType;
  final Widget? suffixIcon;

  @override
  State<DebouncedSettingsField> createState() => _DebouncedSettingsFieldState();
}

class _DebouncedSettingsFieldState extends State<DebouncedSettingsField> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), widget.onChangedDebounced);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      onChanged: _onChanged,
      keyboardType: widget.keyboardType,
      style: const TextStyle(fontSize: 13, color: Colors.white70),
      decoration: InputDecoration(
        labelText: widget.label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        prefixIcon: Icon(widget.prefixIcon, size: 16, color: Colors.grey),
        suffixIcon: widget.suffixIcon,
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.teal, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border, width: 1),
        ),
      ),
    );
  }
}