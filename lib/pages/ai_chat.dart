import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import '../theme/theme.dart';
import '../services/llm_provider.dart';
import '../services/mcp_provider.dart';
import 'package:mcp_client/mcp_client.dart' as mcp;
import '../models/chat_session.dart';
import '../services/session_provider.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/code_block_widget.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'settings_page.dart';
import '../services/shared_prefs_service.dart';
import '../models/system_prompt.dart';
import '../services/system_prompt_service.dart';
import '../services/generation_task_manager.dart';
import '../models/generation_task.dart';
import '../services/notification_provider.dart';

final currentResponseProvider = StateProvider<String>((ref) => '');

class AiChat extends ConsumerStatefulWidget {
  const AiChat({super.key});

  @override
  ConsumerState<AiChat> createState() => _AiChatState();
}

class _AiChatState extends ConsumerState<AiChat> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  StreamSubscription<String>? _responseSubscription;
  List<String> _imageBase64s = [];
  String? _currentTaskId;

  @override
  void initState() {
    super.initState();
    print('=== AI CHAT INITSTATE START ===');
    print('=== AI CHAT INITSTATE DONE ===');
    // 检查是否有运行中的任务
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkRunningTask();
    });
  }

  void _checkRunningTask() {
    final taskManager = ref.read(taskManagerProvider);
    final runningTask = taskManager.getRunningTask(TaskType.chat);
    if (runningTask != null) {
      _currentTaskId = runningTask.id;
      setState(() {
        _isSending = true;
      });
      // 监听任务状态
      _listenToTask(runningTask.id);
    }
  }

  void _listenToTask(String taskId) {
    final taskManager = ref.read(taskManagerProvider);
    taskManager.watchTask(taskId).listen((task) {
      if (!mounted) return;
      
      // 更新当前响应
      if (task.currentResponse != null) {
        ref.read(currentResponseProvider.notifier).state = task.currentResponse!;
        _scrollToBottom();
      }
      
      // 处理任务完成
      if (task.status == TaskStatus.completed) {
        _addAIMessage();
        setState(() {
          _isSending = false;
        });
        _currentTaskId = null;
      }
      
      // 处理任务失败
      if (task.status == TaskStatus.failed) {
        ref.read(notificationServiceProvider).showError('生成失败: ${task.error}');
        setState(() {
          _isSending = false;
        });
        _currentTaskId = null;
      }
    });
  }

  @override
  void dispose() {
    // 不再取消任务，只取消页面级别的订阅
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _addAIMessage() async {
    final fullResponse = ref.read(currentResponseProvider);
    if (fullResponse.isEmpty) return;
    final sessionId = ref.read(currentSessionIdProvider);
    if (sessionId == null) return;
    final currentModel = ref.read(chatCurrentModelProvider);
    final session = ref.read(sessionListProvider).firstWhere((s) => s.id == sessionId);
    final promptName = _getPromptName(session.systemPrompt);
    final aiMessage = Message(
      isUser: false,
      text: fullResponse,
      sender: currentModel,
      promptName: promptName,
    );
    await ref.read(sessionListProvider.notifier).updateSession(
      session.copyWith(messages: [...session.messages, aiMessage])
    );
    ref.read(currentResponseProvider.notifier).state = '';
    _scrollToBottom();
  }

  void _stopGenerating() {
    print('AiChat: Stopping generation...');
    if (_currentTaskId != null) {
      final taskManager = ref.read(taskManagerProvider);
      taskManager.cancelTask(_currentTaskId!);
    }
    _addAIMessage();
    if (mounted) {
      setState(() {
        _isSending = false;
      });
    }
    if (mounted) {
      ref.read(notificationServiceProvider).showInfo('已停止生成');
    }
  }

  void _resetSendingState() {
    ref.read(currentResponseProvider.notifier).state = '';
    if (mounted) {
      setState(() {
        _isSending = false;
      });
    }
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result != null && result.files.isNotEmpty) {
      for (final file in result.files) {
        Uint8List originalBytes;
        if (file.bytes != null) {
          originalBytes = file.bytes!;
        } else {
          final path = file.path;
          if (path == null) continue;
          originalBytes = await File(path).readAsBytes();
        }
        Uint8List bytes;
        try {
          final image = img.decodeImage(originalBytes);
          if (image != null) {
            final resized = img.copyResize(image, width: 1024);
            bytes = img.encodePng(resized, level: 0);
          } else {
            bytes = originalBytes;
          }
        } catch (e) {
          print('图片压缩失败: $e，使用原图');
          bytes = originalBytes;
        }
        _imageBase64s.add(base64Encode(bytes));
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _sendMessage() async {
    print('=== AI CHAT SEND MESSAGE START ===');
    final prompt = _controller.text.trim();
    if (prompt.isEmpty || _isSending) return;

    print('AiChat: _sendMessage started. Prompt: $prompt');

    try {
      var sessionId = ref.read(currentSessionIdProvider);
      print('AiChat: current sessionId: $sessionId');
      if (sessionId == null) {
        print('AiChat: Creating new session...');
        final newSession = await ref.read(sessionListProvider.notifier).createNewSession();
        sessionId = newSession.id;
        ref.read(currentSessionIdProvider.notifier).setSessionId(sessionId);
        print('AiChat: New session created: $sessionId');
      }

      final currentSession = ref.read(sessionListProvider).firstWhere((s) => s.id == sessionId);
      
      final bool supportsVision = await ref.read(chatSupportsVisionProvider.future);
      List<Map<String, dynamic>>? userContentParts;
      if (supportsVision && _imageBase64s.isNotEmpty) {
        userContentParts = [{"type": "text", "text": prompt}];
        for (final b64 in _imageBase64s) {
          userContentParts!.add({
            "type": "image_url",
            "image_url": {"url": "data:image/png;base64,$b64"}
          });
        }
      }
      final userMessage = Message(isUser: true, text: prompt, sender: '我', contentParts: userContentParts);
      final updatedMessages = [...currentSession.messages, userMessage];
      
      String title = currentSession.title;
      if (currentSession.messages.isEmpty) {
        final now = DateTime.now();
        final timestamp = '${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
        final shortPrompt = prompt.length > 20 ? '${prompt.substring(0, 20)}...' : prompt;
        title = '$timestamp - $shortPrompt';
      }

      await ref.read(sessionListProvider.notifier).updateSession(
        currentSession.copyWith(messages: updatedMessages, title: title)
      );

      _controller.clear();
      _imageBase64s.clear();
      _scrollToBottom();

      ref.read(currentResponseProvider.notifier).state = '';

      // Prune history based on separators (history before user message)
      final fullHistory = currentSession.messages;
      final lastClearIndex = fullHistory.lastIndexWhere((m) => m.isSystem);
      final effectiveHistory = lastClearIndex == -1
          ? fullHistory
          : fullHistory.sublist(lastClearIndex + 1);
    
      // 检查是否选择了 MCP 服务器，如果没有选择则跳过 MCP 检查
      final currentMcp = ref.read(currentMcpProvider);
      mcp.Client? mcpClient;
      if (currentMcp.isNotEmpty) {
        print('AiChat: 检查 MCP... 当前选择的 MCP: $currentMcp');
        final mcpClientFuture = ref.read(currentMcpClientProvider.future);
        try {
          mcpClient = await mcpClientFuture;
        } catch (e) {
          print('AiChat: MCP client 加载失败: $e');
        }
      } else {
        print('AiChat: 未选择 MCP 服务器，跳过 MCP 检查');
      }
      
      // 创建任务
      final taskManager = ref.read(taskManagerProvider);
      final taskId = await taskManager.createChatTask(
        sessionId!,
        prompt,
        userContentParts,
        currentSession.systemPrompt,
        ref,
      );
      
      _currentTaskId = taskId;
      setState(() {
        _isSending = true;
      });
      
      // 监听任务状态
      _listenToTask(taskId);
      
      return;
      
      if (mcpClient != null) {
        print('AiChat: MCP client capabilities: ${mcpClient.serverCapabilities}');
        print('AiChat: MCP serverInfo: ${mcpClient.serverInfo}');
        
        // 检查可用工具和提示词
        List<mcp.Tool> toolsResp = [];
        try {
          toolsResp = await mcpClient.listTools();
          print('AiChat: MCP available tools: ${toolsResp.map((t) => t.name).toList()}');
          for (final tool in toolsResp) {
            print('AiChat: Tool ${tool.name}: ${tool.description}');
            print('AiChat: Tool ${tool.name} inputSchema: ${tool.inputSchema}');
          }

                  
                
        } catch (e) {
          print('AiChat: List tools error: $e');
        }
        
        try {
          final promptsResp = await mcpClient.listPrompts();
          print('AiChat: MCP available prompts: ${promptsResp.map((p) => p.name).toList()}');
        } catch (e) {
          print('AiChat: List prompts error: $e');
        }
        
        // LLM-based automatic MCP tool calling (通用，无需特定提示)
        if (toolsResp.isNotEmpty) {
          final toolsDesc = toolsResp.map((t) => '- **${t.name}**: ${t.description}\n  输入 schema: ```json\n${JsonEncoder.withIndent('  ').convert(t.inputSchema)}```').join('\n\n');
          
          final decidePrompt = '''
分析用户查询："$prompt"

可用工具：
$toolsDesc

任务：决定是否调用工具来回答查询。

输出**仅**有效JSON，无任何其他文字：

- 需要工具：{"tool": "tool_name", "params": {"param_name": "value", ...}}
- 不需要：{"tool": null}

参数必须符合工具 schema。
          ''';
          
          print('AiChat: LLM deciding tool use...');
          final decideLlm = await ref.read(chatLlmProvider.future);
          String decideFull = '';
          await for (final delta in decideLlm.generateStream([], decidePrompt)) {
            decideFull += delta;
          }
          print('AiChat: Tool decide: $decideFull');
          
          Map<String, dynamic>? decideJson;
          try {
            decideJson = json.decode(decideFull);
          } catch (e) {
            print('AiChat: Decide JSON parse error: $e');
          }
          
          if (decideJson != null && decideJson['tool'] != null) {
            String currentToolName = decideJson['tool'] as String;
            Map<String, dynamic> currentParams = decideJson['params'] as Map<String, dynamic>;
            
            const int maxRetries = 3;
            bool toolSuccess = false;
            String toolResp = '';
            
            for (int retry = 0; retry < maxRetries; retry++) {
              print('AiChat: Tool call attempt ${retry + 1}/$maxRetries: $currentToolName with $currentParams');
              try {
                final toolResult = await mcpClient.callTool(currentToolName, currentParams);
                
                if (toolResult.content is mcp.TextContent) {
                  toolResp = (toolResult.content as mcp.TextContent).text;
                } else if (toolResult.content is List<mcp.Content>) {
                  toolResp = toolResult.content.whereType<mcp.TextContent>().map((c) => c.text).join('\n');
                }
                
                if (toolResp.isNotEmpty) {
                  toolSuccess = true;
                  break;
                }
              } catch (e) {
                print('AiChat: Tool call failed (attempt ${retry + 1}): $e');
                
                if (retry == maxRetries - 1) break;
                
                // LLM retry decide
                final retryDecPrompt = '''
上次工具调用失败：$e

原用户查询：$prompt

当前工具：$currentToolName

当前参数：${json.encode(currentParams)}

请调整参数或选择其他工具，输出新JSON。

$decidePrompt
                '''.trim();
                
                String retryFull = '';
                await for (final delta in decideLlm.generateStream([], retryDecPrompt)) {
                  retryFull += delta;
                }
                
                print('AiChat: Retry decide: $retryFull');
                
                Map<String, dynamic>? retryJson;
                try {
                  retryJson = json.decode(retryFull);
                } catch (parseE) {
                  print('AiChat: Retry JSON parse error: $parseE');
                  continue;
                }
                
                if (retryJson != null && retryJson['tool'] != null) {
                  currentToolName = retryJson['tool'] as String;
                  final retryParams = retryJson['params'];
                  if (retryParams is Map<String, dynamic>) {
                    currentParams = retryParams;
                  }
                }
              }
            }
            
            if (!toolSuccess || toolResp.isEmpty) {
              if (mounted) {
                ref.read(notificationServiceProvider).showError('工具调用多次失败，请检查参数或网络');
              }
              return;
            }
            
            final analysisPrompt = '''
用户查询：$prompt

工具调用：$currentToolName(${json.encode(currentParams)})

工具结果：
$toolResp

请基于工具结果，给出完整、自然的中文回答。
            '''.trim();
            
            print('AiChat: Starting tool result analysis stream...');
            if (!mounted) return;
            
            setState(() {
              _isSending = true;
            });
            
            final llm = await ref.read(chatLlmProvider.future);
            final textHistory = effectiveHistory.map((msg) => Message(
              isUser: msg.isUser,
              text: _getDisplayText(msg),
              sender: msg.sender,
              timestamp: msg.timestamp,
            )).toList();
            final stream = llm.generateStream(
              textHistory,
              analysisPrompt,
              systemPrompt: currentSession.systemPrompt ?? ''
            );
            
            _responseSubscription?.cancel();
            _responseSubscription = stream.listen(
              (delta) {
                if (delta.isEmpty || !mounted) return;
                final current = ref.read(currentResponseProvider);
                ref.read(currentResponseProvider.notifier).state = current + delta;
                _scrollToBottom();
              },
              onDone: () {
                print('AiChat: Tool analysis stream finished.');
                _addAIMessage();
                if (mounted) {
                  setState(() {
                    _isSending = false;
                  });
                }
              },
              onError: (e) {
                print('AiChat: Tool analysis stream error: $e');
                if (mounted) {
                  ref.read(notificationServiceProvider).showError('分析失败: $e');
                }
                _resetSendingState();
              },
            );
            return;
          }
        }
        
        final supportsSampling = mcpClient.serverCapabilities?.sampling ?? false;
        print('AiChat: Server supports sampling: $supportsSampling');
        
        if (supportsSampling) {
          print('AiChat: 使用 MCP 生成响应');
          try {
            List<mcp.Message> mcpHistory = [];
            if (currentSession.systemPrompt != null && currentSession.systemPrompt!.isNotEmpty) {
              mcpHistory.add(mcp.Message(
                role: 'system',
                content: mcp.TextContent(text: currentSession.systemPrompt!),
              ));
            }
            for (final msg in effectiveHistory) {
              final role = msg.isUser ? 'user' : 'assistant';
              final text = _getDisplayText(msg);
              mcpHistory.add(mcp.Message(
                role: role,
                content: mcp.TextContent(text: text),
              ));
            }
            mcpHistory.add(mcp.Message(
              role: 'user',
              content: mcp.TextContent(text: prompt),  // 暂不支持图片
            ));

            final request = mcp.CreateMessageRequest(
              messages: mcpHistory,
              maxTokens: 4096,
              temperature: 0.7,
            );

            final result = await mcpClient.createMessage(request);

            String fullResponse = '';
            if (result.content is mcp.TextContent) {
              fullResponse = (result.content as mcp.TextContent).text;
            } else {
              for (final content in (result.content as List<mcp.Content>)) {
                if (content is mcp.TextContent) {
                  fullResponse += content.text;
                }
              }
            }

            ref.read(currentResponseProvider.notifier).state = fullResponse;
            _addAIMessage();
            if (mounted) {
              setState(() {
                _isSending = false;
              });
            }
            return;
          } catch (e) {
            print('AiChat: MCP 生成失败: $e');
            if (mounted) {
              ref.read(notificationServiceProvider).showWarning('MCP 生成失败，fallback 到 LLM: $e');
            }
          }
        } else {
          print('AiChat: MCP sampling not supported, fallback to LLM');
        }
      }
    
    } catch (e) {
      print('AiChat: _sendMessage error: $e');
      if (mounted) {
        ref.read(notificationServiceProvider).showError('发送失败: $e');
      }
      _resetSendingState();
    }
  }

  Future<void> _exportToMarkdown() async {
    final sessionId = ref.read(currentSessionIdProvider);
    if (sessionId == null) return;
    final session = ref.read(sessionListProvider).firstWhere((s) => s.id == sessionId);
    if (session.messages.isEmpty) return;
  
    final md = ref.read(chatHistoryServiceProvider).convertToMarkdown(session);
    final safeName = session.title.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: '保存聊天记录',
      fileName: '${safeName}.md',
      type: FileType.custom,
      allowedExtensions: ['md'],
    );
  
    if (outputFile != null) {
      final file = File(outputFile);
      await file.writeAsString(md);
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('导出成功'),
            content: Text('已保存到: ${file.path}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    }
  }

  String _getDisplayText(Message message) {
    if (message.contentParts != null) {
      final texts = message.contentParts!.where((p) => p['type'] == 'text').map((p) => p['text'] as String);
      return texts.join('\n');
    }
    return message.text;
  }

  String? _getPromptName(String? systemPromptContent) {
    if (systemPromptContent == null || systemPromptContent.isEmpty) {
      return null;
    }
    final prompts = ref.read(enabledSystemPromptsProvider);
    final prompt = prompts.firstWhere(
      (p) => p.content == systemPromptContent,
      orElse: () => prompts.firstWhere(
        (p) => p.content.contains(systemPromptContent) || systemPromptContent.contains(p.content),
        orElse: () => SystemPrompt(name: '', content: ''),
      ),
    );
    return prompt.name.isNotEmpty ? prompt.name : null;
  }

  void _showImageViewer(Uint8List bytes) {
    showDialog(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black54,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ),
          body: GestureDetector(
            onDoubleTap: () => Navigator.of(dialogContext).pop(),
            child: Center(
              child: InteractiveViewer(
                panEnabled: true,
                boundaryMargin: const EdgeInsets.all(20),
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.memory(
                  bytes,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImagePreview(Message message) {
    if (message.contentParts == null || !message.isUser) return const SizedBox.shrink();
    List<Widget> imageWidgets = [];
    for (final part in message.contentParts!) {
      if (part['type'] == 'image_url') {
        final url = part['image_url']['url'] as String?;
        if (url != null && url.startsWith('data:image')) {
          final base64Str = url.split(',')[1];
          final bytes = base64Decode(base64Str);
          imageWidgets.add(
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: GestureDetector(
                  onTap: () => _showImageViewer(bytes),
                  onDoubleTap: () => _showImageViewer(bytes),
                  child: Image.memory(
                    bytes,
                    height: 240,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          );
        }
      }
    }
    if (imageWidgets.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: imageWidgets,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionId = ref.watch(currentSessionIdProvider);
    final currentResponse = ref.watch(currentResponseProvider);
    final sessions = ref.watch(sessionListProvider);
    
    final currentSession = sessionId != null 
        ? sessions.firstWhere((s) => s.id == sessionId, orElse: () => sessions.isNotEmpty ? sessions.first : ChatSession(id: '', title: '', messages: []))
        : null;
    final history = currentSession?.messages ?? [];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline, size: 20),
                  onPressed: () async {
                    final session = await ref.read(sessionListProvider.notifier).createNewSession();
                    ref.read(currentSessionIdProvider.notifier).setSessionId(session.id);
                  },
                  tooltip: '新对话',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.transparent,
                  ),
                ),
                const SizedBox(width: 8),
                Consumer(
                  builder: (context, ref, child) {
                    final collapsed = ref.watch(rightSidebarCollapsedProvider);
                    if (collapsed) {
                      return IconButton(
                        onPressed: () {
                          ref.read(rightSidebarCollapsedProvider.notifier).toggle();
                        },
                        icon: const Icon(Icons.history, size: 20),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.transparent,
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: (currentSession == null && currentResponse.isEmpty)
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 48, color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
                        const SizedBox(height: 16),
                        Text('开始新的对话吧', style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5))),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: history.length + (currentResponse.isNotEmpty ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index < history.length) {
                        final message = history[index];
                        if (message.isSystem) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
                            child: Row(
                              children: [
                                Expanded(child: Divider(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2), thickness: 1)),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Text(
                                    '上下文已清除',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Expanded(child: Divider(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.2), thickness: 1)),
                              ],
                            ),
                          );
                        }
                        final timeStr = "${message.timestamp.year}-${message.timestamp.month.toString().padLeft(2, '0')}-${message.timestamp.day.toString().padLeft(2, '0')} ${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}";
                        final displayText = _getDisplayText(message);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                          child: Column(
                            crossAxisAlignment: message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4, left: 4, right: 4),
                                child: Text(
                                  "${message.sender ?? (message.isUser ? '我' : 'AI')}${message.promptName != null ? ' • ${message.promptName}' : ''} • $timeStr",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                    fontWeight: FontWeight.w500,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              Align(
                                alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                                  ),
                                  child: Column(
                                    crossAxisAlignment: message.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: message.isUser ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.secondaryContainer,
                                          borderRadius: BorderRadius.circular(4),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.04),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Builder(
                                          builder: (context) {
                                            final colorScheme = Theme.of(context).colorScheme;
                                            final textColor = message.isUser
                                              ? colorScheme.onPrimaryContainer
                                              : colorScheme.onSecondaryContainer;
                                            final isDark = Theme.of(context).brightness == Brightness.dark;
                                            final config = isDark
                                                ? MarkdownConfig.darkConfig
                                                : MarkdownConfig.defaultConfig;
                                            return DefaultTextStyle(
                                              style: TextStyle(color: textColor),
                                              child: MarkdownWidgetWithCopyButton(
                                                data: displayText,
                                                config: config,
                                                selectable: true,
                                                shrinkWrap: true,
                                                physics: const NeverScrollableScrollPhysics(),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                      _buildImagePreview(message),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.copy_rounded, size: 14),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () {
                                              Clipboard.setData(ClipboardData(text: displayText));
                                              ref.read(notificationServiceProvider).showSuccess('已复制到剪贴板');
                                            },
                                            tooltip: '复制',
                                            style: IconButton.styleFrom(
                                              foregroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline_rounded, size: 14),
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            onPressed: () {
                                              if (sessionId != null) {
                                                ref.read(sessionListProvider.notifier).deleteMessage(sessionId, message.id);
                                              }
                                            },
                                            tooltip: '删除',
                                            style: IconButton.styleFrom(
                                              foregroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      } else {
                        final currentModel = ref.watch(chatCurrentModelProvider);
                        final promptName = _getPromptName(currentSession?.systemPrompt);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4, left: 4),
                                child: Text(
                                  "$currentModel${promptName != null ? ' • $promptName' : ''} • 正在输入...",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                                    fontWeight: FontWeight.w500,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width * 0.75,
                                  ),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.04),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: currentResponse.isEmpty
                                    ? Text(
                                        'AI 正在思考...',
                                        style: TextStyle(
                                          fontSize: 14,
                                          height: 1.5,
                                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                                          fontFamilyFallback: const ['Microsoft YaHei', 'SimSun', 'PingFang SC', 'Hiragino Sans GB', 'Noto Sans CJK SC', 'Arial Unicode MS'],
                                        ),
                                      )
                                    : Builder(
                                        builder: (context) {
                                          final textColor = Theme.of(context).colorScheme.onSecondaryContainer;
                                          final isDark = Theme.of(context).brightness == Brightness.dark;
                                          final config = isDark
                                              ? MarkdownConfig.darkConfig
                                              : MarkdownConfig.defaultConfig;
                                          return DefaultTextStyle(
                                            style: TextStyle(color: textColor),
                                            child: MarkdownWidgetWithCopyButton(
                                              data: currentResponse,
                                              config: config,
                                              selectable: true,
                                              shrinkWrap: true,
                                              physics: const NeverScrollableScrollPhysics(),
                                            ),
                                          );
                                        },
                                      ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_imageBase64s.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SizedBox(
                      height: 220,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _imageBase64s.length,
                        itemBuilder: (context, index) {
                          final b64 = _imageBase64s[index];
                          final bytes = base64Decode(b64);
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: SizedBox(
                              width: 150,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: GestureDetector(
                                        onTap: () => _showImageViewer(bytes),
                                        child: Image.memory(
                                          bytes,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      top: 4,
                                      right: 4,
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() {
                                            _imageBase64s.removeAt(index);
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            shape: BoxShape.circle,
                                          ),
                                          child: const Icon(
                                            Icons.close,
                                            size: 16,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        enabled: !_isSending,
                        decoration: InputDecoration(
                      hintText: _isSending ? 'AI 正在回复...' : '输入消息...',
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Consumer(
                              builder: (context, ref, child) {
                                final sessionId = ref.watch(currentSessionIdProvider);
                                final sessions = ref.watch(sessionListProvider);
                                ChatSession? currentSession;
                                if (sessionId != null) {
                                  try {
                                    currentSession = sessions.firstWhere((s) => s.id == sessionId);
                                  } catch (e) {
                                    currentSession = null;
                                  }
                                }
                                final hasPrompt = currentSession?.systemPrompt != null;
                                final currentPrompt = currentSession?.systemPrompt;
                                final prompts = ref.watch(enabledSystemPromptsProvider);
                                return FPopoverMenu(
                                  menuAnchor: Alignment.topCenter,
                                  childAnchor: Alignment.bottomCenter,
                                  menu: [
                                    FItemGroup(
                                      children: [
                                        FItem(title: const Text('不使用系统提示词'), suffix: currentPrompt == null ? Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary) : null, onPress: () async {
                                          var sid = ref.read(currentSessionIdProvider);
                                          if (sid == null) {
                                            final session = await ref.read(sessionListProvider.notifier).createNewSession();
                                            sid = session.id;
                                            ref.read(currentSessionIdProvider.notifier).setSessionId(sid);
                                          }
                                          ref.read(sessionListProvider.notifier).updateSessionSystemPrompt(sid, null);
                                          await ref.read(sharedPrefsServiceProvider).saveDefaultSystemPrompt(null);
                                        },
                                        ),
                                        ...prompts.map((p) => FItem(
                                          title: Text(p.name), suffix: currentPrompt == p.content ? Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary) : null, onPress: () async {
                                            var sid = ref.read(currentSessionIdProvider);
                                            if (sid == null) {
                                              final session = await ref.read(sessionListProvider.notifier).createNewSession();
                                              sid = session.id;
                                              ref.read(currentSessionIdProvider.notifier).setSessionId(sid);
                                            }
                                            ref.read(sessionListProvider.notifier).updateSessionSystemPrompt(sid, p.content);
                                            await ref.read(sharedPrefsServiceProvider).saveDefaultSystemPrompt(p.content);
                                          },
                                        )),
                                        FItem(
                                          prefix: const Icon(Icons.edit),
                                          title: const Text('管理提示词'),
                                          onPress: () {
                                            ref.read(selectedSectionProvider.notifier).state = SettingsSection.prompts;
                                            Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (context) => const SettingsPage(),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                  builder: (context, controller, child) => IconButton(
                                    key: ValueKey(hasPrompt),
                                    icon: Icon(
                                      hasPrompt ? Icons.description : Icons.description_outlined,
                                      size: 14,
                                      color: hasPrompt ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withOpacity(0.38),
                                    ),
                                    tooltip: hasPrompt ? '当前使用系统提示词' : '不使用系统提示词',
                                    constraints: const BoxConstraints(
                                      maxWidth: 32,
                                      maxHeight: 32,
                                    ),
                                    padding: EdgeInsets.zero,
                                    style: IconButton.styleFrom(
                                      shape: const CircleBorder(),
                                      hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                                    ),
                                    onPressed: controller.toggle,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            Consumer(
                              builder: (context, ref, child) {
                                final namesAsync = ref.watch(chatModelNamesProvider);
                                final currentModel = ref.watch(chatCurrentModelProvider);
                                return namesAsync.when(
                                  data: (names) {
                                    if (names.isEmpty) {
                                      return IconButton(
                                        icon: const Icon(Icons.model_training, size: 14),
                                        tooltip: '无可用模型',
                                        constraints: const BoxConstraints(maxWidth: 32, maxHeight: 32),
                                        padding: EdgeInsets.zero,
                                        style: IconButton.styleFrom(
                                          shape: const CircleBorder(),
                                          hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                                        ),
                                        onPressed: null,
                                      );
                                    }
                                    return FPopoverMenu(
                                      menuAnchor: Alignment.topCenter,
                                      childAnchor: Alignment.bottomCenter,
                                      menu: [
                                        FItemGroup(
                                          children: [
                                            ...names.map((name) => FItem(title: Text(name), suffix: currentModel == name ? Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary) : null, onPress: () {
                                              ref.read(chatCurrentModelProvider.notifier).state = name;
                                            },
                                            )),
                                            FItem(
                                              prefix: const Icon(Icons.model_training),
                                              title: const Text('管理模型'),
                                              onPress: () {
                                                ref.read(selectedSectionProvider.notifier).state = SettingsSection.models;
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (context) => const SettingsPage(),
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                      builder: (context, controller, child) => IconButton(
                                        icon: const Icon(Icons.model_training, size: 14),
                                        tooltip: '切换模型',
                                        constraints: const BoxConstraints(maxWidth: 32, maxHeight: 32),
                                        padding: EdgeInsets.zero,
                                        style: IconButton.styleFrom(
                                          shape: const CircleBorder(),
                                          hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                                        ),
                                        onPressed: controller.toggle,
                                      ),
                                    );
                                  },
                                  loading: () => const SizedBox(width: 32, height: 32),
                                  error: (err, stack) => IconButton(
                                    icon: const Icon(Icons.error_outline, size: 14, color: Colors.red),
                                    tooltip: '加载模型失败',
                                    constraints: const BoxConstraints(maxWidth: 32, maxHeight: 32),
                                    padding: EdgeInsets.zero,
                                    onPressed: null,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            Consumer(
                              builder: (context, ref, child) {
                                final currentMcp = ref.watch(currentMcpProvider);
                                final configsAsync = ref.watch(mcpConfigProvider);
                                return configsAsync.when(
                                  data: (servers) {
                                    if (servers.isEmpty) {
                                      return IconButton(
                                        icon: const Icon(Icons.extension_outlined, size: 14),
                                        tooltip: '无 MCP 服务器',
                                        constraints: const BoxConstraints(maxWidth: 32, maxHeight: 32),
                                        padding: EdgeInsets.zero,
                                        style: IconButton.styleFrom(
                                          shape: const CircleBorder(),
                                          hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                                        ),
                                        onPressed: null,
                                      );
                                    }
                                    return FPopoverMenu(
                                      menuAnchor: Alignment.topCenter,
                                      childAnchor: Alignment.bottomCenter,
                                      menu: [
                                        FItemGroup(
                                          children: [
                                            FItem(
                                              title: const Text('不使用 MCP'),
                                              suffix: currentMcp.isEmpty ? const Icon(Icons.check, size: 16, color: Colors.transparent) : null,
                                              onPress: () {
                                                ref.read(currentMcpProvider.notifier).state = '';
                                              },
                                            ),
                                            ...servers.map((server) => FItem(
                                              title: Text(server.name),
                                              suffix: currentMcp == server.name ? Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary) : null,
                                              onPress: () {
                                                ref.read(currentMcpProvider.notifier).state = server.name;
                                              },
                                            )),
                                            FItem(
                                              prefix: const Icon(Icons.settings),
                                              title: const Text('管理 MCP'),
                                              onPress: () {
                                                ref.read(selectedSectionProvider.notifier).state = SettingsSection.mcp;
                                                Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                    builder: (context) => const SettingsPage(),
                                                  ),
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                      builder: (context, controller, child) => IconButton(
                                        icon: Icon(
                                          Icons.extension,
                                          size: 14,
                                          color: currentMcp.isNotEmpty ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface.withOpacity(0.38),
                                        ),
                                        tooltip: currentMcp.isNotEmpty ? '当前 MCP: $currentMcp' : '选择 MCP 服务器',
                                        constraints: const BoxConstraints(maxWidth: 32, maxHeight: 32),
                                        padding: EdgeInsets.zero,
                                        style: IconButton.styleFrom(
                                          shape: const CircleBorder(),
                                          hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                                        ),
                                        onPressed: controller.toggle,
                                      ),
                                    );
                                  },
                                  loading: () => const SizedBox(width: 32, height: 32),
                                  error: (err, stack) => IconButton(
                                    icon: const Icon(Icons.error_outline, size: 14, color: Colors.red),
                                    tooltip: '加载 MCP 失败',
                                    constraints: const BoxConstraints(maxWidth: 32, maxHeight: 32),
                                    padding: EdgeInsets.zero,
                                    onPressed: null,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.cleaning_services_outlined, size: 14),
                              tooltip: '清除上下文',
                              constraints: const BoxConstraints(
                                maxWidth: 32,
                                maxHeight: 32,
                              ),
                              padding: EdgeInsets.zero,
                              style: IconButton.styleFrom(
                                shape: const CircleBorder(),
                                hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                              ),
                              onPressed: () async {
                                var localSessionId = ref.read(currentSessionIdProvider);
                                if (localSessionId == null) {
                                  final newSession = await ref.read(sessionListProvider.notifier).createNewSession();
                                  ref.read(currentSessionIdProvider.notifier).setSessionId(newSession.id);
                                  localSessionId = newSession.id;
                                }
                                ref.read(sessionListProvider.notifier).addSeparator(localSessionId!);
                                ref.read(notificationServiceProvider).showSuccess('上下文已清除');
                              },
                            ),
                            const SizedBox(width: 8),
                            Consumer(
                              builder: (context, ref, child) {
                                final supportsVisionAsync = ref.watch(chatSupportsVisionProvider);
                                return supportsVisionAsync.when(
                                  data: (supportsVision) {
                                    if (supportsVision && !_isSending) {
                                      return IconButton(
                                        icon: _imageBase64s.isNotEmpty
                                            ? Icon(Icons.image, size: 14, color: Theme.of(context).colorScheme.primary)
                                            : const Icon(Icons.add_photo_alternate_outlined, size: 14),
                                        tooltip: '上传图片',
                                        constraints: const BoxConstraints(maxWidth: 32, maxHeight: 32),
                                        padding: EdgeInsets.zero,
                                        style: IconButton.styleFrom(
                                          shape: const CircleBorder(),
                                          hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                                        ),
                                        onPressed: _pickImage,
                                      );
                                    } else {
                                      return const SizedBox.shrink();
                                    }
                                  },
                                  loading: () => const SizedBox(width: 32, height: 32),
                                  error: (err, stack) => const SizedBox.shrink(),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      suffixIcon: ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _controller,
                        builder: (context, value, child) {
                          return value.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  style: IconButton.styleFrom(
                                    shape: const CircleBorder(),
                                    hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                                  ),
                                  onPressed: () => _controller.clear(),
                                )
                              : const SizedBox.shrink();
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: _isSending ? _stopGenerating : _sendMessage,
                  icon: Icon(
                    _isSending ? Icons.stop : Icons.send_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  style: IconButton.styleFrom(
                    shape: const CircleBorder(),
                    backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                    hoverColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                    padding: EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  ],
),
);
  }
}