// Layout metrics shared by the embedded event-workspace panels (#758/#789).

/// Bottom content inset the Expenses panel reserves so its last scrollable
/// row clears the workspace's floating "+ Add expense" pill (positioned
/// `bottom: 16`, ~45px tall → its top sits ~61px above the scroll bottom; 72
/// leaves comfortable breathing room).
///
/// Expenses-only since #1078: the pill is gated to its own tab, so Settle up
/// / Activity / Recap are FAB-free and use the standard gutter — don't
/// re-add this inset there without re-introducing a FAB above them.
const double kEmbeddedEventPanelFabClearance = 72;
