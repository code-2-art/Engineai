import 'package:collection/collection.dart';
import 'package:mcp_client/mcp_client.dart';

enum McpType {
  remote,
}

class McpServerConfig {
  final String name;
  final McpType type;
  final String pathOrUrl;

  const McpServerConfig({
    required this.name,
    required this.type,
    required this.pathOrUrl,
  });

  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    return McpServerConfig(
      name: json['name'] as String,
      type: json.containsKey('type') ? McpType.values.byName(json['type'] as String) : McpType.remote,
      pathOrUrl: json['pathOrUrl'] ?? json['url'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'type': type.name,
      'pathOrUrl': pathOrUrl,
    };
  }
}