import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'api.dart';
import 'notification_model.dart';
import 'notification_search.dart';
import 'search_field.dart';
import 'screens/date_picker_dialog.dart';

const _notificationRefreshInterval = Duration(seconds: 30);

class NotificationListView extends StatelessWidget {
  static const double bodyFontSize = 16;
  static const double bodyLineHeight = 1.4;
  static const double _verticalPadding = bodyFontSize * bodyLineHeight / 2;

  final List<NotificationItem> notifications;
  final Future<void> Function(NotificationItem item) onTap;

  const NotificationListView({
    super.key,
    required this.notifications,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (notifications.isEmpty) {
      return const Center(child: Text('暂无通知'));
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: notifications.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = notifications[index];
        return Tooltip(
          message: '点击查看详情',
          child: InkWell(
            key: ValueKey('full-notification-${item.id}'),
            onTap: () => onTap(item),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: _verticalPadding,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    child: item.isRead
                        ? null
                        : Center(
                            child: Container(
                              width: 8,
                              height: 8,
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
                      textAlign: TextAlign.left,
                      style: const TextStyle(
                        fontSize: bodyFontSize,
                        height: bodyLineHeight,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 仅供鼠标悬停预览使用的紧凑面板，与完整通知界面完全独立。
class CompactNotificationPanel extends StatelessWidget {
  static const double panelScale = 3;
  static const double panelWidth = 130 * panelScale;
  static const double bodyFontSize = 14;
  static const double bodyLineHeight = 1.4;
  static const double _bodyVerticalPadding = bodyFontSize * bodyLineHeight / 2;
  // 只放大外层面板，标题栏和底部提示保持原有高度。
  static const double _headerHeight = 36;
  static const double _footerHeight = 24;
  static const double _dividerHeight = 1;
  static const int maxPreviewItems = 2;

  static double heightForItemCount(int itemCount) {
    if (itemCount <= 0) return 82 * panelScale;
    final visibleCount = itemCount > maxPreviewItems
        ? maxPreviewItems
        : itemCount;
    return (37 + visibleCount * 52 + (itemCount > visibleCount ? 25 : 0)) *
        panelScale;
  }

  final List<NotificationItem> notifications;
  final Future<void> Function() onMarkAllRead;
  final Future<void> Function(NotificationItem item) onTap;

  const CompactNotificationPanel({
    super.key,
    required this.notifications,
    required this.onMarkAllRead,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final visible = notifications.take(maxPreviewItems).toList();
    final hiddenCount = notifications.length - visible.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _headerHeight,
          child: Padding(
            padding: const EdgeInsets.only(left: 8, right: 2),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '通知',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '全部已读',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 30,
                    height: 30,
                  ),
                  onPressed: notifications.any((item) => !item.isRead)
                      ? onMarkAllRead
                      : null,
                  icon: const Icon(Icons.done_all, size: 17),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: _dividerHeight),
        if (notifications.isEmpty)
          const Expanded(
            child: Center(
              child: Text(
                '暂无通知',
                style: TextStyle(fontSize: 13),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: visible.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: _dividerHeight),
              itemBuilder: (context, index) {
                final item = visible[index];
                return Tooltip(
                  message: '点击查看详情',
                  child: InkWell(
                    key: ValueKey('compact-notification-${item.id}'),
                    onTap: () => onTap(item),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: _bodyVerticalPadding,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 10,
                            child: item.isRead
                                ? null
                                : Center(
                                    child: Container(
                                      width: 6,
                                      height: 6,
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
                              textAlign: TextAlign.left,
                              style: const TextStyle(
                                fontSize: bodyFontSize,
                                height: bodyLineHeight,
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
        if (hiddenCount > 0) ...[
          const Divider(height: _dividerHeight),
          SizedBox(
            height: _footerHeight,
            child: Center(
              child: Text(
                '还有 $hiddenCount 条',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 13,
                ),
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
  final TextEditingController _searchController = TextEditingController();
  List<NotificationItem> _allNotifications = const [];
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
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await Api.listNotifications();
      if (!mounted) return;
      setState(() {
        _allNotifications = items;
        _applySearch();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applySearch() {
    final query = _searchController.text;
    _notifications = query.trim().isEmpty
        ? List<NotificationItem>.from(_allNotifications)
        : _allNotifications
            .where((item) => notificationMatchesSearch(item, query))
            .toList();
  }

  void _searchNotifications(String _) {
    setState(_applySearch);
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationHistoryScreen(
          onOpenTask: widget.onOpenTask,
        ),
      ),
    );
    await _load();
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
    final hasUnread = _allNotifications.any((item) => !item.isRead);
    return Scaffold(
      appBar: AppBar(
        title: AppBarSearchTitle(
          title: '通知',
          controller: _searchController,
          hintText: '搜索通知（空格分词、引号短语、-排除）',
          onChanged: _searchNotifications,
        ),
        actions: [
          IconButton(
            tooltip: '刷新通知',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
          TextButton.icon(
            onPressed: _openHistory,
            icon: const Icon(Icons.history),
            label: const Text('历史通知'),
          ),
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
              onTap: _open,
            ),
    );
  }
}

enum _NotificationHistoryRange {
  threeDays,
  oneWeek,
  all,
  exact,
}

class NotificationHistoryScreen extends StatefulWidget {
  final Future<void> Function(int taskId) onOpenTask;

  const NotificationHistoryScreen({
    super.key,
    required this.onOpenTask,
  });

  @override
  State<NotificationHistoryScreen> createState() =>
      _NotificationHistoryScreenState();
}

class _NotificationHistoryScreenState extends State<NotificationHistoryScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<NotificationItem> _allNotifications = const [];
  List<NotificationItem> _notifications = const [];
  _NotificationHistoryRange _range = _NotificationHistoryRange.threeDays;
  String? _exactFrom;
  String? _exactTo;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  ({String? from, String? to}) _selectedDates() {
    final today = DateTime.now();
    switch (_range) {
      case _NotificationHistoryRange.threeDays:
        return (
          from: DateFormat('yyyy/MM/dd').format(
            today.subtract(const Duration(days: 2)),
          ),
          to: DateFormat('yyyy/MM/dd').format(today),
        );
      case _NotificationHistoryRange.oneWeek:
        return (
          from: DateFormat('yyyy/MM/dd').format(
            today.subtract(const Duration(days: 6)),
          ),
          to: DateFormat('yyyy/MM/dd').format(today),
        );
      case _NotificationHistoryRange.all:
        return (from: null, to: null);
      case _NotificationHistoryRange.exact:
        return (from: _exactFrom, to: _exactTo);
    }
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final dates = _selectedDates();
      final items = await Api.listNotificationHistory(
        from: dates.from,
        to: dates.to,
      );
      if (!mounted) return;
      setState(() {
        _allNotifications = items;
        _applySearch();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applySearch() {
    final query = _searchController.text;
    _notifications = query.trim().isEmpty
        ? List<NotificationItem>.from(_allNotifications)
        : _allNotifications
            .where((item) => notificationMatchesSearch(item, query))
            .toList();
  }

  void _search(String _) => setState(_applySearch);

  Future<void> _open(NotificationItem item) async {
    if (!item.isRead) await Api.markNotificationRead(item.id);
    await _load();
    if (mounted) await widget.onOpenTask(item.taskId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AppBarSearchTitle(
          title: '历史通知',
          controller: _searchController,
          hintText: '搜索历史通知',
          onChanged: _search,
        ),
        actions: [
          IconButton(
            tooltip: '刷新历史通知',
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                const Text('通知时间'),
                const SizedBox(width: 12),
                SizedBox(
                  width: 170,
                  child: DropdownButtonFormField<_NotificationHistoryRange>(
                    initialValue: _range,
                    isExpanded: true,
                    decoration: const InputDecoration(isDense: true),
                    items: const [
                      DropdownMenuItem(
                        value: _NotificationHistoryRange.threeDays,
                        child: Text('三天内'),
                      ),
                      DropdownMenuItem(
                        value: _NotificationHistoryRange.oneWeek,
                        child: Text('一周内'),
                      ),
                      DropdownMenuItem(
                        value: _NotificationHistoryRange.all,
                        child: Text('全部'),
                      ),
                      DropdownMenuItem(
                        value: _NotificationHistoryRange.exact,
                        child: Text('精确时间'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _range = value);
                      if (value != _NotificationHistoryRange.exact) _load();
                    },
                  ),
                ),
                if (_range == _NotificationHistoryRange.exact) ...[
                  const SizedBox(width: 18),
                  Expanded(
                    child: DateRangeField(
                      initialFrom: _exactFrom,
                      initialTo: _exactTo,
                      label: '精确日期',
                      onChanged: (from, to) {
                        _exactFrom = from;
                        _exactTo = to;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.search),
                    label: const Text('查询'),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : NotificationListView(
                    notifications: _notifications,
                    onTap: _open,
                  ),
          ),
        ],
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

  double get _compactPanelHeight =>
      CompactNotificationPanel.heightForItemCount(_notifications.length);

  void _showPanel() {
    _hideTimer?.cancel();
    if (_entry != null) return;
    _entry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned(
            width: CompactNotificationPanel.panelWidth,
            height: _compactPanelHeight,
            child: CompositedTransformFollower(
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
                  child: CompactNotificationPanel(
                    notifications: _notifications,
                    onMarkAllRead: () async {
                      await Api.markAllNotificationsRead();
                      await _load();
                    },
                    onTap: (item) async {
                      if (!item.isRead) {
                        await Api.markNotificationRead(item.id);
                      }
                      _removePanel();
                      await widget.onOpenTask(item.taskId);
                      await _load();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
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
