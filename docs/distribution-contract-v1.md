# Distribution contract v1 (implementation target)

Repository: YzLfireChiYv/VF_RIME. Windows x64 bootstrapper, paired x64+Win32 IME clients.
The daily schema remains platform-aware; this Windows installer does not claim to install Squirrel/fcitx5.

Use .NET 10 LTS Windows Forms, self-contained single-file win-x64, without trimming.
Online and offline EXEs share the same installation engine. Offline embeds the complete
verified payload manifest and bytes; an incomplete payload MUST fail offline packaging.
Do not require users to install .NET, Python, Git or a database separately.

Small pointers: updates/stable.json and updates/nightly.json (schema_version=1, channel,
available). available=false is an explicit unavailable state and must show a useful message.
An available pointer identifies release_id and manifest_url/manifest_sha256; the immutable
release manifest supplies component roles, URLs, exact bytes/SHA256 and compatibility bundle.
Use conditional HTTP/ETag. Avoid GitHub API and full assets when nothing changed.
Fetch upstream fixed bytes, then identical project mirror bytes; never silently change versions.
No arbitrary executable command strings in remote metadata.

Components: bootstrapper, paired-native, schema, dictionary and gram. Native and schema
compatibility revisions are checked before applying. No partial mixed ABI installation.
Stable promotion is explicit and happens after assets exist and are verified; nightly
publication only changes nightly. Ordinary users remain on stable.

Protect personal custom/userdb/input history/sync identity and do not replace their directories.
Stage downloads first; preserve old owned files, journal application and restore owned files
on failure. Native registration follows upstream installer/setup; request elevation only
for system installation. Keep the original user's profile path when elevation uses another
account. Locked DLL replacement may require a reboot; do not reboot automatically.

Only explicitly approved source/data allowlists enter public payloads. Retain all third-party
notices and adapted data terms. No local absolute paths or private Git history in release files.

The initial scheduled workflow only checks the reviewed source preview. The CI worker must
connect actual bootstrapper publishing and full payload builds before claiming nightly EXEs.
Use public standard runners only, no paid larger runners/Packages/LFS or billing changes.
Avoid Actions artifact storage for bulky packages; use Release assets and bounded cache.
