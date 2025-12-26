import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mcp_client/mcp_client.dart';
import 'package:collection/collection.dart';
import '../models/mcp_config.dart';
import 'mcp_storage_service.dart';

final currentMcpProvider = StateProvider<String>((ref) => '');

class McpConfigNotifier extends AsyncNotifier<List<McpServerConfig>> {
  final _storage = McpStorageService();

  @override
  Future<List<McpServerConfig>> build() async {
    return await _storage.readConfig();
  }

  Future<void> _save(List<McpServerConfig> configs) async {
    await _storage.saveConfig(configs);
  }

  Future<void> addServer(McpServerConfig config) async {
    final current = state.valueOrNull ?? [];
    if (current.any((c) => c.name == config.name)) {
      throw Exception('MCP server name already exists');
    }
    final newConfigs = [...current, config];
    state = AsyncValue.data(newConfigs);
    await _save(newConfigs);
  }

  Future<void> updateServer(McpServerConfig updated) async {
    final current = state.valueOrNull ?? [];
    final index = current.indexWhere((c) => c.name == updated.name);
    if (index == -1) return;
    final newConfigs = [...current];
    newConfigs[index] = updated;
    state = AsyncValue.data(newConfigs);
    await _save(newConfigs);
  }

  Future<void> removeServer(String name) async {
    final current = state.valueOrNull ?? [];
    final newConfigs = current.where((c) => c.name != name).toList();
    state = AsyncValue.data(newConfigs);
    await _save(newConfigs);
  }

  List<Map<String, dynamic>> exportToJson() {
    final configs = state.valueOrNull ?? [];
    return configs.map((c) => c.toJson()).toList();
  }

  Future<void> importFromJson(List<dynamic> jsonData, {bool merge = true}) async {
    final parsed = jsonData.map((dynamic item) => McpServerConfig.fromJson(item as Map<String, dynamic>)).toList();
    List<McpServerConfig> newConfigs;
    if (merge) {
      newConfigs = [...(state.valueOrNull ?? []), ...parsed];
    } else {
      newConfigs = parsed;
    }
    state = AsyncValue.data(newConfigs);
    await _save(newConfigs);
  }
}

final mcpConfigProvider = AsyncNotifierProvider<McpConfigNotifier, List<McpServerConfig>>(McpConfigNotifier.new);

class McpClientsNotifier extends AsyncNotifier<Map<String, Client>> {
  @override
  Future<Map<String, Client>> build() async => <String, Client>{};

  Future<Client?> getClient(String serverName) async {
    var clients = state.valueOrNull ?? {};
    if (clients.containsKey(serverName)) {
      return clients[serverName];
    }
    final configs = await ref.read(mcpConfigProvider.future);
    final config = configs.firstWhereOrNull((c) => c.name == serverName);
    if (config == null) return null;

    final clientConfig = McpClient.productionConfig(
      name: 'EngineAI Client',
      version: '1.0.0',
      capabilities: const ClientCapabilities(
        sampling: false,
      ),
    );

    TransportConfig transportConfig;
    if (config.pathOrUrl.endsWith('/mcp')) {
      transportConfig = TransportConfig.streamableHttp(baseUrl: config.pathOrUrl);
    } else {
      transportConfig = TransportConfig.sse(serverUrl: config.pathOrUrl);
    }

    final clientResult = await McpClient.createAndConnect(
      config: clientConfig,
      transportConfig: transportConfig,
    );

    final client = clientResult.fold(
      (c) => c,
      (error) => throw Exception('MCP 连接失败: $error'),
    );

    clients = Map<String, Client>.from(clients)..[serverName] = client;
    state = AsyncValue.data(clients);
    return client;
  }

  Future<void> disconnect(String serverName) async {
    final clients = state.valueOrNull ?? {};
    final client = clients[serverName];
    if (client != null) {
      client.disconnect();
      client.dispose();
    }
    final newClients = Map<String, Client>.from(clients)..remove(serverName);
    state = AsyncValue.data(newClients);
  }
}

final mcpClientsProvider = AsyncNotifierProvider<McpClientsNotifier, Map<String, Client>>(() => McpClientsNotifier());

final currentMcpClientProvider = FutureProvider<Client?>((ref) async {
  final mcpName = ref.watch(currentMcpProvider);
  if (mcpName.isEmpty) return null;
  final clientsNotifier = ref.read(mcpClientsProvider.notifier);
  return await clientsNotifier.getClient(mcpName);
});