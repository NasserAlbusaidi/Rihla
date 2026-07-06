import 'package:flutter/material.dart';

import '../../../../core/extensions/build_context_l10n.dart';
import '../../../../core/theme/tokens/domain_aliases.dart';
import '../../../../core/utils/localized_name_validators.dart';

class DescriptionField extends StatefulWidget {
  const DescriptionField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<DescriptionField> createState() => _DescriptionFieldState();
}

class _DescriptionFieldState extends State<DescriptionField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  // Recompute the inline error as the user types so an over-length / control-
  // char note shows a message instead of an opaque permission-denied (#220).
  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final errorText = validateFreeTextLocalized(
      context,
      widget.controller.text,
    );
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.spacing.space24),
      child: TextField(
        controller: widget.controller,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: context.l10n.editorDescriptionLabel,
          hintText: context.l10n.editorDescriptionHint,
          errorText: errorText,
          filled: true,
          fillColor: context.colors.scaffoldBackground,
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: context.colors.rule2),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: context.colors.primary, width: 1.5),
          ),
          errorBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: context.colors.error),
          ),
          focusedErrorBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: context.colors.error, width: 1.5),
          ),
        ),
      ),
    );
  }
}
