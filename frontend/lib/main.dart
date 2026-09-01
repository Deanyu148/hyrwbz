import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'api.dart';
import 'backend_manager.dart';
import 'screens/home_screen.dart';
import 'window_state.dart';

final BackendManager backendManager = BackendManager();
late final WindowLifecycleListener windowLifecycle;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await windowManager.ensureInitialized();
    await windowManager.setTitle('会议任务管理跟踪系统');
    await windowManager.setMinimumSize(WindowStateStore.minimumSize);
    await WindowStateStore.restore();
    windowLifecycle = WindowLifecycleListener(onClose: backendManager.close);
    windowManager.addListener(windowLifecycle);
    await windowLifecycle.initialize();
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
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        fontFamily: Platform.isWindows ? 'Microsoft YaHei' : null,
      ),
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
