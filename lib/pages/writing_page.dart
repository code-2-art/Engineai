import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import '../../theme/theme.dart';
import 'ai_chat.dart';
import 'package:forui/forui.dart';

class WritingPage extends ConsumerStatefulWidget {
  const WritingPage({super.key});

  @override
  ConsumerState<WritingPage> createState() => _WritingPageState();
}

class _WritingPageState extends ConsumerState<WritingPage> {
  late EditorState editorState;
  double _splitterPosition = 0.6;

  @override
  void initState() {
    super.initState();
    editorState = EditorState.blank();
  }


  @override
  void dispose() {
    editorState.dispose();
    super.dispose();
  }
  


  
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final dividerWidth = 10.0;
        final minPanelWidth = 300.0;
        final splitterPos = (_splitterPosition).clamp(minPanelWidth / constraints.maxWidth, 1.0 - minPanelWidth / constraints.maxWidth);
        final leftWidth = constraints.maxWidth * splitterPos - dividerWidth / 2;
        final rightWidth = constraints.maxWidth - leftWidth - dividerWidth;
        return Row(
          children: [
            SizedBox(
              width: leftWidth,
              height: double.infinity,
              child: AppFlowyEditor(
                editorState: editorState,
                editorStyle: EditorStyle(
                  padding: const EdgeInsets.all(16.0),
                  cursorColor: Theme.of(context).colorScheme.primary,
                  dragHandleColor: Colors.transparent,
                  selectionColor: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  textStyleConfiguration: TextStyleConfiguration(
                    text: TextStyle(
                      fontSize: 16.0,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    bold: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  textSpanDecorator: null,
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) {
                setState(() {
                  final delta = details.delta.dx / constraints.maxWidth;
                  final minPanelWidth = 300.0;
                  _splitterPosition += delta;
                  _splitterPosition = _splitterPosition.clamp(minPanelWidth / constraints.maxWidth, 1.0 - minPanelWidth / constraints.maxWidth);
                });
              },
              child: Container(
                width: 10.0,
                height: double.infinity,
                child: VerticalDivider(
                  thickness: 1,
                  color: Theme.of(context).colorScheme.outline.withOpacity(0.5),
                ),
              ),
            ),
            SizedBox(
              width: rightWidth,
              height: double.infinity,
              child: ClipRect(
                child: const AiChat(),
              ),
            ),
          ],
        );
      },
    );
  }
}