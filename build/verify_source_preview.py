from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[1]/"source-preview"
manifest=json.loads((root/"MANIFEST.json").read_text(encoding="utf-8"))
for item in manifest["files"]:
    rel=Path(item["path"])
    assert not rel.is_absolute() and ".." not in rel.parts
    content=(root/rel).read_bytes()
    assert len(content)==item["bytes"] and hashlib.sha256(content).hexdigest()==item["sha256"],str(rel)
print("Verified source preview:",len(manifest["files"])+1,"files")
