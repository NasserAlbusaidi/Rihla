# Feature Landscape

**Domain:** Group-based event planning with persistent cross-event expense tracking
**Researched:** 2026-03-26
**Confidence:** HIGH for expense-splitting features (strong market data), MEDIUM for template/preset patterns (limited direct comparables), HIGH for anti-features (well-documented pitfalls)

---

## Context: The Market Gap Rihla Fills

The core tension in competitor apps is well-documented: Splitwise users have filed repeated feature requests asking for "events inside groups" — the ability to see per-trip balances within a persistent friend circle. Splitwise's response has always been "create a separate group," which users hate because:

1. Group proliferation becomes unmanageable
2. Cross-group totals collapse into an undifferentiated home-screen number
3. You lose the social history — who joined which trip, who you always owe

No mainstream app does groups-as-containers-for-events well. This is Rihla's structural advantage. The features below are evaluated in that context.

---

## Table Stakes

Features users expect. Missing = the app feels incomplete or broken.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Add expense with split | Core reason to open the app | Low | Already exists. Must support equal, exact, and custom splits |
| View who owes whom | Primary output users check | Low | Already exists (balance calculator) |
| Debt simplification | Reduces N transactions to minimum payments; users expect this from Splitwise | Medium | Already exists (greedy min-transactions). Must work at group level too |
| Multi-currency support | Expected for any travel-adjacent app | Medium | Already exists (OMR-focused, but multi-currency present) |
| Offline capability | Users log expenses in the field without signal | Medium | Already exists. Must not regress during Firestore migration |
| Activity feed | Users want to see what changed and who did it | Low | Already exists per-event. Needs group-level feed too |
| Push notifications for balance changes | Users expect nudges when money is owed | Low | Already exists (FCM). Extend to group-level events |
| Invite via shareable link | Creating accounts is friction-killer; link-join is the standard | Low | Already exists for trips. Must extend to group join flow |
| Expense history | Users scroll back to see "what did we spend on that camping trip" | Low | Already exists per-event |
| Settlement recording | Mark debts as paid | Low | Already exists |
| Persistent group across events | Users want "my friend circle" not "a new group per trip" | High | This is the new layer. The whole point of the milestone |
| Event timeline in group | Chronological list of past + upcoming events | Medium | Active requirement in PROJECT.md |
| Group member list | Who is in my group | Low | Straightforward — needed before anything else works |
| Group-level running balance | Net balance per member across ALL events in the group | High | The killer feature. Already called out in PROJECT.md as core value |
| Create event from group | Spin up a new event with group members pre-populated | Medium | Prevents re-inviting the same people each time |

---

## Differentiators

Features that give Rihla competitive advantage. Not universally expected, but strongly valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Event types with templates | Picking "Camping" pre-fills gear list, suggests modules, reduces setup time | Medium | No competitor does this. Tricount and Splitwise have zero event-type awareness |
| Template gear presets | Camping = tent, sleeping bag, stove auto-added; Night Out = different set | Medium | Users will feel the app "knows what they need" — reduces coordination overhead |
| Template-driven module visibility | Trip type controls which modules appear (gear, logistics, vault, etc.) | Medium | Prevents overwhelm. Custom events = user selects manually |
| Per-event vs. group balance toggle | See "what this trip cost" vs. "what I owe you across everything" | Medium | This is the feature Splitwise users have been requesting for years with no resolution |
| Group spending stats | Total spent across all events, per-member contribution history, busiest periods | High | Satisfaction feature — makes group history feel alive and real |
| Group event history with financial totals | Each past event shows its total spend inline | Low-Medium | Trivial to display once data model supports it; high perceived value |
| Sub-group awareness within events | Car assignments, tent groups — Rihla already does this; no competitor does | Medium | Already exists. Market differentiator worth highlighting in UX |
| Offline-first with real sync | Tricount has offline; Splitwise does not — Rihla's offline-first is genuinely differentiated | Ongoing | Maintenance, not a new build |
| Anonymous auth / no account required | Reduces join friction to near zero; joiners just pick a name | Low | Already exists. Extend carefully to group join flow |
| Cross-event settle-up suggestion | "You owe Nasser 15.500 across 3 events — settle now?" | High | This is the emotional payoff of the whole architecture. Worth investing in |
| Group activity log | "Ahmed added camping trip", "Sara settled up with Khalid" — group-level narrative | Medium | Makes the group feel like a living social space |

---

## Anti-Features

Features to deliberately NOT build. Each one is a complexity trap or a distraction from core value.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| In-app chat / messaging | Every messaging product that tried to bolt on expense splitting failed at both. High complexity, low retention lift for this user base. Splitwise famously scoped this out. | Let WhatsApp do messaging. Rihla does money. |
| Real-time collaborative editing (Google Docs-style) | The coordination overhead to make this work correctly is enormous. Firestore makes it tempting, but conflict resolution is a product rabbit hole. | Last-write-wins for expenses is fine. Activity feed covers visibility. |
| Payment processing / in-app transfers | Thawani is scoped for specific OMR use. Going further (bank integrations, actual money movement) is a compliance and regulatory minefield. | Record settlement intentions. Let people pay via their own means. |
| Complex roles and permissions (admin, editor, viewer) | Users in friend groups do not think in org-chart terms. Any permission model beyond "member / non-member" will confuse and alienate. Splitwise's own feedback board has requests for this that they have correctly ignored. | Keep it flat: you're in the group or you're not. |
| Analytics / spending insights dashboard | "You spend most in Q3" — this is feature theatre. No one opens an expense app to get spending insights. They open it to know what they owe. | Show balances. Show totals. Stop there. |
| Event ticketing / RSVP / attendance management | This pivots the product toward event management, not expense coordination. Different jobs to be done. | Events are "you're going or not" — record who's in, move on. |
| Social feed / reactions / likes on expenses | Splitwise experimented with social features; users found them creepy on financial transactions. | Stick to factual activity: "X added expense", "Y settled up". No emoji reactions on debts. |
| AI-generated expense categorization | Requires ML infrastructure, degrades offline reliability, and the categorization accuracy for OMR/Oman-specific merchants will be poor. | Manual categories with sensible defaults are sufficient. |
| Web app / desktop version | Mobile-first. The coordination value happens in the field. Flutter-web is a future concern, not now. | Mobile only. |
| Recurring expenses | Relevant for household apps (rent, utilities). For event-based groups, expenses are one-off. | Adds model complexity with no payoff for the event-planning use case. |
| Budget planning / forecast mode | Pre-trip budgets are appealing in theory; in practice users add expenses retroactively and never use the forecast. | Record actuals. Skip forecasts. |

---

## Feature Dependencies

```
Group creation
  → Group member list
    → Create event from group (members pre-populated)
      → Event template selection
        → Template-driven module visibility
          → Template gear presets (for camping/trip types)
      → Per-event expense tracking (existing)
        → Per-event balance view (existing)
          → Group-level running balance (aggregates per-event balances)
            → Cross-event settle-up suggestion
              → Settlement recording at group level

Group join via link
  → Group member list
    → All above

Group event timeline
  → Group event history with financial totals (requires group-level balance)

Group activity log
  → Group creation (exists to attach to)
  → Any write operation (expense, settlement, event creation) emits to log
```

Key insight: **Group-level running balance is the central dependency.** Almost all differentiating features build on it. It must be designed correctly before building anything on top. If the data model for cross-event balance aggregation is wrong, everything downstream needs to change.

---

## MVP Recommendation

Build in this order to deliver value as early as possible and de-risk the hard parts first:

**Phase 1 — Persistent Groups (foundation)**
1. Group creation and join-via-link
2. Group member list
3. Create event from group (with type selection)
4. Group event timeline (chronological list)

**Phase 2 — Group Financial Layer (the payoff)**
5. Group-level running balance (net balance per member across events)
6. Per-event vs. group balance toggle in UI
7. Cross-event settle-up suggestion
8. Group activity log

**Phase 3 — Templates and Differentiation**
9. Event type templates with gear presets
10. Template-driven module visibility

**Defer indefinitely:**
- Group spending stats (analytics)
- Complex member permissions
- Any feature in the Anti-Features table above

**Hard constraints that must not slip:**
- Offline-first must work for all new group/event features
- Financial precision (Decimal, OMR 3dp) must not regress
- Anonymous auth join flow must remain frictionless

---

## Sources

- [Splitwise user feedback: trip/event inside group request](https://feedback.splitwise.com/forums/162446-general/suggestions/13100073-add-a-trip-or-event-feature-inside-a-group-among)
- [Splitwise feedback: subgroups request](https://feedback.splitwise.com/forums/162446-general/suggestions/11323461-subgroups)
- [Splitwise: what is simplify debts](https://www.splitwise.com/l/sdv/c1mHsiFUb9x)
- [Splitwise vs Tricount feature comparison](https://tricount.com/splitwise-vs-tricount)
- [Tricount expense tracker features](https://tricount.com/expense-tracker-features)
- [Top Splitwise alternatives 2026 — SquadTrip](https://squadtrip.com/guides/top-splitwise-alternatives-for-group-travel-expenses/)
- [Settler vs Splitwise vs Tricount comparison 2025](https://getsettler.com/blog/settler-vs-splitwise-vs-tricount)
- [Best group travel planning apps 2025 — AvoSquado](https://www.avosquado.app/blog/best-group-travel-planning-apps-in-2025-complete-comparison)
- [Group member management: Splitwise admin permissions FAQ](https://feedback.splitwise.com/knowledgebase/articles/264547-can-i-set-a-group-admin-or-set-different-permis)
- [Splitwise spending summary and analytics feedback](https://feedback.splitwise.com/forums/162446-general/suggestions/6513831-please-introduce-a-way-to-view-total-spend-indiv)
