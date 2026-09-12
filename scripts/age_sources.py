"""Checksum-verified public sources shared by every age-proof build path."""
from hashlib import sha256
from pathlib import Path
import io
import json
import shutil
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
CONFIG = json.loads((ROOT / "config/age-proof-sources.json").read_text())
DEPENDENCIES = ("rsa", "bignum", "poseidon", "sha256", "sha512", "sha1")


def archive_bytes(name, cache):
    archive = cache / (name + ".tar.gz")
    cache.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        for cached in [ROOT / ".build/age-source-archives" / archive.name,
                       ROOT / ".build/age-proof-engine" / archive.name]:
            if cached.exists():
                shutil.copyfile(cached, archive)
                break
        else:
            archive.write_bytes(urllib.request.urlopen(CONFIG[name]["url"], timeout=60).read())
    data = archive.read_bytes()
    assert sha256(data).hexdigest() == CONFIG[name]["sha256"], "Unexpected public archive"
    return data


def extract_clean(data, destination):
    """Recreate generated sources, so prior edits/extra build files cannot survive."""
    assert not destination.is_symlink(), "Refusing a symlink source destination"
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="age-source-", dir=destination.parent) as folder:
        clean = Path(folder) / "source"
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
            members = tar.getmembers()
            prefix = members[0].name.split("/")[0] + "/"
            for member in members:
                if member.name.rstrip("/") == prefix.rstrip("/"):
                    continue
                assert member.name.startswith(prefix)
                member.name = member.name[len(prefix):]
                # Upstream source archives contain only regular files/directories.
                assert member.isfile() or member.isdir(), "Unexpected archive link"
                tar.extract(member, clean, filter="data")
        if destination.exists():
            shutil.rmtree(destination)
        clean.rename(destination)
    return destination


def materialize(name, cache, destination):
    return extract_clean(archive_bytes(name, cache), destination)


def vendor_circuit(destination, cache, beta19=False):
    assert destination.resolve().is_relative_to(ROOT / ".build"), "Generated circuit must stay in .build"
    if destination.exists():
        assert not destination.is_symlink()
        shutil.rmtree(destination)
    shutil.copytree(ROOT / "circuits/jpki_age/src", destination / "src")
    for name in DEPENDENCIES:
        materialize(name, cache, destination / "vendor" / name)
    manifest = (ROOT / "circuits/jpki_age/Nargo.toml").read_text()
    for old, new in [
        ('{ tag = "v0.11.0", git = "https://github.com/zkpassport/noir_rsa" }', '{ path = "vendor/rsa" }'),
        ('{ tag = "v0.10.0", git = "https://github.com/noir-lang/noir-bignum" }', '{ path = "vendor/bignum" }'),
        ('{ tag = "v0.3.0", git = "https://github.com/noir-lang/sha256" }', '{ path = "vendor/sha256" }'),
    ]:
        assert manifest.count(old) == 1
        manifest = manifest.replace(old, new)
    (destination / "Nargo.toml").write_text(manifest)
    replacements = [
        ("rsa/Nargo.toml", '{tag = "v0.10.0", git = "https://github.com/noir-lang/noir-bignum"}', '{ path = "../bignum" }'),
        ("rsa/Nargo.toml", '{ tag = "v0.3.0", git = "https://github.com/noir-lang/sha256" }', '{ path = "../sha256" }'),
        ("rsa/Nargo.toml", '{ tag = "v0.2.0", git = "https://github.com/zkpassport/sha512" }', '{ path = "../sha512" }'),
        ("rsa/Nargo.toml", '{ tag = "v0.11", git = "https://github.com/zac-williamson/sha1" }', '{ path = "../sha1" }'),
        ("bignum/Nargo.toml", '{ git = "https://github.com/noir-lang/poseidon", tag = "v0.3.0" }', '{ path = "../poseidon" }'),
    ]
    if beta19:
        replacements.append(("poseidon/src/lib.nr", 'pub use std::hash::poseidon2_permutation;',
            '// Noir beta.19 requires the state length argument.\npub fn poseidon2_permutation<let N: u32>(input: [Field; N]) -> [Field; N] { std::hash::poseidon2_permutation(input,N) }'))
    for name, old, new in replacements:
        file = destination / "vendor" / name
        text = file.read_text()
        assert text.count(old) == 1, "Unexpected public dependency API"
        file.write_text(text.replace(old, new))
    # Do not let a newly introduced transitive dependency silently bypass pins.
    import tomllib
    for file in destination.rglob("Nargo.toml"):
        document = tomllib.loads(file.read_text())
        for dependency in document.get("dependencies", {}).values():
            assert set(dependency) == {"path"}, "Unpinned Noir dependency"
    return destination
