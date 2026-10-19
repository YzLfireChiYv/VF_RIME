# Source and build preparation

The source trees are reproducible from upstream commits plus the included patches;
the assembler checked all three resulting Git tree hashes with private indexes.
This is not a claim that clean-machine Windows binary builds have been reproduced.

```text
python tools/prepare_sources.py
python tools/prepare_sources.py --fetch --destination source-preview --with-deps
```

The first command prints a plan only. The second explicitly downloads into a NEW
directory and leaves patches staged on their upstream bases. It never installs
anything. This download path has not been run as part of the local preparation.

The modified core lives in weasel/librime and the three pinned plugins under its
plugins directory. Do not recursively reset Weasel's old librime gitlink over it.
Submodule sources and their notices remain governed by the respective upstreams.
Lua runtime 5.4.8 is a separate source dependency; the official archive URL and
SHA256 are pinned in SOURCE-LOCK.json. Its build placement must match librime-lua's
build scripts; no local untracked thirdparty tree is silently copied into this pack.

Windows baseline used VS2022/v143, SDK10.0.26100.0, CMake Release and static runtime.
Build dependencies separately for x64 and x86; build the modified core with the
explicit lua,octagram,predict plugin set, then make Weasel consume its newly
exported headers/import library/DLL. Build x64 server/deployer plus x64 and Win32
clients. Win32 clients support 32-bit applications on 64-bit Windows.

Upstream build starting points:
https://github.com/rime/weasel
https://github.com/rime/librime
https://github.com/hchunhui/librime-lua

Still required before a reproducible binary release: machine-independent Boost
and dependency setup, Lua runtime placement, generated Weasel properties and
CI on a fresh Windows environment. Existing local binaries/SDK paths are not
distributed as substitutes for those steps. Build output and installation must
remain separate; no system DLL replacement is performed by these tools.
