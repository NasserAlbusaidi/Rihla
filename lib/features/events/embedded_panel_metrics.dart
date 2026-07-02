// Layout metrics shared by the embedded event-workspace panels (#758/#789).

/// Bottom content inset the FAB-bearing embedded panels (Expenses · Settle up ·
/// Activity) reserve so their last scrollable row clears the workspace's
/// floating "+ Add expense" pill (positioned `bottom: 16`, ~45px tall → its top
/// sits ~61px above the scroll bottom; 72 leaves comfortable breathing room).
///
/// Recap is intentionally excluded: the Recap tab exists only on a closed
/// event, where the pill is hidden — there is nothing to clear.
const double kEmbeddedEventPanelFabClearance = 72;
