# License and provenance scope

Weasel upstream declares GPLv3; librime and librime-lua use BSD-3-Clause. Their
license texts are copied verbatim in LICENSES, and source patches retain original
notices. Reconstructing sources from the official bases retains their full source
and notices. Original framework modules, new examples and helper code use MIT,
as selected by the project owner; this does not relicense upstream components.

Runtime dependencies not bundled in this preview include Lua, OpenCC, Boost,
glog, leveldb, yaml-cpp, marisa and others pinned by the upstream repositories.
The optional octagram/predict sources are also obtained separately. Inspect their
actual license/notice files when building or packaging binaries. This preview
does not assert a completed binary-package SBOM.

Wanxiang inherited Lua and configuration dependencies are not included in the
review subset. Their attribution and actual versions must remain explicit when
the complete scheme is prepared. Wanxiang's v18.1.5 repository declares CC BY4.0;
that declaration is not authority to relicense unrelated mapping or corpus data.

The two current English tables, OpenCC emoji/other/group tables and embedded
emoji_group_data are excluded because their full provenance is unresolved.
Private words, snippets, spoken.txt and user databases are excluded separately.
No existing data is relabeled as MIT. Moegirl data is also not bundled; any later
optional data release must retain its own actual terms, including NC-SA where
applicable, rather than treating public download as blanket permission.
