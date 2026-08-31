import 'dart:io' show File, Platform, Process, ProcessStartMode, Directory;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
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
  }
  // 启动后端子进程（隐藏窗口）
  await _startBackend();
  runApp(const HyrwbzApp());
}

Future<void> _startBackend() async {
  // 找到 backend exe（开发模式：相对 backend/target/release；打包后：与 frontend exe 同目录）
  final exe = _resolveBackendExe();
  if (exe == null) {
    // 找不到后端，仍启动 UI（用户能看到错误提示）
    _backendPort = 7790;
    Api.port = 7790;
    return;
  }
  // 选一个空闲端口
  final port = await _pickFreePort();
  _backendPort = port;
  Api.port = port;
  // Windows 上确保无新控制台窗口
  final mode = Platform.isWindows ? ProcessStartMode.detached : ProcessStartMode.normal;
  try {
    _backendProcess = await Process.start(
      exe,
      <String>['--port', port.toString()],
      mode: mode,
    );
  } catch (_) {
    // 启动失败也继续，UI 会提示连接失败
  }
  // 健康检查（最多 10s）
  for (var i = 0; i < 50; i++) {
    if (await Api.health(port: port)) return;
    await Future.delayed(const Duration(milliseconds: 200));
  }
}

Future<int> _pickFreePort() async {
  final s = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}

String? _resolveBackendExe() {
  final exeDir = File(Platform.resolvedExecutable).parent.path;
  final cwd = Directory.current.path;
  final candidates = <String>[
    // 打包后：与 frontend exe 同目录
    exeDir + '/hyrwbz_backend.exe',
    // 开发 release
    cwd + '/backend/target/release/hyrwbz_backend.exe',
    // 开发 debug
    cwd + '/backend/target/debug/hyrwbz_backend.exe',
  ];
  for (final p in candidates) {
    if (File(p).existsSync()) return p;
  }
  return null;
}

/// 应用退出（窗口关闭）时杀掉后端子进程
Future<void> _killBackend() async {
  try {
    _backendProcess.kill();
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
      ),
      home: const _KillOnClose(child: HomeScreen()),
    );
  }
}

/// 窗口关闭时杀后端子进程的包装 widget
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
    await _killBackend();
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
