#!/usr/bin/env python3
"""Generate a Cask only from an existing stable-version release archive."""
import argparse
import hashlib
from pathlib import Path
import re
import zipfile

parser = argparse.ArgumentParser()
parser.add_argument("--version", required=True)
parser.add_argument("--tag", required=True)
parser.add_argument("--archive", type=Path, required=True)
parser.add_argument("--tap", type=Path, required=True)
args = parser.parse_args()
if not re.fullmatch(r"\d+\.\d+\.\d+", args.version) or args.tag != f"v{args.version}":
    parser.error("Only vMAJOR.MINOR.PATCH stable releases can update the production Cask")
with zipfile.ZipFile(args.archive) as archive:
    names = set(archive.namelist())
    for required in ("GimmeRemote.app/Contents/MacOS/GimmeRemote",
                     "GimmeRemote.app/Contents/MacOS/gimme",
                     "GimmeRemote.app/Contents/Resources/Web/index.html"):
        if required not in names:
            parser.error(f"Release archive is missing {required}")

destination = args.tap / "Casks" / "gimme-remote.rb"
if destination.exists():
    previous = re.search(r'version "(\d+\.\d+\.\d+)"', destination.read_text())
    if previous and tuple(map(int, previous[1].split("."))) > tuple(map(int, args.version.split("."))):
        parser.error("Refusing to downgrade the existing Cask")
with args.archive.open("rb") as source:
    checksum = hashlib.file_digest(source, "sha256").hexdigest()
destination.parent.mkdir(parents=True, exist_ok=True)
destination.write_text(f'''cask "gimme-remote" do
  version "{args.version}"
  sha256 "{checksum}"

  url "https://github.com/lucientong/gimme-remote/releases/download/v#{{version}}/GimmeRemote-#{{version}}-universal.zip"
  name "Gimme Remote"
  desc "Control your Mac from your phone on the local network"
  homepage "https://github.com/lucientong/gimme-remote"

  depends_on macos: ">= :sonoma"

  app "GimmeRemote.app"
  binary "#{{appdir}}/GimmeRemote.app/Contents/MacOS/gimme"

  zap trash: [
    "~/Library/Application Support/GimmeRemote",
    "~/Library/Preferences/com.lucientong.GimmeRemote.plist",
  ]
end
''')
print(destination)
