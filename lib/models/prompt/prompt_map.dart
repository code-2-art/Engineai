import '../system_prompt.dart';
import 'research/physician.dart';
import 'video/wan_shot.dart';
import 'video/flux.dart';
import 'music/music_udio.dart';

/// 聊天系统预定义提示词映射
/// 用于提供给系统提示词列表的选择
Map<String, SystemPrompt> getChatPromptMap() {
  return {
    'default': SystemPrompt(
      id: 'default',
      name: '默认聊天助手',
        content: '''你是一个友好且有帮助的聊天助手。
请根据用户的查询提供准确、有用的回答。
保持对话自然流畅，并适时询问以澄清需求。避免提供结构化文本输出''',
    ),
    'physician': SystemPrompt(
      id: 'physician',
      name: '家庭医生',
      content: physician,
    ),
    'wan_story_shot': SystemPrompt(
      id: 'wan_story_shot',
      name: '镜头语言',
      content: wan_story_shot,
    ),
    'fluxd1': SystemPrompt(
      id: 'fluxd1',
      name: '图片生成',
      content: flux_syspromt,
    ),
    'music_udio': SystemPrompt(
      id: 'music_udio',
      name: '背景音乐',
      content: trailer_music_udio,
    ),
  };
}