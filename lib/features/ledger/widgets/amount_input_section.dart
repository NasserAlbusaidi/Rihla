import 'package:flutter/material.dart';
import '../../../core/theme/tokens/color_tokens.dart';

/// Numeric keypad and amount display for expense entry.
///
/// Step 0 in the 3-step Add Expense flow.
class AmountInputSection extends StatelessWidget {
  final String amount;
  final String currency;
  final ValueChanged<String> onKeyPress;

  const AmountInputSection({
    super.key,
    required this.amount,
    required this.currency,
    required this.onKeyPress,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        // Amount Display
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              currency,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w300,
                color: AppColorTokens.light.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              amount,
              style: TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.w900,
                color: AppColorTokens.light.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 40),
        // Numpad
        _Numpad(onKeyPress: onKeyPress),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _Numpad extends StatelessWidget {
  final ValueChanged<String> onKeyPress;

  const _Numpad({required this.onKeyPress});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          _buildRow(['1', '2', '3']),
          const SizedBox(height: 20),
          _buildRow(['4', '5', '6']),
          const SizedBox(height: 20),
          _buildRow(['7', '8', '9']),
          const SizedBox(height: 20),
          _buildRow(['.', '0', 'back']),
        ],
      ),
    );
  }

  Widget _buildRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: keys.map((key) {
        if (key == 'back') {
          return _NumpadKey(
            child: Icon(
              Icons.backspace_outlined,
              color: AppColorTokens.light.textPrimary,
            ),
            onTap: () => onKeyPress('back'),
          );
        }
        return _NumpadKey(
          child: Text(
            key,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: AppColorTokens.light.textPrimary,
            ),
          ),
          onTap: () => onKeyPress(key),
        );
      }).toList(),
    );
  }
}

class _NumpadKey extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  const _NumpadKey({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 80,
        height: 60,
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}
