import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

class SavedWindowState {
  final double x;
  final double y;
  final double width;
  final double height;
  final bool maximized;

  const SavedWindowState({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.maximized,
  });

  factory SavedWindowState.fromJson(Map<String, dynamic> json) => SavedWindowState(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        width: (json['width'] as num).toDouble(),
        height: (json['height'] as num).toDouble(),
        maximized: json['maximized'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'version': 2,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'maximized': maximized,
      };
}

class WindowStateStore {
  static const minimumSize = Size(1200, 600);

  static File get file {
    final appData = Platform.environment['APPDATA'];
    final base = appData == null || appData.isEmpty
        ? File(Platform.resolvedExecutable).parent
        : Directory(appData);
    return File('${base.path}${Platform.pathSeparator}hyrwbz${Platform.pathSeparator}window_state_v2.json');
  }

  static SavedWindowState? load() {
    try {
      final target = file;
      if (!target.existsSync()) return null;
      return SavedWindowState.fromJson(jsonDecode(target.readAsStringSync()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static void saveSync(SavedWindowState state) {
    try {
      final target = file;
      target.parent.createSync(recursive: true);
      final temporary = File('${target.path}.tmp');
      temporary.writeAsStringSync(jsonEncode(state.toJson()), flush: true);
      if (target.existsSync()) target.deleteSync();
      temporary.renameSync(target.path);
    } catch (_) {}
  }

  /// 在窗口尚未显示时恢复普通窗口范围，并返回保存的状态。
  /// 最大化由启动时序在 setBounds 完成后统一执行，避免窗口显示后再切换状态造成闪烁。
  static Future<SavedWindowState?> restore() async {
    final saved = load();
    if (saved == null) return null;
    try {
      final displays = await screenRetriever.getAllDisplays();
      final primary = await screenRetriever.getPrimaryDisplay();
      final bounds = correctedBounds(saved, displays, primary);
      await windowManager.setBounds(bounds);
    } catch (_) {
      await windowManager.setSize(Size(
        saved.width < minimumSize.width ? minimumSize.width : saved.width,
        saved.height < minimumSize.height ? minimumSize.height : saved.height,
      ));
    }
    return saved;
  }

  static Rect correctedBounds(
    SavedWindowState saved,
    List<Display> displays,
    Display primary,
  ) {
    final target = displays.cast<Display?>().firstWhere(
          (display) => display != null && _intersects(saved, display),
          orElse: () => null,
        ) ??
        primary;
    final work = _displayRect(target);
    final width = saved.width.clamp(minimumSize.width, work.width).toDouble();
    final height = saved.height.clamp(minimumSize.height, work.height).toDouble();
    var x = saved.x;
    var y = saved.y;
    if (!_intersects(saved, target)) {
      x = work.left + (work.width - width) / 2;
      y = work.top + (work.height - height) / 2;
    } else {
      x = x.clamp(work.left, work.right - width).toDouble();
      y = y.clamp(work.top, work.bottom - height).toDouble();
    }
    return Rect.fromLTWH(x, y, width, height);
  }

  static bool _intersects(SavedWindowState state, Display display) {
    return Rect.fromLTWH(state.x, state.y, state.width, state.height)
        .overlaps(_displayRect(display));
  }

  static Rect _displayRect(Display display) {
    final position = display.visiblePosition ?? Offset.zero;
    final size = display.visibleSize ?? display.size;
    return Rect.fromLTWH(position.dx, position.dy, size.width, size.height);
  }
}

class WindowLifecycleListener with WindowListener {
  final Future<void> Function() onClose;
  Timer? _saveTimer;
  SavedWindowState? _normalState;
  bool _maximized = false;
  bool _closing = false;

  WindowLifecycleListener({required this.onClose});

  Future<void> initialize({SavedWindowState? restoredState}) async {
    if (restoredState != null) {
      // 最大化窗口启动时，原生窗口可能要到 show 后才报告 maximized。
      // 直接采用已保存状态，避免初始化阶段把 maximized 错写为 false。
      _normalState = restoredState;
      _maximized = restoredState.maximized;
      if (!_maximized) await _captureNormalState();
      return;
    }
    _maximized = await windowManager.isMaximized();
    if (_maximized) {
      _normalState = WindowStateStore.load();
    } else {
      await _captureNormalState();
    }
  }

  void dispose() {
    _saveTimer?.cancel();
  }

  @override
  void onWindowMove() => _scheduleCapture();

  @override
  void onWindowResize() => _scheduleCapture();

  @override
  void onWindowMaximize() {
    _saveTimer?.cancel();
    _maximized = true;
    _saveCurrent();
  }

  @override
  void onWindowUnmaximize() {
    // Windows 关闭最大化窗口时可能短暂发出 unmaximize；稍后确认，
    // 防止关闭过程把已保存的最大化状态覆盖为普通窗口。
    unawaited(_confirmUnmaximize());
  }

  Future<void> _confirmUnmaximize() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (_closing || await windowManager.isMaximized()) return;
    _maximized = false;
    _scheduleCapture();
  }

  @override
  void onWindowClose() {
    if (_closing) return;
    _closing = true;
    _saveTimer?.cancel();
    _saveCurrent();
    unawaited(onClose());
  }

  void _scheduleCapture() {
    if (_maximized) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), () async {
      await _captureNormalState();
      _saveCurrent();
    });
  }

  Future<void> _captureNormalState() async {
    if (await windowManager.isMaximized()) return;
    final bounds = await windowManager.getBounds();
    _normalState = SavedWindowState(
      x: bounds.left,
      y: bounds.top,
      width: bounds.width,
      height: bounds.height,
      maximized: false,
    );
  }

  void _saveCurrent() {
    final state = _normalState;
    if (state == null) return;
    WindowStateStore.saveSync(SavedWindowState(
      x: state.x,
      y: state.y,
      width: state.width,
      height: state.height,
      maximized: _maximized,
    ));
  }
}
