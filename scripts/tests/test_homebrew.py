import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / "update-homebrew.py"


class HomebrewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.archive = self.root / "release.zip"
        with zipfile.ZipFile(self.archive, "w") as archive:
            for name in ("Contents/MacOS/GimmeRemote", "Contents/MacOS/gimme",
                         "Contents/Resources/Web/index.html"):
                archive.writestr(f"GimmeRemote.app/{name}", "test fixture")
        self.tap = self.root / "tap"

    def generate(self, version="1.2.3", tag="v1.2.3"):
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--version", version, "--tag", tag,
             "--archive", str(self.archive), "--tap", str(self.tap)],
            capture_output=True, text=True,
        )

    def test_uses_final_archive_checksum_and_installs_app_and_cli(self):
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stderr)
        cask = (self.tap / "Casks/gimme-remote.rb").read_text()
        self.assertIn(hashlib.sha256(self.archive.read_bytes()).hexdigest(), cask)
        self.assertIn('version "1.2.3"', cask)
        self.assertIn('app "GimmeRemote.app"', cask)
        self.assertIn('Contents/MacOS/gimme', cask)
        self.assertIn('ad-hoc signing', cask)
        self.assertIn('Open Anyway', cask)
        self.assertIn('updates may require granting it again', cask)

    def test_prerelease_and_mismatched_tag_are_rejected(self):
        self.assertNotEqual(self.generate("1.2.3", "v1.2.3-beta.1").returncode, 0)
        self.assertNotEqual(self.generate("1.2.3", "v1.2.4").returncode, 0)

    def test_existing_newer_cask_cannot_be_downgraded(self):
        self.assertEqual(self.generate("2.0.0", "v2.0.0").returncode, 0)
        self.assertNotEqual(self.generate().returncode, 0)
        self.assertIn('version "2.0.0"', (self.tap / "Casks/gimme-remote.rb").read_text())


if __name__ == "__main__":
    unittest.main()
