import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dart_ipc/dart_ipc.dart' as ipc;

const int _headerSize = 20;
const int _version = 1;
const int _flagResponse = 1;
const int _flagError = 2;
const int _maxJson = 1024 * 1024;
const int _maxBinary = 512 * 1024 * 1024;
const List<int> _magic = [0x48, 0x59, 0x52, 0x57];

class RpcException implements Exception {
  final String code;
  final String message;
  const RpcException(this.code, this.message);
  @override
  String toString() => message;
}

class RpcReply {
  final dynamic result;
  final Uint8List binary;
  const RpcReply(this.result, this.binary);
}

class LocalRpcClient {
  final String socketPath;
  Socket? _socket;
  StreamSubscription<Uint8List>? _subscription;
  final _decoder = RpcFrameDecoder();
  final Map<int, Completer<RpcReply>> _pending = {};
  int _nextId = 1;
  Future<void> _writeTail = Future<void>.value();
  bool _connected = false;

  LocalRpcClient(this.socketPath);

  bool get isConnected => _connected;

  Future<void> connect() async {
    if (_connected) return;
    final socket = await ipc.connect(socketPath);
    _socket = socket;
    _connected = true;
    _subscription = socket.listen(
      _onData,
      onError: (Object error, StackTrace stack) => _disconnect(error),
      onDone: () => _disconnect(const RpcException('disconnected', '本地服务连接已断开')),
      cancelOnError: true,
    );
  }

  Future<RpcReply> call(
    String method, {
    Map<String, dynamic> params = const {},
    Uint8List? binary,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_connected || _socket == null) {
      throw const RpcException('disconnected', '本地服务尚未连接');
    }
    final id = _nextId++;
    final completer = Completer<RpcReply>();
    _pending[id] = completer;
    final frame = encodeRpcFrame(
      flags: 0,
      header: {'id': id, 'method': method, 'params': params},
      binary: binary,
    );
    try {
      await _enqueueWrite(frame);
    } catch (error) {
      _pending.remove(id);
      rethrow;
    }
    try {
      return await completer.future.timeout(timeout);
    } on TimeoutException {
      _pending.remove(id);
      throw RpcException('timeout', '$method 请求超时');
    }
  }

  Future<void> close() async {
    _connected = false;
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    _socket = null;
    _failPending(const RpcException('closed', '本地服务连接已关闭'));
  }

  Future<void> _enqueueWrite(Uint8List bytes) {
    Future<void> write() async {
      final socket = _socket;
      if (!_connected || socket == null) {
        throw const RpcException('disconnected', '本地服务连接已断开');
      }
      socket.add(bytes);
      await socket.flush();
    }

    _writeTail = _writeTail.then((_) => write(), onError: (_) => write());
    return _writeTail;
  }

  void _onData(Uint8List data) {
    try {
      _decoder.add(data);
      while (true) {
        final frame = _decoder.tryDecode();
        if (frame == null) break;
        if ((frame.flags & _flagResponse) == 0) {
          throw const RpcException('protocol', '收到非响应 RPC 帧');
        }
        final id = (frame.header['id'] as num?)?.toInt() ?? 0;
        final completer = _pending.remove(id);
        if (completer == null) continue;
        if ((frame.flags & _flagError) != 0) {
          final error = frame.header['error'] as Map? ?? const {};
          completer.completeError(RpcException(
            error['code']?.toString() ?? 'internal',
            error['message']?.toString() ?? '本地服务调用失败',
          ));
        } else {
          completer.complete(RpcReply(frame.header['result'], frame.binary));
        }
      }
    } catch (error) {
      _disconnect(error);
    }
  }

  void _disconnect(Object error) {
    if (!_connected && _socket == null) return;
    _connected = false;
    _socket?.destroy();
    _socket = null;
    _subscription = null;
    _decoder.clear();
    _failPending(error);
  }

  void _failPending(Object error) {
    final pending = _pending.values.toList();
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }
}

class RpcFrame {
  final int flags;
  final Map<String, dynamic> header;
  final Uint8List binary;
  const RpcFrame(this.flags, this.header, this.binary);
}

Uint8List encodeRpcFrame({
  required int flags,
  required Map<String, dynamic> header,
  Uint8List? binary,
}) {
  final jsonBytes = Uint8List.fromList(utf8.encode(jsonEncode(header)));
  final payload = binary ?? Uint8List(0);
  if (jsonBytes.length > _maxJson || payload.length > _maxBinary) {
    throw const RpcException('frame_too_large', 'RPC 数据超过允许大小');
  }
  final output = Uint8List(_headerSize + jsonBytes.length + payload.length);
  output.setRange(0, 4, _magic);
  final view = ByteData.sublistView(output);
  view.setUint16(4, _version, Endian.big);
  view.setUint16(6, flags, Endian.big);
  view.setUint32(8, jsonBytes.length, Endian.big);
  view.setUint64(12, payload.length, Endian.big);
  output.setRange(_headerSize, _headerSize + jsonBytes.length, jsonBytes);
  output.setRange(_headerSize + jsonBytes.length, output.length, payload);
  return output;
}

RpcFrame? _tryDecodeRpcFrame(_ByteQueue queue) {
  if (queue.length < _headerSize) return null;
  final prefix = queue.peek(_headerSize);
  for (var i = 0; i < _magic.length; i++) {
    if (prefix[i] != _magic[i]) throw const RpcException('protocol', 'RPC magic 不正确');
  }
  final view = ByteData.sublistView(prefix);
  if (view.getUint16(4, Endian.big) != _version) {
    throw const RpcException('protocol_version', '前后端 RPC 协议版本不一致');
  }
  final flags = view.getUint16(6, Endian.big);
  final jsonLength = view.getUint32(8, Endian.big);
  final binaryLength = view.getUint64(12, Endian.big);
  if (jsonLength > _maxJson || binaryLength > _maxBinary) {
    throw const RpcException('frame_too_large', 'RPC 数据超过允许大小');
  }
  final total = _headerSize + jsonLength + binaryLength;
  if (queue.length < total) return null;
  queue.take(_headerSize);
  final headerBytes = queue.take(jsonLength);
  final decoded = jsonDecode(utf8.decode(headerBytes));
  if (decoded is! Map) throw const RpcException('protocol', 'RPC JSON 头格式错误');
  final binary = queue.take(binaryLength);
  return RpcFrame(flags, Map<String, dynamic>.from(decoded), binary);
}


class RpcFrameDecoder {
  final _ByteQueue _queue = _ByteQueue();

  void add(Uint8List bytes) => _queue.add(bytes);
  RpcFrame? tryDecode() => _tryDecodeRpcFrame(_queue);
  void clear() => _queue.clear();
}

class _ByteQueue {
  final List<Uint8List> _chunks = [];
  int _offset = 0;
  int length = 0;

  void add(Uint8List bytes) {
    if (bytes.isEmpty) return;
    _chunks.add(bytes);
    length += bytes.length;
  }

  Uint8List peek(int count) {
    if (count > length) throw RangeError.range(count, 0, length);
    final result = Uint8List(count);
    var written = 0;
    var chunkIndex = 0;
    var offset = _offset;
    while (written < count) {
      final chunk = _chunks[chunkIndex++];
      final available = chunk.length - offset;
      final take = (count - written) < available ? count - written : available;
      result.setRange(written, written + take, chunk, offset);
      written += take;
      offset = 0;
    }
    return result;
  }

  Uint8List take(int count) {
    if (count > length) throw RangeError.range(count, 0, length);
    final result = Uint8List(count);
    var written = 0;
    while (written < count) {
      final chunk = _chunks.first;
      final available = chunk.length - _offset;
      final take = (count - written) < available ? count - written : available;
      result.setRange(written, written + take, chunk, _offset);
      written += take;
      _offset += take;
      length -= take;
      if (_offset == chunk.length) {
        _chunks.removeAt(0);
        _offset = 0;
      }
    }
    return result;
  }

  void clear() {
    _chunks.clear();
    _offset = 0;
    length = 0;
  }
}
