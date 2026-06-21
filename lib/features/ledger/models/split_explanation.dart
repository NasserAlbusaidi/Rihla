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

/// Opaque display metadata for an itemized expense (#203). Reconstructs the
/// itemized editor on reopen. **INBOUND/display-only** — NEVER read by balance
/// math, the server oracle (`recomputeNet`), or any Cloud Function; balance
/// truth is the expense's `splitDistribution`. `firestore.rules` guards it as
/// `is map` + a bounded top-level entry count only (opaque).
class SplitExplanation {
  final String type;
  final int version;
  final List<SplitItem> items;

  /// RESERVED for #605 (bill-level adjustments: service/tax/tip/discount).
  /// Slice 1 round-trips it opaquely so a #605-written doc never loses its
  /// adjustments when read here. Additive — no schema version bump.
  final List<dynamic>? adjustments;

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
      adjustments: map['adjustments'] as List?,
    );
  }

  Map<String, dynamic> toMap() => {
    'type': type,
    'version': version,
    'items': [for (final i in items) i.toMap()],
    if (adjustments != null) 'adjustments': adjustments,
  };
}
