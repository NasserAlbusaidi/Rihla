import 'package:flutter/material.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../models/expense_model.dart';
import 'segmented.dart';

class ScopeSegment extends StatelessWidget {
  const ScopeSegment({
    super.key,
    required this.scope,
    required this.onChanged,
  });

  final ExpenseScope scope;
  final ValueChanged<ExpenseScope> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // subGroup is legacy/dead — collapse it onto "Everyone".
    final selected = scope == ExpenseScope.subGroup ? ExpenseScope.global : scope;
    return Segmented<ExpenseScope>(
      value: selected,
      onChanged: onChanged,
      options: [
        (ExpenseScope.global, l10n.editorScopeGlobal),
        (ExpenseScope.custom, l10n.editorScopeCustom),
        (ExpenseScope.personal, l10n.editorScopePersonal),
      ],
    );
  }
}
