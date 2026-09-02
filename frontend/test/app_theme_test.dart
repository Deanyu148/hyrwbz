import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hyrwbz_frontend/app_theme.dart';
import 'package:hyrwbz_frontend/app_widgets.dart';
import 'package:hyrwbz_frontend/search_field.dart';

void main() {
  test('application theme centralizes desktop visual defaults', () {
    final theme = AppTheme.light();
    expect(theme.useMaterial3, isTrue);
    expect(theme.scaffoldBackgroundColor, AppTheme.canvasColor);
    expect(theme.appBarTheme.toolbarHeight, 64);
    expect(theme.inputDecorationTheme.filled, isTrue);
  });

  testWidgets('surface and search loading state use shared components', (tester) async {
    final controller = TextEditingController(text: '工程');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Column(
            children: [
              const AppSurface(child: Text('内容面板')),
              AppSearchField(
                controller: controller,
                hintText: '搜索',
                loading: true,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('内容面板'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(Material), findsWidgets);
  });
}
