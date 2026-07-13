/// One line item on an itemized bill (#203). Display-only metadata that
/// reconstructs the itemized editor on reopen; balance truth lives in the
/// expense's `splitDistribution` (persisted as `SplitMode.exact`).
///
/// [amountFils] is the integer-subunit LINE TOTAL (quantity already folded in
/// by the editor). [quantity] is display-only ("2× Coffee"); the allocator
/// never multiplies by it. [allocation] is `'equal'` in v1.
class SplitItem {
  final String label;
  final int amountFils;
  final int quantity;
  final List<String> participantIds;
  final String allocation;

  const SplitItem({
    required this.label,
    required this.amountFils,
    this.quantity = 1,
    required this.participantIds,
    this.allocation = 'equal',
  });

  /// Lenient read for display reconstruction — tolerates missing/garbage keys
  /// and never throws. (The producer `BalanceCalculator.allocateItemizedDistribution`
  /// is the STRICT side: it rejects negative `amountFils` / zero-assignee items.
  /// So a forged persisted item displays fine but must be re-validated by the
  /// editor before it is re-fed to the allocator on resave.)
  factory SplitItem.fromMap(Map<String, dynamic> map) {
    return SplitItem(
      label: map['label'] as String? ?? '',
      amountFils: (map['amountFils'] as num?)?.toInt() ?? 0,
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      participantIds:
          (map['participantIds'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      allocation: map['allocation'] as String? ?? 'equal',
    );
  }

  Map<String, dynamic> toMap() => {
    'label': label,
    'amountFils': amountFils,
    'quantity': quantity,
    'participantIds': participantIds,
    'allocation': allocation,
  };
}

/// Canonical bill-level adjustment types (#605). Additive = anything but
/// `'discount'` (service/tax/tip ADD; discount SUBTRACTS). The allocator's
/// strict allow-list, the l10n labels, and the tests all reference this one set.
const Set<String> kAdjustmentTypes = {'service', 'tax', 'tip', 'discount'};

/// One bill-level adjustment on an itemized expense (#605): service charge, tax,
/// tip (each ADDS) or discount (SUBTRACTS). Display-only metadata like
/// [SplitItem] — balance truth is the folded `splitDistribution`.
///
/// [amountFils] is the positive magnitude in integer subunits; the SIGN is
/// derived from [type] ('discount' subtracts, all others add). [allocation] is
/// `'equal'` (spread across the whole table) or `'proportional'` (by each
/// person's item subtotal). A 'discount' is always folded proportional to each
/// person's pre-discount owed regardless of this field (that is what guarantees
/// non-negativity); the editor normalizes a discount's [allocation] to
/// `'proportional'` on write.
///
/// Lenient [fromMap] (display reconstruction, never throws) vs strict producer:
/// `BalanceCalculator.allocateItemizedDistribution` rejects an unknown [type] or
/// a negative [amountFils] on the write path, so a forged doc displays fine but
/// cannot resave a bad fold.
class SplitAdjustment {
  final String type;
  final int amountFils;
  final String allocation;

  /// Who bears an `'assigned'` discount (#605). Null/empty for every other
  /// type/allocation (the key is omitted on write). Display-only, like every
  /// field here — the balance truth is the folded `splitDistribution`. Lenient
  /// [fromMap] tolerates anything; the producer
  /// `BalanceCalculator.allocateItemizedDistribution` is the STRICT side (it
  /// requires a non-empty subset ⊆ the participant table for an assigned
  /// discount, else `ArgumentError`).
  final List<String>? participantIds;

  const SplitAdjustment({
    required this.type,
    required this.amountFils,
    this.allocation = 'equal',
    this.participantIds,
  });

  factory SplitAdjustment.fromMap(Map<String, dynamic> map) {
    return SplitAdjustment(
      type: map['type'] as String? ?? 'service',
      amountFils: (map['amountFils'] as num?)?.toInt() ?? 0,
      allocation: map['allocation'] as String? ?? 'equal',
      participantIds:
          (map['participantIds'] as List?)?.map((e) => e.toString()).toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'type': type,
    'amountFils': amountFils,
    'allocation': allocation,
    if (participantIds != null && participantIds!.isNotEmpty)
      'participantIds': participantIds,
  };
}

/// Opaque display metadata for an itemized expense (#203). Reconstructs the
/// itemized editor on reopen. **INBOUND/display-only** — NEVER read by balance
/// math, the server oracle (`recomputeNet`), or any Cloud Function; balance
/// truth is the expense's `splitDistribution`. `firestore.rules` guards it as
/// `is map` + a bounded top-level entry count only (opaque).
class SplitExplanation {
  final String type;
  final int version;
  final List<SplitItem> items;

  /// Bill-level adjustments (#605: service/tax/tip/discount), folded into the
  /// exact `splitDistribution` at save. Display-only, like [items] — additive,
  /// no schema version bump. Null or empty ⇒ the key is omitted on write.
  final List<SplitAdjustment>? adjustments;

  const SplitExplanation({
    this.type = 'itemized',
    this.version = 1,
    required this.items,
    this.adjustments,
  });

  factory SplitExplanation.fromMap(Map<String, dynamic> map) {
    return SplitExplanation(
      type: map['type'] as String? ?? 'itemized',
      version: (map['version'] as num?)?.toInt() ?? 1,
      items:
          (map['items'] as List?)
              ?.whereType<Map>()
              .map((e) => SplitItem.fromMap(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      adjustments: (map['adjustments'] as List?)
          ?.whereType<Map>()
          .map((e) => SplitAdjustment.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
    'type': type,
    'version': version,
    'items': [for (final i in items) i.toMap()],
    if (adjustments != null && adjustments!.isNotEmpty)
      'adjustments': [for (final a in adjustments!) a.toMap()],
  };
}
