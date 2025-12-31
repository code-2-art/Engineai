import 'package:flutter/material.dart';

/// 通知类型
enum NotificationType {
  info,
  success,
  warning,
  error,
}

/// 通知数据类
class NotificationData {
  final String message;
  final NotificationType type;
  final Duration duration;
  final VoidCallback? onDismiss;

  NotificationData({
    required this.message,
    this.type = NotificationType.info,
    this.duration = const Duration(seconds: 3),
    this.onDismiss,
  });
}

/// 通知服务
class NotificationService extends ChangeNotifier {
  final List<NotificationData> _notifications = [];

  List<NotificationData> get notifications => List.unmodifiable(_notifications);

  /// 显示通知
  void show(NotificationData notification) {
    _notifications.add(notification);
    notifyListeners();

    // 自动移除通知
    Future.delayed(notification.duration, () {
      if (_notifications.contains(notification)) {
        _notifications.remove(notification);
        notifyListeners();
        notification.onDismiss?.call();
      }
    });
  }

  /// 显示信息通知
  void showInfo(String message, {Duration? duration}) {
    show(NotificationData(
      message: message,
      type: NotificationType.info,
      duration: duration ?? const Duration(seconds: 3),
    ));
  }

  /// 显示成功通知
  void showSuccess(String message, {Duration? duration}) {
    show(NotificationData(
      message: message,
      type: NotificationType.success,
      duration: duration ?? const Duration(seconds: 3),
    ));
  }

  /// 显示警告通知
  void showWarning(String message, {Duration? duration}) {
    show(NotificationData(
      message: message,
      type: NotificationType.warning,
      duration: duration ?? const Duration(seconds: 4),
    ));
  }

  /// 显示错误通知
  void showError(String message, {Duration? duration}) {
    show(NotificationData(
      message: message,
      type: NotificationType.error,
      duration: duration ?? const Duration(seconds: 4),
    ));
  }

  /// 手动移除通知
  void remove(NotificationData notification) {
    if (_notifications.remove(notification)) {
      notifyListeners();
      notification.onDismiss?.call();
    }
  }

  /// 清除所有通知
  void clear() {
    _notifications.clear();
    notifyListeners();
  }
}

/// 通知显示组件
class NotificationOverlay extends StatelessWidget {
  final NotificationService service;

  const NotificationOverlay({
    super.key,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: service,
      builder: (context, child) {
        final notifications = service.notifications;
        if (notifications.isEmpty) {
          return const SizedBox.shrink();
        }

        return Positioned(
          top: 16,
          right: 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: notifications.map((notification) {
              return _NotificationCard(
                notification: notification,
                onDismiss: () => service.remove(notification),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

/// 单个通知卡片
class _NotificationCard extends StatefulWidget {
  final NotificationData notification;
  final VoidCallback onDismiss;

  const _NotificationCard({
    required this.notification,
    required this.onDismiss,
  });

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    Color backgroundColor;
    Color textColor;
    Color iconColor;
    IconData icon;

    switch (widget.notification.type) {
      case NotificationType.info:
        backgroundColor = isDark
            ? const Color(0xFF1E3A5F)
            : const Color(0xFFE3F2FD);
        textColor = isDark
            ? const Color(0xFFE3F2FD)
            : const Color(0xFF1565C0);
        iconColor = isDark
            ? const Color(0xFF64B5F6)
            : const Color(0xFF1976D2);
        icon = Icons.info_outline;
        break;
      case NotificationType.success:
        backgroundColor = isDark
            ? const Color(0xFF1B5E20)
            : const Color(0xFFE8F5E9);
        textColor = isDark
            ? const Color(0xFFE8F5E9)
            : const Color(0xFF2E7D32);
        iconColor = isDark
            ? const Color(0xFF66BB6A)
            : const Color(0xFF388E3C);
        icon = Icons.check_circle_outline;
        break;
      case NotificationType.warning:
        backgroundColor = isDark
            ? const Color(0xFFBF360C)
            : const Color(0xFFFFF3E0);
        textColor = isDark
            ? const Color(0xFFFFF3E0)
            : const Color(0xFFE65100);
        iconColor = isDark
            ? const Color(0xFFFFB74D)
            : const Color(0xFFF57C00);
        icon = Icons.warning_amber_outlined;
        break;
      case NotificationType.error:
        backgroundColor = isDark
            ? const Color(0xFFB71C1C)
            : const Color(0xFFFFEBEE);
        textColor = isDark
            ? const Color(0xFFFFEBEE)
            : const Color(0xFFC62828);
        iconColor = isDark
            ? const Color(0xFFEF5350)
            : const Color(0xFFD32F2F);
        icon = Icons.error_outline;
        break;
    }

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          constraints: const BoxConstraints(
            minWidth: 280,
            maxWidth: 400,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: widget.onDismiss,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      color: iconColor,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.notification.message,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 14,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: widget.onDismiss,
                      child: Icon(
                        Icons.close,
                        color: textColor.withOpacity(0.6),
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
