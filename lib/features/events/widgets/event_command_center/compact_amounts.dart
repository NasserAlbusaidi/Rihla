import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../../../../shared/widgets/r_amount.dart';
import '../../keys/event_keys.dart';

/// Small per-currency amounts shown beside the title while collapsed.
class CompactAmounts extends StatelessWidget {
  const CompactAmounts({super.key, required this.lines});

  final List<({String currency, Decimal net})> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: EventKeys.headerCompactAmount,
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final line in lines)
          RAmount(
            value: line.net,
            currency: line.currency,
            size: 12,
            weight: FontWeight.w700,
            sign: true,
            tone: line.net > Decimal.zero ? AmountTone.sage : AmountTone.rust,
          ),
      ],
    );
  }
}
