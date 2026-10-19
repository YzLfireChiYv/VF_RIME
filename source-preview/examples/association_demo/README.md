<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 YzLfireChiYv -->

# Minimal association example

This small, dictionary-free Rime schema demonstrates real candidate payloads,
source/associated relationships and attached output rows. It is an API example,
not the complete input method or its production shortcut policy. The three files
are newly authored examples licensed under MIT; see the distribution's MIT
license text. Rime and its plugins retain their own licenses.

Place `association_demo.schema.yaml` in a **separate test** Rime user directory,
and place `lua/association_demo.lua` in that directory's `lua` folder. Add
`association_demo` to the test directory's `default.custom.yaml` schema list and
deploy normally. No dictionary, gram, user database, network service or external
Lua module is required. Rime with librime-lua is required.

Type `demo`. The common preset creates `示例`, two local time/date formats and
three emoji examples. The English preset creates `示例`, `example`, `sample`
and `demonstration`. These deliberately small mappings illustrate the data model;
they are not translations generated from a complete dictionary. Time values are
captured when the candidates are generated; selection commits that candidate's
stored text without recomputing it.

While the exact input `demo` is active:

- `Ctrl+F13` selects common (emoji plus local time/date).
- `Ctrl+F15` selects English mapping.
- Digits, Space, Up/Down and other ordinary candidate operations use Rime's
  native selector/editor. This example does not provide production caret rules.
- In rod presentation, `Ctrl+1` selects the first output row attached to the
  highlighted main candidate. If that candidate has no row, it does nothing.
- Other Ctrl/Alt/Super shortcuts pass to the application without explicitly
  committing the composition. No ordinary shortcut is repurposed outside this
  exact demo composition. There are no hold gestures or repeated-key state.

Preset selection is idempotent and session-local. It does not implement the
production F13 two-preset cycle, arbitrary nesting or translation software calls.

The default `association_demo/presentation: flat` exposes every output as an
ordinary, individually selectable candidate, including on unmodified frontends.
To examine the matching fork's native rods, change this setting to `rods` in the
**test** schema and deploy again. This uses Interaction `source`, `associated`
and `output` objects; it does not encode hidden selection metadata in comments.
Use the matching modified librime, librime-lua and Weasel client together for
the rod UI. If the Lua Interaction API is absent, `rods` automatically uses flat
candidates instead. A modified core with an unmodified frontend should keep the
explicit `flat` setting: API presence alone does not prove UI support.

