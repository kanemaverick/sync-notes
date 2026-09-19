"""Build SCF ZIP from an explicit allowlist; no local secrets or native binaries."""
import pathlib
import subprocess
import sys
import tempfile
import zipfile


def main():
    root = pathlib.Path(__file__).resolve().parents[1]
    source = root / "server/tencent_asr_proxy/scf_python"
    target = root / "build/tencent_asr_proxy_scf.zip"
    target.parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="sync-asr-package-") as staging:
        subprocess.run([
            sys.executable, "-m", "pip", "install", "--target", staging,
            "--platform", "any", "--implementation", "py", "--abi", "none",
            "--python-version", "39", "--only-binary=:all:", "--no-deps",
            "-r", str(source / "requirements.txt"),
        ], check=True)
        with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
            for name in ("app.py", "aliyun_asr.py", "scf_bootstrap"):
                info = zipfile.ZipInfo(name)
                info.external_attr = (0o100755 if name == "scf_bootstrap" else 0o100644) << 16
                archive.writestr(info, (source / name).read_bytes())
            for path in sorted(pathlib.Path(staging).rglob("*")):
                if not path.is_file() or "__pycache__" in path.parts:
                    continue
                if path.suffix in (".so", ".dylib", ".pyd"):
                    raise RuntimeError("Refusing platform-dependent dependency")
                archive.write(path, path.relative_to(staging))
    print(target)


if __name__ == "__main__":
    main()
