import 'package:chatgpt/src/app_controller.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace.dart';
import 'package:chatgpt/src/presentation/workspace/codex_workspace_side_panel_tabs.dart';
import 'package:chatgpt/src/services/codex_app_server.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('main shell exposes labels for interactive controls', (
    tester,
  ) async {
    final controller = CodexController(server: CodexAppServer())
      ..workspacePath = '/workspace'
      ..status = RuntimeStatus.ready;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(home: CodexWorkspace(controller: controller)),
    );
    await tester.pump();

    final data = _collectSemantics(tester);
    for (final label in ['新对话', '设置']) {
      expect(
        data.any(
          (item) => item.label.contains(label) || item.tooltip.contains(label),
        ),
        isTrue,
        reason: label,
      );
    }

    final unlabeledTapNodes = _collectSemantics(tester)
        .where(
          (data) =>
              data.hasAction(SemanticsAction.tap) &&
              data.label.trim().isEmpty &&
              data.tooltip.trim().isEmpty,
        )
        .toList();
    expect(unlabeledTapNodes, isEmpty);
    semantics.dispose();
  });

  testWidgets(
    'settings controls and navigation retain labels in narrow windows',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(680, 520));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final controller = CodexController(server: CodexAppServer())
        ..workspacePath = '/workspace'
        ..status = RuntimeStatus.ready;
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(home: CodexWorkspace(controller: controller)),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('sidebar-settings-button')));
      await tester.pump();
      final settingsData = _collectSemantics(tester);
      expect(settingsData.any((data) => data.label.contains('返回应用')), isTrue);
      expect(settingsData.any((data) => data.label.contains('常规')), isTrue);
      expect(settingsData.any((data) => data.label.contains('外观')), isTrue);

      await tester.tap(find.byKey(const Key('settings-nav-外观')));
      await tester.pump();
      expect(
        _collectSemantics(tester).any((data) => data.label.contains('高对比度主题')),
        isTrue,
      );
      expect(find.byKey(const Key('settings-high-contrast')), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('workbench tabs expose selected and actionable semantics', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 420,
          height: 300,
          child: WorkspaceSidePanelTabs(
            contents: const {
              'review': Text('Review'),
              'agents': Text('Agents'),
            },
            labels: const {'review': '审查', 'agents': '智能体'},
            activeTab: 'review',
            onSelect: (_) {},
            onCollapse: _noop,
          ),
        ),
      ),
    );
    await tester.pump();

    final data = _collectSemantics(tester);
    expect(data.any((item) => item.label.contains('审查')), isTrue);
    expect(data.any((item) => item.label.contains('智能体')), isTrue);
    expect(
      _findSemanticsData(tester, '审查').flagsCollection.isSelected.toString() ==
          'Tristate.isTrue',
      isTrue,
    );
    expect(
      _findSemanticsData(tester, '审查').hasAction(SemanticsAction.tap),
      isTrue,
    );
    semantics.dispose();
  });
}

void _noop() {}

List<SemanticsData> _collectSemantics(WidgetTester tester) {
  final owner = tester.binding.renderViews.single.owner!.semanticsOwner;
  final root = owner?.rootSemanticsNode;
  if (root == null) return const <SemanticsData>[];
  final result = <SemanticsData>[];
  bool visit(SemanticsNode node) {
    result.add(node.getSemanticsData());
    node.visitChildren(visit);
    return true;
  }

  visit(root);
  return result;
}

SemanticsData _findSemanticsData(WidgetTester tester, String label) =>
    _collectSemantics(tester).firstWhere((data) => data.label.contains(label));
