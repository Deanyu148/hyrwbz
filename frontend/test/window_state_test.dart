import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:hyrwbz_frontend/window_state.dart';

void main() {
  const display = Display(
    id: 'primary',
    size: Size(1920, 1080),
    visiblePosition: Offset.zero,
    visibleSize: Size(1920, 1040),
  );

  test('off-screen window is centered on primary display', () {
    const saved = SavedWindowState(
      x: 5000,
      y: 5000,
      width: 1000,
      height: 700,
      maximized: false,
    );
    final bounds = WindowStateStore.correctedBounds(saved, const [display], display);
    expect(bounds.left, closeTo(360, 0.001));
    expect(bounds.top, closeTo(170, 0.001));
  });

  test('window size is clamped to minimum and visible work area', () {
    const saved = SavedWindowState(
      x: 10,
      y: 10,
      width: 300,
      height: 200,
      maximized: false,
    );
    final bounds = WindowStateStore.correctedBounds(saved, const [display], display);
    expect(bounds.width, 1200);
    expect(bounds.height, 600);
  });

  test('maximized state survives JSON persistence', () {
    const saved = SavedWindowState(
      x: 120,
      y: 80,
      width: 1280,
      height: 720,
      maximized: true,
    );
    final restored = SavedWindowState.fromJson(saved.toJson());
    expect(restored.maximized, isTrue);
    expect(restored.x, saved.x);
    expect(restored.y, saved.y);
    expect(restored.width, saved.width);
    expect(restored.height, saved.height);
  });
}
