import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_widget/markdown_widget.dart';

/// 自定义代码块组件，带有复制按钮
class CodeBlockWithCopyButton extends StatelessWidget {
  final String text;
  final String language;

  const CodeBlockWithCopyButton({
    super.key,
    required this.text,
    required this.language,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // 使用主题兼容的颜色
    final bgColor = isDark 
        ? const Color(0xFF1E1E1E)
        : const Color(0xFFF5F5F5);
    final textColor = isDark 
        ? const Color(0xFFD4D4D4)
        : const Color(0xFF24292E);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isDark
              ? const Color(0xFF3E3E3E)
              : const Color(0xFFE1E4E8),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 代码块头部（语言标签和复制按钮）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? const Color(0xFF3E3E3E)
                      : const Color(0xFFE1E4E8),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 语言标签
                Text(
                  language.isEmpty ? 'Code' : language,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.colorScheme.onSurface.withOpacity(0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                // 复制按钮
                InkWell(
                  onTap: () => _copyToClipboard(context),
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.copy_rounded,
                          size: 14,
                          color: theme.colorScheme.onSurface.withOpacity(0.5),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '复制',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 代码内容
          Padding(
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.5,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(BuildContext context) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('已复制到剪贴板'),
        behavior: SnackBarBehavior.floating,
        width: 200,
        duration: Duration(seconds: 2),
      ),
    );
  }
}

/// 自定义 Markdown Widget，代码块带有复制按钮
class MarkdownWidgetWithCopyButton extends StatelessWidget {
  final String data;
  final MarkdownConfig? config;
  final bool selectable;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  const MarkdownWidgetWithCopyButton({
    super.key,
    required this.data,
    this.config,
    this.selectable = false,
    this.shrinkWrap = false,
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    // 使用正则表达式提取所有代码块
    // 不要求最后的换行符，确保能匹配 AI 生成的代码块
    final codeBlockRegex = RegExp(r'```(\w*)\n([\s\S]*?)```', multiLine: true, dotAll: true);
    final matches = codeBlockRegex.allMatches(data);
    
    if (matches.isEmpty) {
      // 没有代码块，直接使用原始 MarkdownWidget
      return MarkdownWidget(
        data: data,
        config: config,
        selectable: selectable,
        shrinkWrap: shrinkWrap,
        physics: physics,
      );
    }
    
    // 有代码块，需要自定义渲染
    final parts = <Widget>[];
    int lastIndex = 0;
    
    for (final match in matches) {
      // 添加代码块前的文本
      if (match.start > lastIndex) {
        final beforeText = data.substring(lastIndex, match.start);
        if (beforeText.trim().isNotEmpty) {
          parts.add(
            MarkdownWidget(
              data: beforeText,
              config: config,
              selectable: selectable,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
            ),
          );
        }
      }
      
      // 添加代码块
      final language = match.group(1) ?? '';
      final code = match.group(2) ?? '';
      parts.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: CodeBlockWithCopyButton(
            text: code,
            language: language,
          ),
        ),
      );
      
      lastIndex = match.end;
    }
    
    // 添加最后的文本
    if (lastIndex < data.length) {
      final afterText = data.substring(lastIndex);
      if (afterText.trim().isNotEmpty) {
        parts.add(
          MarkdownWidget(
            data: afterText,
            config: config,
            selectable: selectable,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
          ),
        );
      }
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: parts,
    );
  }
}
