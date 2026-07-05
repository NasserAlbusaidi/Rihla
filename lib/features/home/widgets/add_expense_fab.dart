import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../../core/extensions/build_context_l10n.dart';
import '../../../core/services/haptic_service.dart';
import '../keys/home_keys.dart';
import '../providers/active_journeys_provider.dart';
import 'add_expense_target_sheet.dart';

/// Route for an [AddExpenseTarget] — same path shape the ledger CTA and the
/// event hub push (#364).
String addExpensePathFor(AddExpenseTarget target) {
  return '/group/${target.groupId}/event/${target.eventId}/ledger/add';
}

/// Persistent add-expense FAB for the tab shell (#364).
///
/// Fast path (#900 / friction #1): a ranked `preferred` target exists (every
/// group's event stream resolved, and at least one open event anywhere) →
/// push its add route directly; the editor's Where card names the target and
/// offers "change" if the guess is wrong. Otherwise open the flattened target
/// picker sheet.
class AddExpenseFab extends ConsumerWidget {
  const AddExpenseFab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targetsAsync = ref.watch(addExpenseTargetsProvider);
    return FloatingActionButton(
      key: HomeKeys.addExpenseFab,
      tooltip: context.l10n.homeQuickAddExpense,
      onPressed: () {
        HapticService.lightClick();
        final target = targetsAsync.valueOrNull?.preferred;
        if (target != null) {
          context.push(addExpensePathFor(target));
          return;
        }
        AddExpenseTargetSheet.show(context);
      },
      child: const Icon(Iconsax.add),
    );
  }
}
