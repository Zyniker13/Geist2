# 0018 — iPad split view and the deep-link hook

Date: 2026-11-25
Status: Accepted

## Context

M4.1's fixed choice is "split view on iPad and Mac, stacks on iPhone."
The root view had implemented that as `#if os(macOS)` → split view,
everything else → stack, which gave iPad the iPhone's single-column
stack. A simulator screenshot caught it after several milestones had
shipped on top of the mistake.

The `-openFirstRecipe` deep-link hook (decision 0016) meanwhile pushed
onto the `NavigationPath` only, so it showed the detail in the stack
but never populated the split view's detail pane, whose content binds
to `library.selection`.

## Decision

- One `RootLayout` view chooses the layout from
  `@Environment(\.horizontalSizeClass)`: `.regular` →
  `NavigationSplitView` with the detail bound to `library.selection`,
  `.compact` → `NavigationStack` driven by the shared
  `NavigationPath`. Platform `#if`s stay for the Mac's own root only.
  This also makes iPad split-screen behave correctly for free.
- Row taps set `library.selection` on every platform. On the stack the
  value is inert; on split views it drives the detail pane, so the
  same code serves iPad, Mac, and iPad split-screen.
- The `-openFirstRecipe` hook sets `library.selection` and appends to
  the path together, with no size-class branch and no settle delay.
  An early attempt branched on the size class inside a delayed task
  and failed on iPad (the selection branch never took effect);
  setting both unconditionally is simpler and layout-agnostic — each
  layout reads the value it uses and ignores the other.
- iPad search uses `.toolbar` placement (like the Mac) instead of the
  iPhone's navigation-bar drawer; both handled in
  `LibraryView.searchablePlacement` by size class.

## Consequences

- iPad and iPhone share one layout chooser; the split view appears at
  any regular-width size class (including iPhone landscape on large
  models and iPad split-screen), matching the fixed choice's intent.
- The hook is now one unconditional write; the AX tests that rely on
  it keep working on both layouts without per-device branches.
- Fresh iPad screenshots (`m4.4-ipad-library.png`,
  `m4.4-ipad-detail.png`) replace the single-column ones that
  documented the regression.
