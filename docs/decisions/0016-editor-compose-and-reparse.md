# 0016 — The editor composes rows and re-parses them

Date: 2026-11-25

## Context

M4.3 needs a recipe editor. Two shapes were possible: edit the
structured `IngredientLine` fields directly (amount stays a Decimal,
unit stays an identifier), or edit human text and parse it. Editing
Decimals directly means the editor must duplicate every parse escape
hatch (ranges, "to taste", free text) as UI, and any field the UI
cannot express is unreachable. Editing free text means the row's
meaning can drift from its structure.

## Decision

Each editor row keeps separate fields for what a cook edits most
(amount, unit, item, preparation, note, optional, to taste), and
`EditableIngredientRow.text` composes them into one string. Saving
parses that string through `IngredientParser` — the same parser import
uses — so the stored line and the display pipeline see exactly what
they would see from an import. Amounts compose with kitchen
fraction spelling and ranges with "to"; preparation composes with a
leading comma (the parser's preparation split point).

Paste-lines mode feeds raw pasted lines to the same parser, and
section headers ("For the marinade:") open new sections.

The yield amount field also parses "1 1/2" (fraction first, because
`Decimal(string:)` silently reads that string as 1).

## Consequences

- One parse path: an editor-entered line, a pasted line and an
  imported line are indistinguishable downstream; the M2 corpus and
  517-line exactness guarantee cover them all.
- An unparseable row degrades the way imports do: the line round-trips
  as an item-only line, and the editor surfaces a problem note instead
  of blocking the save.
- Reorder (drag to move) is not in this milestone; rows are added,
  removed and pasted. Reordering lands with M4.4 polish if it proves
  needed in use.
- Timers are detected from step text at save (the import path's
  detection) and may also be added by hand as minutes.
