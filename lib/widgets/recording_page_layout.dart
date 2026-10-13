import 'package:flutter/material.dart';

/// One outer scroll surface keeps controls reachable in landscape and split view.
class RecordingPageLayout extends StatelessWidget {
  const RecordingPageLayout({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Scrollbar(
      child: ListView(
        key: const PageStorageKey('recording-page-scroll'),
        padding: EdgeInsets.fromLTRB(
          ((constraints.maxWidth - 900) / 2).clamp(0.0, double.infinity),
          0,
          ((constraints.maxWidth - 900) / 2).clamp(0.0, double.infinity),
          24,
        ),
        children: children,
      ),
    ),
  );
}
