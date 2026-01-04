# Engineai_Release

一个极简的 LLM、VL 和图像生成聊天软件，用于替代复杂臃肿的聊天应用。

---

## 📖 介绍

Engineai_Release 是一个功能精简但强大的 AI 对话工具，专注于提供核心的 AI 交互能力，无冗余功能。

**核心功能：**

- **多模态对话**：支持 OpenAI API 兼容接口的 LLM 模型对话聊天
- **视觉理解**：集成 VL 模型，支持多图识别和理解
- **图像生成**：支持图像生成模型，包括多图参考和历史图片标记功能
- **图像编辑**：提供简单的图片标注、编辑功能，可作为参考素材
- **MCP 接口**：可对接 streamable-http 协议，扩展知识库能力
- **主题定制**：多种深色和浅色主题可选
- **跨平台**：支持 Web 和 macOS（M2 及以上 ARM 架构）

---

## 🏗️ 架构

### 技术栈
- **前端框架**：Flutter
- **状态管理**：本地数据持久化（Hive、SharedPreferences）
- **平台支持**：Web、macOS（ARM 架构）

### 系统架构
```
┌─────────────────────────────────────┐
│         Flutter Application         │
├─────────────────────────────────────┤
│  ┌──────────┐  ┌──────────┐        │
│  │   LLM    │  │    VL    │        │
│  │  Models  │  │  Models  │        │
│  └──────────┘  └──────────┘        │
│  ┌──────────┐  ┌──────────┐        │
│  │  Image   │  │   MCP    │        │
│  │  Gen.    │  │ Interface│        │
│  └──────────┘  └──────────┘        │
├─────────────────────────────────────┤
│     API Layer                       │
│  - OpenAI API Compatible            │
│  - OpenRouter & DMXAPI              │
│  - Streamable-HTTP (MCP)            │
└─────────────────────────────────────┘
```

### API 兼容性
- OpenAI API 兼容接口
- OpenRouter 接口
- DMXAPI 接口
- MCP streamable-http 协议

---

## 🚀 使用

### 环境要求
- Flutter SDK
- macOS 版本需要 M2 或更新版本的 ARM 架构（不支持 Intel 芯片）

### 安装依赖
```bash
flutter pub get
```

### 运行应用

#### Web 版本
```bash
# 开发模式
flutter run -d chrome

# 指定端口运行（推荐用于数据持久化）
flutter run -d chrome --web-port=8080
```

**Web 数据持久化说明：**

默认情况下，`flutter run -d chrome` 会创建临时 Chrome 配置文件，导致本地数据（Hive、SharedPreferences）在重启后丢失。

如需在开发过程中持久化数据：

1. 使用固定端口运行：
   ```bash
   flutter run -d chrome --web-port=8080
   ```
2. 在你的主 Chrome 浏览器（非自动实例）中打开 [http://localhost:8080](http://localhost:8080)

数据将保存在浏览器的本地存储中。

#### macOS 版本
```bash
# 开发模式
flutter run -d macos

# 发布模式
flutter run -d macos --release
```

---

## 📸 功能预览

### LLM & VL 对话
<img src="./doc/image/image20251223010607.png" width="350px">

### 图像生成
<img src="./doc/image/imagen20251222005636.png" width="350px">

### 多图参考与生成
<img src="./doc/image/20251228103524_800_213.jpg" width="350px">

### 设置页面
<img src="./doc/image/Snipaste_2025-12-28_11-02-13.png" width="350px">

---

## 💡 备注

- **个人使用**：除了替代大软件，还有是为了简单做图像的一些应用更方便
- **知识库扩展**：可以连接 MCP，没有必要写个连接，现在很多无代码给 MCP 接口的框架，很方便
- **问题反馈**：有什么 bug 请提交到问题中，会尽快解决

---

## 📝 提交代码

```bash
git push https://github.com/code-2-art/Engineai.git main
```

