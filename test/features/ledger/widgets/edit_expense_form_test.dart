import 'package:decimal/decimal.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:safar/core/types/event_ref.dart';
import 'package:safar/features/auth/providers/auth_provider.dart';
import 'package:safar/features/events/models/event_model.dart';
import 'package:safar/features/ledger/models/expense_model.dart';
import 'package:safar/features/ledger/providers/category_provider.dart';
import 'package:safar/features/ledger/widgets/edit_expense_form.dart';
import 'package:safar/features/logistics/providers/sub_group_provider.dart';
import 'package:safar/features/trip/models/trip_model.dart';
import 'package:safar/features/trip/providers/trip_provider.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockUser extends Mock implements firebase_auth.User {}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _groupId = 'g-1';
const _eventId = 'e-1';
const _creatorUid = 'uid-creator';

final _testEvent = Event(
  id: _eventId,
  name: 'Test Event',
  type: EventType.trip,
  groupId: _groupId,
  createdBy: _creatorUid,
  participantIds: const [_creatorUid],
  participantNames: const {_creatorUid: 'Alice'},
  modules: const EventModules(
    ledger: true,
    gear: false,
    logistics: false,
    vault: false,
    memories: false,
  ),
  currency: 'OMR',
  createdAt: DateTime(2026, 1, 1),
);

final _testExpense = Expense(
  id: 'exp-1',
  tripId: _eventId,
  payerParticipantId: _creatorUid,
  amount: Decimal.parse('10.500'),
  description: 'Dinner',
  scope: ExpenseScope.global,
  createdAt: DateTime(2026, 1, 2),
  payerName: 'Alice',
  categoryName: 'Food & Dining',
  categoryIcon: 'food',
);

// ---------------------------------------------------------------------------
// Helper
// ---------------------------------------------------------------------------

Widget _wrapForm({
  VoidCallback? onSubmit,
  VoidCallback? onDelete,
  bool isSaving = false,
  String? selectedCategoryId,
  TextEditingController? amountController,
}) {
  final EventRef eventRef = (groupId: _groupId, eventId: _eventId);
  final ctrl = amountController ?? TextEditingController(text: '10.500');
  final mockUser = MockUser();
  when(() => mockUser.uid).thenReturn(_creatorUid);

  return ProviderScope(
    overrides: [
      // Categories provider — return empty list for simplicity
      tripCategoriesProvider(_eventId).overrideWith(
        (ref) => Stream.value(const []),
      ),
      // Scope section provider
      eventSubGroupsProvider(eventRef).overrideWith(
        (ref) => Stream.value(const []),
      ),
      // Payer selector providers
      currentUserProvider.overrideWith((ref) => mockUser),
      currentParticipantProvider(_eventId).overrideWith((ref) => null),
      eventLogisticsParticipantsProvider(_testEvent)
          .overrideWith((ref) => const []),
    ],
    child: MaterialApp(
      home: EditExpenseForm(
        initialExpense: _testExpense,
        groupId: _groupId,
        eventId: _eventId,
        event: _testEvent,
        tripCurrency: 'OMR',
        amountController: ctrl,
        noteController: TextEditingController(text: ''),
        selectedCategoryId: selectedCategoryId,
        onCategoryChanged: (_) {},
        scope: ExpenseScope.global,
        onScopeChanged: (_) {},
        selectedSubGroupId: null,
        onSubGroupIdChanged: (_) {},
        customSplitParticipants: const {},
        onCustomSplitChanged: (_) {},
        selectedPayerId: null,
        onPayerChanged: (_) {},
        onSubmit: onSubmit ?? () {},
        onDelete: onDelete ?? () {},
        isSaving: isSaving,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('EditExpenseForm', () {
    testWidgets('renders amount field and note field', (tester) async {
      await tester.pumpWidget(_wrapForm());
      await tester.pump();

      // Amount TextField
      expect(find.byType(TextField), findsAtLeastNWidgets(1));
      // Note field hint
      expect(find.text('Add a note...'), findsOneWidget);
    });

    testWidgets('renders Save Changes button', (tester) async {
      await tester.pumpWidget(_wrapForm());
      await tester.pump();

      expect(find.text('Save Changes'), findsOneWidget);
    });

    testWidgets('renders Cancel button', (tester) async {
      await tester.pumpWidget(_wrapForm());
      await tester.pump();

      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('calls onSubmit when Save Changes is tapped', (tester) async {
      var submitted = false;
      await tester.pumpWidget(_wrapForm(onSubmit: () => submitted = true));
      await tester.pump();

      // Scroll to ensure the button is visible before tapping
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.tap(find.text('Save Changes'));
      await tester.pump();

      expect(submitted, isTrue);
    });

    testWidgets('calls onDelete when delete icon button is tapped',
        (tester) async {
      var deleted = false;
      await tester.pumpWidget(_wrapForm(onDelete: () => deleted = true));
      await tester.pump();

      await tester.tap(find.byTooltip('Delete expense'));
      await tester.pump();

      expect(deleted, isTrue);
    });

    testWidgets('Save Changes button is disabled when isSaving is true',
        (tester) async {
      await tester.pumpWidget(_wrapForm(isSaving: true));
      await tester.pump();

      // When isSaving, the button shows a CircularProgressIndicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Save Changes'), findsNothing);
    });

    testWidgets('shows diff indicator when amount changes from original',
        (tester) async {
      final ctrl = TextEditingController(text: '20.000');
      await tester.pumpWidget(_wrapForm(amountController: ctrl));
      await tester.pump();

      // The diff row shows the original amount with a strikethrough label
      // and the new amount. We verify the arrow icon is present.
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    });
  });
}
