import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import '../../theme/theme.dart';
import 'ai_chat.dart';
import 'package:forui/forui.dart';
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
class WritingPage extends ConsumerStatefulWidget {
  const WritingPage({super.key});

  @override
  ConsumerState<WritingPage> createState() => _WritingPageState();
}

class _WritingPageState extends ConsumerState<WritingPage> {
  late EditorState editorState;
  double _splitterPosition = 0.6;
  String? _savePath;
  DateTime? _lastSaved;
  Timer? _saveTimer;
  late SharedPreferences _prefs;

  @override
  void initState() {
    super.initState();
    editorState = EditorState.blank();
    _initPrefs();
  }


  @override
  void dispose() {
    _saveTimer?.cancel();
    editorState.dispose();
    super.dispose();
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    _savePath = _prefs.getString('writing_save_path');
    if (mounted) {
      setState(() {});
    }
    _saveTimer = Timer.periodic(const Duration(seconds: 3), (_) => _autoSave());
  }


  Future<void> _autoSave() async {
    if (_savePath == null || !mounted) return;
    try {
      final buffer = StringBuffer();
      void traverse(Node? node) {
        if (node == null) return;
        buffer.write(node.delta?.toPlainText() ?? '');
        for (final child in node.children) {
          traverse(child);
        }
      }
      traverse(editorState.document.root);
      final md = buffer.toString();
      await File(_savePath!).writeAsString(md);
      if (mounted) {
        _lastSaved = DateTime.now();
        setState(() {});
      }
    } catch (e) {
      print('保存失败: $e');
    }
  }

  void _selectSaveDir() async {
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath != null && mounted) {
      _savePath = '$dirPath/writing.md';
      await _prefs.setString('writing_save_path', _savePath!);
      await _autoSave();
      setState(() {});
    }
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
              child: Column(
                children: [
                  Container(
                    height: 48,
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _savePath != null ? _savePath!.split('/').last : '未选择保存路径',
                            style: Theme.of(context).textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.folder_open),
                          onPressed: _selectSaveDir,
                          tooltip: '选择保存文件夹',
                        ),
                        if (_lastSaved != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Text(
                              '保存于: ${_lastSaved!.toLocal().toString().substring(5, 16)}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.green),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
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
                ],
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