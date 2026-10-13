import 'package:flutter/material.dart';

class RecordingQuickActions extends StatelessWidget {
  const RecordingQuickActions({
    required this.onPhoto,
    required this.onHighlight,
    required this.onQuestion,
    required this.onChapter,
    required this.onNote,
    super.key,
  });

  final VoidCallback onPhoto;
  final VoidCallback onHighlight;
  final VoidCallback onQuestion;
  final VoidCallback onChapter;
  final VoidCallback onNote;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 600 ? 3 : 2;
      final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
      final height = 52 + MediaQuery.textScalerOf(context).scale(20);
      final actions = <Widget>[
        _ActionButton(
          icon: Icons.add_photo_alternate_outlined,
          label: '拍照 / 相册',
          onPressed: onPhoto,
          primary: true,
        ),
        _ActionButton(
          icon: Icons.star_rounded,
          label: '重点',
          onPressed: onHighlight,
        ),
        _ActionButton(
          icon: Icons.help_outline_rounded,
          label: '没听懂',
          onPressed: onQuestion,
        ),
        _ActionButton(
          icon: Icons.bookmark_add_outlined,
          label: '章节',
          onPressed: onChapter,
        ),
        _ActionButton(
          icon: Icons.edit_note_rounded,
          label: '备注',
          onPressed: onNote,
        ),
      ];
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final action in actions)
            SizedBox(width: width, height: height, child: action),
        ],
      );
    },
  );
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 26),
        const SizedBox(width: 9),
        Flexible(
          child: Text(
            label,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      label: label,
      child: primary
          ? FilledButton(onPressed: onPressed, child: child)
          : FilledButton.tonal(onPressed: onPressed, child: child),
    );
  }
}
