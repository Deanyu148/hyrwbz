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
  static const minimumSize = Size(900, 600);

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

  static Future<void> restore() async {
    final saved = load();
    if (saved == null) return;
    try {
      final displays = await screenRetriever.getAllDisplays();
      final primary = await screenRetriever.getPrimaryDisplay();
      final bounds = correctedBounds(saved, displays, primary);
      await windowManager.setBounds(bounds);
      if (saved.maximized) await windowManager.maximize();
    } catch (_) {
      await windowManager.setSize(Size(
        saved.width < minimumSize.width ? minimumSize.width : saved.width,
        saved.height < minimumSize.height ? minimumSize.height : saved.height,
      ));
    }
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

  Future<void> initialize() async {
    _maximized = await windowManager.isMaximized();
    if (_maximized) {
      // 启动时若恢复为最大化，保存文件中的 bounds 仍是上次的普通窗口范围。
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
    _maximized = true;
    _saveCurrent();
  }

  @override
  void onWindowUnmaximize() {
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
