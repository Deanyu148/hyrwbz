import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'notification_model.dart';

const _notificationRefreshInterval = Duration(seconds: 30);

class NotificationListView extends StatelessWidget {
  final List<NotificationItem> notifications;
  final bool compact;
  final Future<void> Function() onMarkAllRead;
  final Future<void> Function(NotificationItem item) onTap;
  final bool showMarkAllRead;

  const NotificationListView({
    super.key,
    required this.notifications,
    required this.onMarkAllRead,
    required this.onTap,
    this.compact = false,
    this.showMarkAllRead = true,
  });

  @override
  Widget build(BuildContext context) {
    final visibleNotifications = compact && notifications.length > 4
        ? notifications.take(4).toList()
        : notifications;
    final hiddenCount = notifications.length - visibleNotifications.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
          child: Row(
            children: [
              Text(
                '通知${notifications.isEmpty ? '' : '（${notifications.length}）'}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (showMarkAllRead)
                TextButton(
                  onPressed: notifications.any((item) => !item.isRead)
                      ? onMarkAllRead
                      : null,
                  child: const Text('全部已读'),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: notifications.isEmpty
              ? const Center(child: Text('暂无需要提醒的任务'))
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  physics: compact
                      ? const NeverScrollableScrollPhysics()
                      : null,
                  itemCount: visibleNotifications.length,
                  itemBuilder: (context, index) {
                    final item = visibleNotifications[index];
                    return Tooltip(
                      message: '点击查看详情',
                      child: InkWell(
                        onTap: () => onTap(item),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: compact ? 7 : 10,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 14,
                                child: item.isRead
                                    ? null
                                    : Padding(
                                        padding: const EdgeInsets.only(top: 5),
                                        child: Container(
                                          width: 7,
                                          height: 7,
                                          decoration: const BoxDecoration(
                                            color: Colors.red,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                              ),
                              Expanded(
                                child: Text(
                                  item.message,
                                  maxLines: compact ? 2 : null,
                                  overflow: compact
                                      ? TextOverflow.ellipsis
                                      : null,
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
        if (compact && hiddenCount > 0) ...[
          const Divider(height: 1),
          SizedBox(
            height: 30,
            child: Center(
              child: Text(
                '还有 $hiddenCount 条，点击通知按钮查看全部',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class NotificationScreen extends StatefulWidget {
  final Future<void> Function(int taskId) onOpenTask;

  const NotificationScreen({
    super.key,
    required this.onOpenTask,
  });

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  List<NotificationItem> _notifications = const [];
  Timer? _refreshTimer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      _notificationRefreshInterval,
      (_) => _load(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await Api.listNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    await Api.markAllNotificationsRead();
    await _load();
  }

  Future<void> _open(NotificationItem item) async {
    if (!item.isRead) await Api.markNotificationRead(item.id);
    await _load();
    if (mounted) await widget.onOpenTask(item.taskId);
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _notifications.any((item) => !item.isRead);
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知'),
        actions: [
          TextButton(
            onPressed: hasUnread ? _markAllRead : null,
            child: const Text('全部已读'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : NotificationListView(
              notifications: _notifications,
              onMarkAllRead: _markAllRead,
              onTap: _open,
              showMarkAllRead: false,
            ),
    );
  }
}

class NotificationButton extends StatefulWidget {
  final Future<void> Function() onOpenScreen;
  final Future<void> Function(int taskId) onOpenTask;

  const NotificationButton({
    super.key,
    required this.onOpenScreen,
    required this.onOpenTask,
  });

  @override
  State<NotificationButton> createState() => _NotificationButtonState();
}

class _NotificationButtonState extends State<NotificationButton> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _entry;
  Timer? _refreshTimer;
  Timer? _hideTimer;
  List<NotificationItem> _notifications = const [];

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      _notificationRefreshInterval,
      (_) => _load(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _hideTimer?.cancel();
    _removePanel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await Api.listNotifications();
      if (!mounted) return;
      setState(() => _notifications = items);
      _entry?.markNeedsBuild();
    } catch (_) {}
  }

  double get _compactPanelHeight {
    if (_notifications.isEmpty) return 118;
    final visibleCount = _notifications.length > 4 ? 4 : _notifications.length;
    return 51 + visibleCount * 54 + (_notifications.length > 4 ? 30 : 0);
  }

  void _showPanel() {
    _hideTimer?.cancel();
    if (_entry != null) return;
    _entry = OverlayEntry(
      builder: (context) => CompositedTransformFollower(
        link: _layerLink,
        showWhenUnlinked: false,
        targetAnchor: Alignment.bottomRight,
        followerAnchor: Alignment.topRight,
        offset: const Offset(0, 8),
        child: MouseRegion(
          onEnter: (_) => _hideTimer?.cancel(),
          onExit: (_) => _scheduleRemovePanel(),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: 320,
              height: _compactPanelHeight,
              child: NotificationListView(
                notifications: _notifications,
                compact: true,
                onMarkAllRead: () async {
                  await Api.markAllNotificationsRead();
                  await _load();
                },
                onTap: (item) async {
                  if (!item.isRead) await Api.markNotificationRead(item.id);
                  _removePanel();
                  await widget.onOpenTask(item.taskId);
                  await _load();
                },
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_entry!);
    _load();
  }

  void _scheduleRemovePanel() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 250), _removePanel);
  }

  void _removePanel() {
    _hideTimer?.cancel();
    _hideTimer = null;
    _entry?.remove();
    _entry = null;
  }

  Future<void> _openScreen() async {
    _removePanel();
    await widget.onOpenScreen();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notifications.any((item) => !item.isRead);
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        onEnter: (_) => _showPanel(),
        onExit: (_) => _scheduleRemovePanel(),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_none),
              tooltip: '通知',
              onPressed: _openScreen,
            ),
            if (unread)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
