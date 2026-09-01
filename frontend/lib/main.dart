import 'dart:io' show File, Platform, Process, ProcessStartMode, Directory, InternetAddress, RawDatagramSocket, pid;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';
import 'screens/home_screen.dart';

late Process _backendProcess;
late int _backendPort;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.setTitle('会议任务管理跟踪系统');
    await windowManager.setMinimumSize(const Size(900, 600));
    // 拦截窗口关闭，保证 onWindowClose 有机会保存窗口状态并清理后端进程
    await windowManager.setPreventClose(true);
    // Restore saved window size and position
    final prefs = await SharedPreferences.getInstance();
    final w = prefs.getDouble('window_width');
    final h = prefs.getDouble('window_height');
    if (w != null && h != null) {
      await windowManager.setSize(Size(w, h));
    }
    final x = prefs.getDouble('window_x');
    final y = prefs.getDouble('window_y');
    if (x != null && y != null) {
      await windowManager.setPosition(Offset(x, y));
    }
  }
  await _startBackend();
  runApp(const HyrwbzApp());
}

Future<void> _startBackend() async {
  final exe = _resolveBackendExe();
  if (exe == null) {
    _backendPort = 7790;
    Api.port = 7790;
    return;
  }
  final port = await _pickFreePort();
  _backendPort = port;
  Api.port = port;
  final mode = Platform.isWindows ? ProcessStartMode.detached : ProcessStartMode.normal;
  try {
    _backendProcess = await Process.start(
      exe,
      <String>['--port', port.toString(), '--parent-pid', pid.toString()],
      mode: mode,
    );
  } catch (_) {}
  for (var i = 0; i < 50; i++) {
    if (await Api.health(port: port)) return;
    await Future.delayed(const Duration(milliseconds: 200));
  }
}

Future<int> _pickFreePort() async {
  final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  s.close();
  return port;
}

String? _resolveBackendExe() {
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final cwd = Directory.current.path;
  final candidates = <String>[
    exeDir + '/hyrwbz_backend.exe',
    cwd + '/backend/target/release/hyrwbz_backend.exe',
    cwd + '/backend/target/debug/hyrwbz_backend.exe',
  ];
  for (final p in candidates) {
    if (File(p).existsSync()) return p;
  }
  return null;
}

Future<void> _killBackend() async {
  try {
    if (Platform.isWindows) {
      // detached 进程用 taskkill 连同子进程一起强制结束，比 Process.kill 可靠
      await Process.run(
          'taskkill', <String>['/PID', _backendProcess.pid.toString(), '/T', '/F']);
    } else {
      _backendProcess.kill();
    }
  } catch (_) {}
}

class HyrwbzApp extends StatelessWidget {
  const HyrwbzApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '会议任务管理跟踪系统',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        fontFamily: Platform.isWindows ? 'Microsoft YaHei' : null,
      ),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [
        Locale('zh', 'CN'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _KillOnClose(child: HomeScreen()),
    );
  }
}

class _KillOnClose extends StatefulWidget {
  final Widget child;
  const _KillOnClose({required this.child});
  @override
  State<_KillOnClose> createState() => _KillOnCloseState();
}

class _KillOnCloseState extends State<_KillOnClose> with WindowListener {
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // Save window size and position before closing
    try {
      final size = await windowManager.getSize();
      final pos = await windowManager.getPosition();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('window_width', size.width);
      await prefs.setDouble('window_height', size.height);
      await prefs.setDouble('window_x', pos.dx);
      await prefs.setDouble('window_y', pos.dy);
    } catch (_) {}
    await _killBackend();
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
