# Phase 16: Stitch Workflow & Design Reference - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-03-28
**Phase:** 16-stitch-workflow-design-reference
**Areas discussed:** Mockup scope & fidelity, Stitch-to-Flutter workflow, Visual spec format & storage, Palette reconciliation

---

## Mockup Scope & Fidelity

| Option | Description | Selected |
|--------|-------------|----------|
| High-fidelity | Full visual detail — earthy palette, real typography, realistic data, proper spacing | ✓ |
| Mid-fidelity wireframes | Layout and hierarchy clear, earthy palette, placeholder content and approximate spacing | |
| Layout-only sketches | Structural layout without visual styling | |

**User's choice:** High-fidelity
**Notes:** None

### Screen States

| Option | Description | Selected |
|--------|-------------|----------|
| Loaded (primary state) | Screen with realistic data | ✓ |
| Empty state | First-time user experience, illustrated CTA | ✓ |
| Loading/skeleton | Skeleton placeholder while data loads | ✓ |
| Error state | Data fetch failure, retry prompt, offline banner | ✓ |

**User's choice:** All 4 states
**Notes:** None

### Content Style

| Option | Description | Selected |
|--------|-------------|----------|
| Realistic Omani context | Omani names, OMR amounts, real trip types | |
| Generic placeholder | User 1, User 2, $10.00, Trip A — neutral content | ✓ |
| You decide | Claude picks contextually appropriate content | |

**User's choice:** Generic placeholder

### Screen Priority

| Option | Description | Selected |
|--------|-------------|----------|
| Equal depth for all 3 | Home, Group Detail, Event Hub each get full treatment | ✓ |
| Home first, others lighter | Home deepest; others loaded + empty only | |
| Home + Group Detail deep | Event Hub lighter treatment | |

**User's choice:** Equal depth for all 3

### Home Screen Layout

| Option | Description | Selected |
|--------|-------------|----------|
| All 4 sections | Balance hero, group cards, quick-action tray, activity strip | ✓ |
| Core 3 + defer activity | Balance hero, group cards, quick actions only | |
| Let me describe it | Custom layout vision | |

**User's choice:** All 4 sections (matches NAV-01)

### Group Detail Density

| Option | Description | Selected |
|--------|-------------|----------|
| Dense dashboard | All data visible without scrolling | ✓ |
| Card-based sections | Scrollable, spacious, breathing room | |
| You decide | Claude picks appropriate density | |

**User's choice:** Dense dashboard

### Event Hub Module Presentation

| Option | Description | Selected |
|--------|-------------|----------|
| Module grid with status | Cards show live summary + module accent color | ✓ |
| Compact list with icons | Vertical list, more info density, less visual weight | |
| Hero + modules below | Event summary hero at top, module grid below | |
| You decide | Claude designs optimal layout | |

**User's choice:** Module grid with status

### Responsive Design

| Option | Description | Selected |
|--------|-------------|----------|
| Single breakpoint (~390px) | One layout fits most devices | ✓ |
| Two sizes (small + large) | Compact + expanded variants | |
| You decide | Claude determines responsive considerations | |

**User's choice:** Single breakpoint

---

## Stitch-to-Flutter Workflow

### Stitch Role

| Option | Description | Selected |
|--------|-------------|----------|
| Visual oracle only | Extract layout ideas, never commit Stitch code | ✓ |
| Layout scaffold + token swap | Use Stitch layout as starting point, replace hardcoded values | |
| Full code extraction with review | Use Stitch output as working code, fix tokens/naming | |

**User's choice:** Visual oracle only (matches PROJECT.md guidance)

### Stitch Inputs

| Option | Description | Selected |
|--------|-------------|----------|
| Palette hex values | Feed earthy palette for correct color output | ✓ |
| Screen descriptions | Natural language describing screen contents | ✓ |
| Current screenshots | Screenshots of existing screens for redesign context | ✓ |
| Component inventory | List of existing shared widgets | ✓ |

**User's choice:** All 4 inputs

### Post-Generation Checklist

| Option | Description | Selected |
|--------|-------------|----------|
| Color token mapping | Every color maps to existing token | ✓ |
| Spacing consistency | Follows token scale | ✓ |
| Component reuse check | Uses existing widgets where possible | ✓ |
| Accessibility check | Contrast, touch targets, interactive distinction | ✓ |

**User's choice:** All 4 checks

### Execution Model

| Option | Description | Selected |
|--------|-------------|----------|
| User runs Stitch manually | User does everything, Claude documents | |
| Claude documents workflow | Phase deliverable is process doc, not mockups | |
| Hybrid | Claude prepares prompts + checklist; user runs Stitch; Claude annotates | ✓ |

**User's choice:** Hybrid

### Prompt Format

| Option | Description | Selected |
|--------|-------------|----------|
| Standalone prompt files | One .md per screen in prompts/ directory | ✓ |
| Embedded in workflow doc | Prompts inside CLAUDE.md documentation | |
| You decide | | |

**User's choice:** Standalone prompt files

### Stitch Configuration Guidance

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, prescriptive | Document which Stitch settings to use | |
| No, user knows Stitch | Skip Stitch config, focus on pipeline | ✓ |
| You decide | | |

**User's choice:** No guidance needed

### Iteration Rounds

| Option | Description | Selected |
|--------|-------------|----------|
| 1-2 rounds | Generate, review checklist, refine once if needed | ✓ |
| As many as needed | Iterate until right | |
| Single shot | One generation, accept result | |

**User's choice:** 1-2 rounds

### Reusability

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, template for all phases | General workflow for phases 20-22 to follow | ✓ |
| Phase 16 only | Just get 3 screens done | |
| You decide | | |

**User's choice:** Reusable template

---

## Visual Spec Format & Storage

### Format

| Option | Description | Selected |
|--------|-------------|----------|
| Annotated design doc | Markdown per screen, text-first, images as reference | ✓ |
| Image gallery + notes | Screenshots as PNGs with brief index | |
| Structured spec per screen | Formal spec with every widget/token/spacing value | |
| You decide | | |

**User's choice:** Annotated design doc

### Implementation Hints

| Option | Description | Selected |
|--------|-------------|----------|
| Visual + structural hints | Describe layout structure alongside visual | ✓ |
| Purely visual | Only appearance, no implementation guidance | |
| You decide | | |

**User's choice:** Visual + structural hints

### Location

| Option | Description | Selected |
|--------|-------------|----------|
| .planning/design/ | Dedicated design directory | ✓ |
| Inside phase 16 directory | Colocated with phase artifacts | |
| docs/design/ | Part of codebase, survives archival | |

**User's choice:** .planning/design/

### Image Storage

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, in .planning/design/images/ | Committed alongside specs | |
| No, external only | Stored outside repo, referenced by URL | ✓ |

**User's choice:** External only — keeps repo lean

### Token Mapping Table

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, mandatory | Every spec includes visual element → token reference table | ✓ |
| Inline references only | Token names mentioned in descriptions | |
| You decide | | |

**User's choice:** Mandatory token mapping table

### Spacing Specification

| Option | Description | Selected |
|--------|-------------|----------|
| Section-level spacing | Major section gaps only, using token names | |
| Full spacing spec | Every level — sections, cards, padding, line-height | ✓ |
| You decide | | |

**User's choice:** Full spacing spec

### Interaction Notes

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, navigation + key interactions | Tap/swipe behavior, transition types | ✓ |
| Visual only, no interactions | | |
| You decide | | |

**User's choice:** Include navigation + key interactions

### Widget References

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, map to existing widgets | Specs reference ModuleHeader, EmptyStateView, etc. | ✓ |
| No, describe visually only | | |

**User's choice:** Map to existing widgets

---

## Palette Reconciliation

### Color Drift Handling

| Option | Description | Selected |
|--------|-------------|----------|
| Snap to nearest token | Phase 15 tokens are source of truth | ✓ |
| Flag for review | Document both values, decide per-case | |
| Update tokens if Stitch is better | Allow Phase 15 tokens to be updated | |

**User's choice:** Snap to nearest token

### WCAG Verification

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, verify against Phase 15 matrix | All pairs checked, no new unverified combinations | ✓ |
| Trust Phase 15 tokens | Only check if new combinations introduced | |
| You decide | | |

**User's choice:** Verify against Phase 15 matrix

### New Token Discovery

| Option | Description | Selected |
|--------|-------------|----------|
| Document and defer | Note need, add token in implementation phase | |
| Add tokens in this phase | Keep token system complete as design artifact | |
| You decide | Claude judges per-case | ✓ |

**User's choice:** Claude's discretion

---

## Claude's Discretion

- Whether to add new tokens in Phase 16 or defer to implementation phases (per-case judgment)
- Exact Stitch prompt wording and structure
- Level of annotation detail beyond mandatory token mapping table
- Organization of design docs within `.planning/design/`

## Deferred Ideas

None — discussion stayed within phase scope
