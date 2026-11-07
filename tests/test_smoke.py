"""Check smoke build selection without building or starting containers."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

FAKE_DOCKER = """#!/usr/bin/env python3
import json
import os
import sys

args = sys.argv[1:]
with open(os.environ["TEST_DOCKER_LOG"], "a") as log:
    log.write(json.dumps(args) + "\\n")
if args[:2] in (["buildx", "bake"], ["image", "inspect"]):
    sys.exit(17)
"""


class SmokeBuildSelectionTests(unittest.TestCase):
    def test_build_failure_and_missing_prebuilt_image_stop_before_runtime(self):
        with tempfile.TemporaryDirectory(prefix="workspace-smoke-selection-") as directory:
            root = Path(directory)
            docker = root / "docker"
            docker.write_text(FAKE_DOCKER)
            docker.chmod(0o755)
            log = root / "docker.jsonl"
            env = os.environ | {"PATH": str(root) + os.pathsep + os.environ["PATH"],
                                "TEST_DOCKER_LOG": str(log)}
            for args, first_command in ((["code"], ["buildx", "bake"]),
                                        (["--no-build", "code"], ["image", "inspect"])):
                with self.subTest(args=args):
                    log.write_text("")
                    result = subprocess.run(["bash", str(ROOT / "scripts/smoke-test.sh"), *args],
                                            env=env, text=True, capture_output=True)
                    calls = [json.loads(line) for line in log.read_text().splitlines()]
                    self.assertEqual(result.returncode, 17, result.stderr)
                    self.assertEqual(calls[0][:2], first_command)
                    self.assertFalse(any(call[0] in ("run", "pull") for call in calls))
                    if "--no-build" in args:
                        self.assertFalse(any(call[:2] == ["buildx", "bake"] for call in calls))


if __name__ == "__main__":
    unittest.main()
