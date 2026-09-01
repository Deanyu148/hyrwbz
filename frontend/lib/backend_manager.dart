import 'dart:async';
import 'dart:io';
import 'local_rpc.dart';

class BackendManager {
  Process? _process;
  LocalRpcClient? _client;
  Future<LocalRpcClient>? _starting;
  int _generation = 0;

  Future<LocalRpcClient> getClient() {
    final client = _client;
    if (client != null && client.isConnected) return Future.value(client);
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<LocalRpcClient> _start() async {
    await _stopProcess();
    final executable = _resolveBackendExe();
    if (executable == null) {
      throw const RpcException('backend_missing', '未找到 hyrwbz_backend.exe');
    }
    final socketPath = _newSocketPath();
    final mode = Platform.isWindows ? ProcessStartMode.detached : ProcessStartMode.normal;
    _process = await Process.start(
      executable,
      ['--socket-path', socketPath, '--parent-pid', pid.toString()],
      mode: mode,
    );

    Object? lastError;
    for (var i = 0; i < 50; i++) {
      final client = LocalRpcClient(socketPath);
      try {
        await client.connect();
        await client.call('system.health', timeout: const Duration(seconds: 2));
        _client = client;
        return client;
      } catch (error) {
        lastError = error;
        await client.close();
        await Future.delayed(const Duration(milliseconds: 200));
      }
    }
    await _stopProcess();
    throw RpcException('backend_start_failed', '本地服务启动失败: ${lastError ?? '连接超时'}');
  }

  String _newSocketPath() {
    final nonce = '${DateTime.now().microsecondsSinceEpoch}_${_generation++}';
    if (Platform.isWindows) return r'\\.\pipe\hyrwbz_' + '${pid}_$nonce';
    return '${Directory.systemTemp.path}/hyrwbz_${pid}_$nonce.sock';
  }

  String? _resolveBackendExe() {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final cwd = Directory.current.path;
    final suffix = Platform.isWindows ? '.exe' : '';
    final candidates = [
      '$exeDir/hyrwbz_backend$suffix',
      '$cwd/backend/target/release/hyrwbz_backend$suffix',
      '$cwd/backend/target/debug/hyrwbz_backend$suffix',
    ];
    for (final path in candidates) {
      if (File(path).existsSync()) return path;
    }
    return null;
  }

  Future<void> close() async {
    final client = _client;
    _client = null;
    await client?.close();
    await _stopProcess();
  }

  Future<void> _stopProcess() async {
    final process = _process;
    _process = null;
    if (process == null) return;
    try {
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/PID', '${process.pid}', '/T', '/F'])
            .timeout(const Duration(seconds: 2));
      } else {
        process.kill();
      }
    } catch (_) {}
  }
}
