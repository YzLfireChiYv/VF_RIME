# Framework review subset

These 18 modules are original framework/control adapters, exported under MIT with
per-file source and export hashes in ORIGINS.json. They are not a standalone schema.

Dependencies deliberately not bundled include super_lookup, super_tips,
super_filter, super_comment_preedit, super_english and wanxiang; inherited parts
retain their own upstream attribution/license. Older business modules such as
interaction, clock, snippets, calc, hot, unicode_mode, session, letters,
slash_cmd and pinyin_shape also need separate review before a full scheme release.
Native Component/Context APIs come from the pinned Rime/Lua source combination.

Do not add unknown dictionaries or copy personal modules to make this subset seem
self-contained. Use ../examples/association_demo (from the package root) for the
newly authored, dependency-free sample. Full schema dependency closure remains a
follow-up publication task; nothing here claims a complete production scheme.
