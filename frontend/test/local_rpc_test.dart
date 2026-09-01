import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyrwbz_frontend/local_rpc.dart';

void main() {
  test('RPC frame supports fragmented input and binary payload', () {
    final bytes = encodeRpcFrame(
      flags: 1,
      header: {'id': 42, 'result': {'ok': true}},
      binary: Uint8List.fromList([0, 1, 2, 255]),
    );
    final decoder = RpcFrameDecoder();
    decoder.add(Uint8List.sublistView(bytes, 0, 7));
    expect(decoder.tryDecode(), isNull);
    decoder.add(Uint8List.sublistView(bytes, 7));
    final frame = decoder.tryDecode();
    expect(frame, isNotNull);
    expect(frame!.header['id'], 42);
    expect(frame.binary, [0, 1, 2, 255]);
  });

  test('RPC decoder reads consecutive frames', () {
    final first = encodeRpcFrame(flags: 1, header: {'id': 1, 'result': 1});
    final second = encodeRpcFrame(flags: 1, header: {'id': 2, 'result': 2});
    final decoder = RpcFrameDecoder()
      ..add(Uint8List.fromList([...first, ...second]));
    expect(decoder.tryDecode()!.header['id'], 1);
    expect(decoder.tryDecode()!.header['id'], 2);
    expect(decoder.tryDecode(), isNull);
  });
}
