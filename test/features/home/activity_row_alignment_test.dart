import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safar/core/theme/app_theme.dart';
import 'package:safar/features/groups/models/group_activity_log_model.dart';
import 'package:safar/features/home/widgets/activity_row.dart';
import 'package:safar/l10n/generated/app_localizations.dart';

void main() {
  testWidgets(
    'avatar top-aligns to the first text line so wrapped titles do not push '
    'it to the vertical centre (#159)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: SizedBox(width: 360, child: _Row()),
          ),
        ),
      );

      // The outer Row holds the avatar + the text column. Top-aligning it
      // keeps the avatar pinned to the first line regardless of wrap.
      final outerRow = tester.widget<Row>(
        find
            .descendant(
              of: find.byType(ActivityRow),
              matching: find.byType(Row),
            )
            .first,
      );
      expect(outerRow.crossAxisAlignment, CrossAxisAlignment.start);
    },
  );
}

GroupActivityLog _fixture() => GroupActivityLog(
  id: '1',
  type: 'member_joined',
  actorId: 'u1',
  actorName: 'Abdulrahman Al-Mahrouqi',
  description: 'joined the Salalah Khareef Summer Road Trip',
  timestamp: DateTime(2026, 5, 1),
);

class _Row extends StatelessWidget {
  const _Row();
  @override
  Widget build(BuildContext context) => ActivityRow(
    activity: _fixture(),
    groupName: 'Salalah Khareef',
    groupId: 'g1',
  );
}
