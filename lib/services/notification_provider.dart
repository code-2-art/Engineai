import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'notification_service.dart';

/// 通知服务 Provider
final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});
