import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'api.dart';
import 'app_theme.dart';
import 'backend_manager.dart';
import 'screens/home_screen.dart';
import 'window_state.dart';

final BackendManager backendManager = BackendManager();
late final WindowLifecycleListener windowLifecycle;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: WindowStateStore.minimumSize,
      minimumSize: WindowStateStore.minimumSize,
      center: true,
      title: '会议任务管理跟踪系统',
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      SavedWindowState? saved;
      var listenerCreated = false;
      try {
        // 窗口保持隐藏，先恢复普通窗口范围，再恢复最大化状态。
        saved = await WindowStateStore.restore();
        if (saved?.maximized == true) {
          await windowManager.maximize();
        }
        windowLifecycle = WindowLifecycleListener(onClose: backendManager.close);
        windowManager.addListener(windowLifecycle);
        listenerCreated = true;
        await windowLifecycle.initialize(restoredState: saved);
      } catch (_) {
        // 即使恢复状态失败，也要继续显示窗口，避免应用无界面启动。
        if (!listenerCreated) {
          windowLifecycle = WindowLifecycleListener(onClose: backendManager.close);
          windowManager.addListener(windowLifecycle);
        }
      } finally {
        await windowManager.show();
        // 少数 Windows 环境对隐藏窗口的 maximize 延迟生效；显示后只在
        // 状态仍未生效时补做一次，保证最终一定以最大化打开。
        if (saved?.maximized == true && !await windowManager.isMaximized()) {
          await windowManager.maximize();
        }
        await windowManager.focus();
      }
    });
  }
  Api.configure(backendManager.getClient);
  runApp(const HyrwbzApp());
}

class HyrwbzApp extends StatelessWidget {
  const HyrwbzApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '会议任务管理跟踪系统',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeScreen(),
    );
  }
}
