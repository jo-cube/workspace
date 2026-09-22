"""Exercise the public recipes without starting containers or contacting a registry."""

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

FAKE_DOCKER = r'''#!/usr/bin/env python3
import json
import os
import sys

args = sys.argv[1:]
record = {"args": args, "env": {name: os.environ.get(name) for name in
          ("REGISTRY", "TAG", "FLAVOR", "BASE_IMAGE")}}
if args[:2] == ["compose", "exec"]:
    record["stdin"] = sys.stdin.read()
    sys.stdout.write(record["stdin"])
with open(os.environ["TEST_DOCKER_LOG"], "a") as log:
    log.write(json.dumps(record) + "\n")
if args[:2] == ["image", "inspect"]:
    sys.exit(int(os.environ.get("TEST_IMAGE_MISSING", "0")))
if args[:2] == ["buildx", "bake"]:
    sys.exit(int(os.environ.get("TEST_BUILD_EXIT", "0")))
if args[:2] == ["compose", "up"]:
    sys.exit(int(os.environ.get("TEST_UP_EXIT", "0")))
if args[:2] == ["compose", "exec"]:
    sys.exit(int(os.environ.get("TEST_EXEC_EXIT", "0")))
'''


class LauncherTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="workspace-launcher-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        docker = self.bin / "docker"
        docker.write_text(FAKE_DOCKER)
        docker.chmod(0o755)
        self.log = self.root / "docker.jsonl"
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(
            ("JUST_", "COMPOSE_", "TEST_")) and k not in
            ("REGISTRY", "TAG", "FLAVOR", "BASE_IMAGE", "WORKSPACE_PORT",
             "WORKSPACE_BIND_ADDRESS", "PASSWORD", "HASHED_PASSWORD",
             "JUPYTER_TOKEN", "WORKSPACE_CONFIG_FILE", "PUBLISH", "CACHE_FROM")}
        self.env["TEST_DOCKER_LOG"] = str(self.log)

    def project(self, enterprise=False, dotenv=""):
        path = self.root / ("enterprise" if enterprise else "generic")
        path.mkdir(exist_ok=True)
        source = ROOT / "templates/enterprise" if enterprise else ROOT
        for name in ("justfile", "compose.yaml", "docker-bake.hcl"):
            shutil.copy(source / name, path / name)
        if enterprise:
            (path / "config").mkdir(exist_ok=True)
            (path / "config/proxy.env").write_text("")
        (path / ".env").write_text(dotenv)
        self.log.write_text("")
        return path

    def run_just(self, project, *args, env=None, stdin="", real_docker=False):
        runtime_env = self.env | (env or {})
        if not real_docker:
            runtime_env["PATH"] = str(self.bin) + os.pathsep + self.env["PATH"]
        return subprocess.run(["just", "--justfile", str(project / "justfile"), *args],
                              input=stdin, text=True, capture_output=True, env=runtime_env, check=False)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def assert_success(self, result):
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_start_uses_dotenv_image_and_waits_without_rebuilding(self):
        for enterprise in (False, True):
            with self.subTest(enterprise=enterprise):
                project = self.project(enterprise, "REGISTRY=example.invalid/team\nTAG=1.2.3\nFLAVOR=full\n")
                self.assert_success(self.run_just(project, "start"))
                inspect, up = self.calls()
                expected = "example.invalid/team:1.2.3" if enterprise else "example.invalid/team/workspace:full-1.2.3"
                self.assertEqual(inspect["args"], ["image", "inspect", expected])
                self.assertEqual(up["args"], ["compose", "up", "--wait", "--wait-timeout", "120", "--no-build"])
                self.assertTrue((project / "workspace").is_dir())

    def test_missing_dotenv_uses_defaults_without_inheriting_another_project(self):
        (self.root / ".env").write_text("REGISTRY=example.invalid/other-project\nTAG=wrong\nFLAVOR=full\n")
        for enterprise in (False, True):
            with self.subTest(enterprise=enterprise):
                project = self.project(enterprise)
                (project / ".env").unlink()
                self.assert_success(self.run_just(project, "start"))
                expected = "registry.internal.example.com/workspace:latest" if enterprise else "ghcr.io/jo-cube/workspace:code-latest"
                self.assertEqual(self.calls()[0]["args"][-1], expected)

    def test_empty_selection_values_use_the_same_defaults_as_compose(self):
        for enterprise in (False, True):
            with self.subTest(enterprise=enterprise):
                project = self.project(enterprise, "REGISTRY=\nTAG=\nFLAVOR=\nBASE_IMAGE=\n")
                self.assert_success(self.run_just(project, "start"))
                expected = "registry.internal.example.com/workspace:latest" if enterprise else "ghcr.io/jo-cube/workspace:code-latest"
                self.assertEqual(self.calls()[0]["args"][-1], expected)
                compose = self.run_just(project, "--command", "docker", "compose", "config", "--images", real_docker=True)
                self.assert_success(compose)
                self.assertEqual(compose.stdout.strip(), expected)

    def test_environment_and_explicit_flavor_override_dotenv(self):
        project = self.project(dotenv="REGISTRY=example.invalid/file\nTAG=old\nFLAVOR=full\n")
        self.assert_success(self.run_just(project, "start", "platform", env={"TAG": "new"}))
        inspect, up = self.calls()
        self.assertEqual(inspect["args"][-1], "example.invalid/file/workspace:platform-new")
        self.assertEqual(up["env"]["FLAVOR"], "platform")
        self.assertEqual(up["env"]["TAG"], "new")

    def test_missing_image_is_built_with_the_selected_registry_and_tag(self):
        for enterprise in (False, True):
            with self.subTest(enterprise=enterprise):
                project = self.project(enterprise, "REGISTRY=example.invalid/team\nTAG=dev\nFLAVOR=platform\n")
                self.assert_success(self.run_just(project, "start", env={"TEST_IMAGE_MISSING": "1"}))
                _inspect, build, up = self.calls()
                self.assertEqual(build["args"], ["buildx", "bake", "enterprise" if enterprise else "platform"])
                self.assertEqual(build["env"]["REGISTRY"], "example.invalid/team")
                self.assertEqual(build["env"]["TAG"], "dev")
                self.assertEqual(up["args"][:2], ["compose", "up"])

    def test_failed_build_never_starts_or_creates_runtime_directories(self):
        for enterprise in (False, True):
            for recipe in ("start", "up"):
                with self.subTest(enterprise=enterprise, recipe=recipe):
                    project = self.project(enterprise)
                    result = self.run_just(project, recipe, env={"TEST_IMAGE_MISSING": "1", "TEST_BUILD_EXIT": "17"})
                    self.assertNotEqual(result.returncode, 0)
                    self.assertFalse(any(c["args"][:2] == ["compose", "up"] for c in self.calls()))
                    self.assertFalse((project / "workspace").exists())

    def test_up_rebuilds_even_when_an_image_exists(self):
        for enterprise in (False, True):
            with self.subTest(enterprise=enterprise):
                project = self.project(enterprise)
                self.assert_success(self.run_just(project, "up"))
                self.assertEqual([c["args"][:2] for c in self.calls()],
                                 [["buildx", "bake"], ["image", "inspect"], ["compose", "up"]])

    def test_invalid_flavors_never_reach_docker_or_the_shell(self):
        project = self.project()
        for recipe in ("start", "up", "build", "pull", "push"):
            for flavor in ("all", "code-core", "full; touch injected", "$(touch injected)"):
                with self.subTest(recipe=recipe, flavor=flavor):
                    result = self.run_just(project, recipe, flavor)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("Unsupported flavor:", result.stderr)
        self.assertEqual(self.calls(), [])
        self.assertFalse((project / "injected").exists())

    def test_pull_uses_selection_without_building_or_starting(self):
        for enterprise in (False, True):
            with self.subTest(enterprise=enterprise):
                project = self.project(enterprise, "REGISTRY=example.invalid/team\nTAG=1.2.3\n")
                args = ["pull"] if enterprise else ["pull", "full"]
                self.assert_success(self.run_just(project, *args))
                call, = self.calls()
                self.assertEqual(call["args"], ["compose", "pull", "workspace"])
                self.assertEqual(call["env"]["TAG"], "1.2.3")
                if not enterprise:
                    self.assertEqual(call["env"]["FLAVOR"], "full")

    def test_exec_preserves_arguments_stdin_and_exit_code(self):
        for enterprise in (False, True):
            with self.subTest(enterprise=enterprise):
                project = self.project(enterprise)
                args = ["printf", "%s\\n", "two words", "", "'quoted'", "$HOME", "*",
                        "$(touch injected)", "`touch injected`", "; touch injected"]
                result = self.run_just(project, "exec", *args, stdin="first\nsecond\n", env={"TEST_EXEC_EXIT": "23"})
                self.assertEqual(result.returncode, 23, result.stderr)
                self.assertEqual(result.stdout, "first\nsecond\n")
                call, = self.calls()
                self.assertEqual(call["args"], ["compose", "exec", "-T", "--user", "dev",
                    "--env", "HOME=/home/dev", "--env", "USER=dev", "--workdir", "/workspace", "workspace", *args])
                self.assertFalse((project / "injected").exists())

    def test_unhealthy_start_and_health_probe_fail(self):
        for enterprise in (False, True):
            with self.subTest(enterprise=enterprise):
                project = self.project(enterprise)
                result = self.run_just(project, "start", env={"TEST_UP_EXIT": "1"})
                self.assertNotEqual(result.returncode, 0)
                result = self.run_just(project, "health", env={"TEST_EXEC_EXIT": "1"})
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("workspace healthy", result.stdout)
                self.assertEqual(self.calls()[-1]["args"],
                                 ["compose", "exec", "-T", "workspace", "/scripts/healthcheck.sh"])

    def test_compose_and_bake_resolve_the_same_image(self):
        for enterprise in (False, True):
            with self.subTest(enterprise=enterprise):
                project = self.project(enterprise, "REGISTRY=example.invalid/team\nTAG=1.2.3\nFLAVOR=full\n")
                compose = self.run_just(project, "--command", "docker", "compose", "config", "--images", real_docker=True)
                bake = self.run_just(project, "--command", "docker", "buildx", "bake", "--print",
                                     "enterprise" if enterprise else "full", real_docker=True)
                self.assert_success(compose)
                self.assert_success(bake)
                target = json.loads(bake.stdout)["target"]["enterprise" if enterprise else "full"]
                self.assertEqual(target["tags"], [compose.stdout.strip()])


if __name__ == "__main__":
    unittest.main()
