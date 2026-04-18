// Tests for GroupActivityTile widget.
//
// Covers the _iconAndColor switch cases for different activity types
// (event_deleted, group_settlement, member_joined, member_left).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';

import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/groups/widgets/group_activity_tile.dart';

GroupActivityLog _makeLog(String type) => GroupActivityLog(
      id: 'log-$type',
      type: type,
      actorId: 'uid-1',
      actorName: 'Alice',
      description: 'Activity of type $type',
      timestamp: DateTime(2026, 1, 1),
    );

void main() {
  group('GroupActivityTile', () {
    testWidgets('renders event_deleted activity type', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme,
          home: Scaffold(
            body: GroupActivityTile(activity: _makeLog('event_deleted')),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(GroupActivityTile), findsOneWidget);
    });

    testWidgets('renders group_settlement activity type', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme,
          home: Scaffold(
            body: GroupActivityTile(activity: _makeLog('group_settlement')),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(GroupActivityTile), findsOneWidget);
    });

    testWidgets('renders member_joined activity type', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme,
          home: Scaffold(
            body: GroupActivityTile(activity: _makeLog('member_joined')),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(GroupActivityTile), findsOneWidget);
    });

    testWidgets('renders member_left activity type', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme,
          home: Scaffold(
            body: GroupActivityTile(activity: _makeLog('member_left')),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(GroupActivityTile), findsOneWidget);
    });

    testWidgets('renders unknown activity type (default case)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.lightTheme,
          home: Scaffold(
            body: GroupActivityTile(activity: _makeLog('unknown_type')),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(GroupActivityTile), findsOneWidget);
    });
  });
}
