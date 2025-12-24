import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/system_prompt_service.dart';
import '../services/builtin_prompt_service.dart';
import '../models/system_prompt.dart';

final systemPromptServiceProvider = Provider<SystemPromptService>((ref) => SystemPromptService());

final builtinPromptServiceProvider = Provider<BuiltinPromptService>((ref) => BuiltinPromptService());

final builtinPromptsProvider = FutureProvider<List<SystemPrompt>>((ref) async {
  final service = ref.watch(builtinPromptServiceProvider);
  return await service.loadAllBuiltinPrompts();
});

final systemPromptsProvider = FutureProvider<List<SystemPrompt>>((ref) async {
  final userPrompts = await ref.watch(systemPromptServiceProvider).getAllPrompts();
  final builtinPrompts = await ref.read(builtinPromptsProvider.future);
  return [...builtinPrompts, ...userPrompts];
});

final enabledSystemPromptsProvider = FutureProvider<List<SystemPrompt>>((ref) async {
  final prompts = await ref.watch(systemPromptsProvider.future);
  return prompts.where((p) => p.isEnabled).toList();
});