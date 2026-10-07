import 'package:chatgpt/src/app_controller_conversation_timeline_state.dart';
import 'package:chatgpt/src/app_controller_pending_turn_steer.dart';
import 'package:chatgpt/src/domain/timeline_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clear invalidates the timeline and pending direction state', () {
    final state = CodexConversationTimelineState()
      ..entries.add(
        TimelineEntry(
          kind: TimelineKind.system,
          title: 'title',
          detail: 'detail',
          createdAt: DateTime(2026),
        ),
      )
      ..conversationViewRevision = 4
      ..resumingThread = true
      ..activeTurnId = 'turn-1'
      ..pendingTurnSteerSending = true
      ..pendingTurnSteerSendToken = Object();

    state.clear();

    expect(state.entries, isEmpty);
    expect(state.conversationViewRevision, 5);
    expect(state.resumingThread, isFalse);
    expect(state.activeTurnId, isNull);
    expect(state.pendingTurnSteers, isEmpty);
    expect(state.pendingTurnSteerSending, isFalse);
    expect(state.sendingPendingTurnSteer, isNull);
    expect(state.pendingTurnSteerSendToken, isNull);
  });

  test('timeline and pending directions remain independently mutable', () {
    final state = CodexConversationTimelineState();
    state.entries.add(
      TimelineEntry(
        kind: TimelineKind.system,
        title: 'system',
        detail: 'message',
        createdAt: DateTime(2026),
      ),
    );
    state.pendingTurnSteers.add(
      const PendingTurnSteer(displayText: 'Continue', prompt: 'Continue'),
    );

    expect(state.entries, hasLength(1));
    expect(state.pendingTurnSteers.single.prompt, 'Continue');
  });
}
