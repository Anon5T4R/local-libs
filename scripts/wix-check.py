r"""Compila o .wxs de um app numa ref do git com binários falsos: valida o instalador MSI (sintaxe,
Ids, componentes, extensões do WiX) sem o build de release, em segundos.

uso: python -I wix-check.py <repo-do-app> <ref> <wxs-relativo> <package.ps1-relativo>
     WIX_SCOPE=perUser python -I wix-check.py ...   # MSIs com $(var.Scope) (office, sheets, slides)
ex.: python -I wix-check.py C:/Dev/underworld-apps/local-pdf HEAD packaging/windows/localpdf.wxs packaging/windows/package.ps1

Precisa do WiX v5 do package.ps1 (`dotnet tool install --global wix`, mais as extensões que ele lista).
Não substitui o teste do MSI real: só pega o que quebraria o `wix build` do release.
"""
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib

repo, ref, wxs_rel, ps1_rel = sys.argv[1:5]


def show(path):
    return subprocess.run(["git", "-C", repo, "show", f"{ref}:{path}"], capture_output=True, check=True).stdout


wxs = show(wxs_rel).decode("utf-8")
ps1 = show(ps1_rel).decode("utf-8", "replace")
work = tempfile.mkdtemp(prefix="wixcheck-")
bindir = os.path.join(work, "bin")
os.makedirs(bindir)
wxs_dir = os.path.join(work, os.path.dirname(wxs_rel))
os.makedirs(wxs_dir, exist_ok=True)
wxs_path = os.path.join(work, wxs_rel)
open(wxs_path, "w", encoding="utf-8").write(wxs)
# Other .wxs the package.ps1 passes to `wix build` with it (pdf: installer-ui.wxs), from the same ref.
extra_wxs = []
for name in sorted(set(re.findall(r"'([\w.-]+\.wxs)'", ps1)) - {os.path.basename(wxs_rel)}):
    rel = os.path.join(os.path.dirname(wxs_rel), name).replace("\\", "/")
    try:
        text = show(rel).decode("utf-8")
    except subprocess.CalledProcessError:
        continue
    path = os.path.join(work, rel)
    open(path, "w", encoding="utf-8").write(text)
    extra_wxs.append(path)
    wxs += text  # its $(var.*) need defines too
# Arquivos incluídos pelo wxs (wxi, licença rtf…) ao lado dele, da mesma ref.
for inc in re.findall(r'<\?include\s+([^?]+?)\s*\?>', wxs):
    p = os.path.join(os.path.dirname(wxs_rel), inc).replace("\\", "/")
    try:
        open(os.path.join(work, p), "wb").write(show(p))
    except subprocess.CalledProcessError:
        pass


def bmp(path):
    # BMP 1x1 válido (a extensão de UI do WiX lê o arquivo).
    data = b"BM" + struct.pack("<IHHI", 58, 0, 0, 54) + struct.pack("<IiiHHIIiiII", 40, 1, 1, 1, 24, 0, 4, 0, 0, 0, 0) + b"\0\0\0\0"
    open(path, "wb").write(data)


def ico(path):
    png = b"\x89PNG\r\n\x1a\n"
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(b"\0\0\0\0\0"))
    png += chunk(b"IEND", b"")
    head = struct.pack("<HHH", 0, 1, 1) + struct.pack("<BBBBHHII", 1, 1, 0, 0, 1, 32, len(png), 22)
    open(path, "wb").write(head + png)


def dummy(path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    low = path.lower()
    if low.endswith(".bmp"):
        bmp(path)
    elif low.endswith(".ico"):
        ico(path)
    elif low.endswith(".rtf"):
        open(path, "w").write(r"{\rtf1\ansi x}")
    else:
        open(path, "wb").write(b"MZ")


defines = {}
for name in set(re.findall(r"\$\(var\.(\w+)\)", wxs)):
    if name == "Scope":
        defines[name] = os.environ.get("WIX_SCOPE", "perMachine")
        continue
    if name.lower() in ("version", "productversion", "msiversion"):
        defines[name] = "1.0.0"
        continue
    if re.search(r"\$\(var\." + name + r"\)[\\/]", wxs):
        d = os.path.join(work, "dir-" + name)
        os.makedirs(d, exist_ok=True)
        defines[name] = d
        for rel in re.findall(r"\$\(var\." + name + r"\)[\\/]([^\"<>]+)", wxs):
            if "*" in rel:
                # <Files Include="$(var.X)\**">: one file under the folder is enough.
                base = rel.split("*")[0].rstrip("\\/")
                dummy(os.path.join(d, base.replace("\\", os.sep), "placeholder.txt"))
            else:
                dummy(os.path.join(d, rel.replace("\\", os.sep)))
    else:
        ext = ".bmp" if "bmp" in name.lower() else ".ico" if "icon" in name.lower() else ".rtf" if "licen" in name.lower() else ".bin"
        f = os.path.join(work, name + ext)
        dummy(f)
        defines[name] = f

exts = re.findall(r"WixToolset\.\w+\.wixext", ps1)
ver = (re.findall(r"\$WixVersion\s*=\s*'([^']+)'", ps1) or ["5.0.2"])[0]
cmd = ["wix", "build", wxs_path, *extra_wxs, "-arch", "x64", "-culture", "en-us", "-o", os.path.join(work, "out.msi")]
for e in sorted(set(exts)):
    cmd += ["-ext", f"{e}/{ver}"]
for k, v in defines.items():
    cmd += ["-d", f"{k}={v}"]
r = subprocess.run(cmd, capture_output=True, text=True, cwd=wxs_dir)
out = (r.stdout + r.stderr).strip()
print(f"{os.path.basename(repo)}: {'OK' if r.returncode == 0 else 'FALHOU'}")
if r.returncode != 0 or "warning" in out.lower():
    print("\n".join(l for l in out.splitlines() if "error" in l.lower() or "warning" in l.lower())[:3000])
shutil.rmtree(work, ignore_errors=True)
sys.exit(r.returncode)
