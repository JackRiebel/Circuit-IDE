import 'package:flutter/material.dart';

class CommandDescriptor {
  final String id;
  final String title;
  final String? description;
  final String? shortcut;
  final String category;
  final IconData icon;
  final bool Function()? isEnabled;
  final void Function() run;

  const CommandDescriptor({
    required this.id,
    required this.title,
    this.description,
    this.shortcut,
    required this.category,
    required this.icon,
    this.isEnabled,
    required this.run,
  });

  bool get enabled => isEnabled?.call() ?? true;
}
