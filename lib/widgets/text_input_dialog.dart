import 'package:flutter/material.dart';

/// Owns its text controller for exactly as long as the dialog is mounted.
///
/// Keeping the controller inside the dialog avoids disposing it while the
/// route's exit animation is still removing text-field dependencies.
class TextInputDialog extends StatefulWidget {
  const TextInputDialog({
    required this.title,
    required this.cancelLabel,
    required this.submitLabel,
    this.hintText,
    this.initialValue,
    this.maxLength = 100,
    super.key,
  });

  final String title;
  final String cancelLabel;
  final String submitLabel;
  final String? hintText;
  final String? initialValue;
  final int maxLength;

  @override
  State<TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<TextInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: widget.maxLength,
        decoration: InputDecoration(hintText: widget.hintText),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }
}
