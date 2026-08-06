import 'package:flutter/material.dart';

class PermissionExplanationSheet extends StatelessWidget {
  const PermissionExplanationSheet({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;

  static Future<bool> show(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
    required String actionLabel,
  }) async =>
      await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        useSafeArea: true,
        builder: (_) => PermissionExplanationSheet(
          icon: icon,
          title: title,
          message: message,
          actionLabel: actionLabel,
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(radius: 28, child: Icon(icon, size: 28)),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(actionLabel),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('暂不使用'),
        ),
      ],
    ),
  );
}
