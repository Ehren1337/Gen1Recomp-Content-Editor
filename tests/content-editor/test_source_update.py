"""Exercise the real source installer against disposable portable installations.

Run: python tests/content-editor/test_source_update.py
"""
import os
from pathlib import Path
import subprocess
import shutil
import uuid
import tarfile
import zipfile
import stat
import unittest

ROOT = Path(__file__).resolve().parents[2]
LUA = os.environ.get("LUA_TEST") or (str(ROOT / "tools/tooling/luajit/luajit.exe") if os.name == "nt" else "luajit")


class SourceInstallTests(unittest.TestCase):
    def setUp(self):
        self.base = ROOT / "tests/content-editor" / ("editor update ' test " + uuid.uuid4().hex)
        self.base.mkdir()
        assert self.base.resolve().parent == (ROOT / "tests/content-editor").resolve()
        self.addCleanup(shutil.rmtree, self.base)
        self.install = self.base / "installed"
        self.stage = self.base / "stage"
        self.install.mkdir()
        self.stage.mkdir()
        self.script = self.base / ("install.ps1" if os.name == "nt" else "install.sh")
        env = dict(os.environ, TEST_ROOT=str(self.install), TEST_STAGE=str(self.stage), TEST_SCRIPT=str(self.script))
        program = r'''
package.path = "tools/content-editor/?.lua;" .. package.path
local S = require("SourceUpdate")
for _, unit in ipairs(S.installUnits()) do print(unit) end
local f = assert(io.open(os.getenv("TEST_SCRIPT"), "wb"))
f:write(S.installScript(os.getenv("TEST_ROOT"), os.getenv("TEST_STAGE"), 2147483647,
  package.config:sub(1,1) == "\\", "ContentEditor.sh", false))
f:close()
'''
        result = subprocess.run([LUA, "-e", program], cwd=ROOT, env=env, text=True, capture_output=True, check=True)
        self.units = result.stdout.splitlines()
        self.dirs = {"tools/content-editor", "tools/save-editor", "tools/tooling", "libs",
                     "tests/fixture_data", "assets/launcher", "assets/logo", "assets/switch", "assets/touch"}
        for unit in self.units:
            for root, content in [(self.install, "old"), (self.stage, "new")]:
                path = root / unit
                if unit in self.dirs:
                    path = path / ("obsolete.lua" if content == "old" else "current.lua")
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
        self.protected = ["mods/my_project/main.lua", "mods/my_project/assets/sprite.png",
                          "my_project.editor_project.lua", "data/generated/cache.bin",
                          "assets/generated/cache.bin", "love/saves/save.dat", "love/settings.json",
                          "love/love.exe", "runtime/gen1recomp/mods/local/main.lua"]
        for name in self.protected:
            path = self.install / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"user data\x00\xff")
        # Even an unwanted mods folder in the stage must not be installed.
        (self.stage / "mods/my_project").mkdir(parents=True)
        (self.stage / "mods/my_project/main.lua").write_text("overwrite attempt")

    def run_installer(self):
        command = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File"] if os.name == "nt" else ["sh"]
        return subprocess.run(command + [str(self.script)], text=True, capture_output=True)

    def assert_protected(self):
        for name in self.protected:
            self.assertEqual((self.install / name).read_bytes(), b"user data\x00\xff", name)

    def test_install_preserves_mods_and_removes_obsolete_modules(self):
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_protected()
        self.assertFalse((self.install / "tools/content-editor/obsolete.lua").exists())
        self.assertEqual((self.install / "tools/content-editor/current.lua").read_text(), "new")
        self.assertEqual((self.install / "content-editor-commit.txt").read_text(), "new")

    def test_failed_install_restores_previous_files(self):
        (self.stage / "content-editor-commit.txt").unlink()
        result = self.run_installer()
        self.assertNotEqual(result.returncode, 0)
        self.assert_protected()
        self.assertEqual((self.install / "tools/content-editor/obsolete.lua").read_text(), "old")
        self.assertFalse((self.install / "tools/content-editor/current.lua").exists())
        self.assertEqual((self.install / "main.lua").read_text(), "old")

    def test_checkout_is_never_modified(self):
        (self.install / ".git").write_text("gitdir: example")
        self.assertNotEqual(self.run_installer().returncode, 0)
        self.assertEqual((self.install / "main.lua").read_text(), "old")
        self.assert_protected()

    def test_source_staging_builds_runtime_without_mods(self):
        runtime = self.base / "runtime-fixture"
        for name in ["main.lua", "conf.lua", "src/core/Input.lua", "data/example.lua", "assets/example.txt", "mods/do-not-ship/main.lua"]:
            path = runtime / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("runtime fixture")
        archive = self.base / "runtime.tar.gz"
        with tarfile.open(archive, "w:gz") as tar:
            tar.add(runtime, arcname="upstream-sha")
        for name in ["main.lua", "conf.lua"]:
            path = self.stage / "tools/content-editor/runtime" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("editor bootstrap")
        package = self.base / "package"
        env = dict(os.environ, TEST_SOURCE=str(self.stage), TEST_PACKAGE=str(package),
                   TEST_ARCHIVE=str(archive), TEST_SCRIPT=str(self.script))
        program = r'''
package.path = "tools/content-editor/?.lua;" .. package.path
local S = require("SourceUpdate")
local f = assert(io.open(os.getenv("TEST_SCRIPT"), "wb"))
f:write(S.stageScript(os.getenv("TEST_SOURCE"), os.getenv("TEST_PACKAGE"),
  os.getenv("TEST_ARCHIVE"), package.config:sub(1,1) == "\\"))
f:close()
'''
        subprocess.run([LUA, "-e", program], cwd=ROOT, env=env, check=True)
        result = self.run_installer()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((package / "main.lua").read_text(), "editor bootstrap")
        self.assertFalse((package / "mods").exists())
        with zipfile.ZipFile(package / "runtime/gen1recomp.love") as z:
            names = [name.replace("\\", "/") for name in z.namelist()]
            self.assertIn("src/core/Input.lua", names)
            self.assertFalse(any(name.startswith("mods/") for name in names))

    def test_background_checks_stage_new_commits_and_retry_failures(self):
        program = r'''
package.path = "tools/content-editor/?.lua;" .. package.path
local U = require("Updater")
local dir = os.getenv("TEST_WORK")
U.workDir = function() return dir end
U.root = function() return os.getenv("TEST_ROOT") end
U.launch = function() return true end -- Simulate completed network jobs below.
local sha = string.rep("a", 40)
U.currentVersion = function() return string.rep("b", 40) end
local function write(path, body)
  local f = assert(io.open(path, "wb")); f:write(body); f:close()
end
local function answer(body, code)
  write(U.state.file, body)
  write(U.state.job.done, code or "0")
  U.poll()
end
U.check(true)
answer('{"sha":"' .. sha .. '","commit":{"message":"Update"}}')
assert(U.state.step == "downloading", "new commits download automatically")
U.state = {step="idle"}
U.currentVersion = function() return sha end
U.check(true)
answer('{"sha":"' .. sha .. '"}')
assert(U.state.step == "latest", "same commit must not download again")
U.nextCheck = 0; U.poll()
assert(U.state.step == "checking", "periodic automatic check")
answer('', "1")
assert(U.state.step == "error")
U.nextCheck = 0; U.poll()
assert(U.state.step == "checking", "offline failures retry")
answer('{"message":"API rate limit exceeded"}')
assert(U.state.step == "error" and U.state.error:find("rate limit"))
U.state = {step="staged"}; U.nextCheck = 0; U.poll()
assert(U.state.step == "staged", "do not discard staged updates")
'''
        env = dict(os.environ, TEST_WORK=str(self.base), TEST_ROOT=str(self.install))
        env.pop("POKEPORT_NO_UPDATE_CHECK", None)
        subprocess.run([LUA, "-e", program], cwd=ROOT, env=env, check=True)


class CheckoutUpdateTests(unittest.TestCase):
    def setUp(self):
        self.base = ROOT / "tests/content-editor" / ("git update test " + uuid.uuid4().hex)
        self.repo = self.base / "checkout"
        self.repo.mkdir(parents=True)
        assert self.base.resolve().parent == (ROOT / "tests/content-editor").resolve()
        self.addCleanup(self.cleanup)
        self.git("init", "-b", "main")
        self.git("config", "user.email", "test@example.invalid")
        self.git("config", "user.name", "Updater test")
        (self.repo / "main.lua").write_text("old editor")
        (self.repo / "mods/project").mkdir(parents=True)
        (self.repo / "mods/project/main.lua").write_text("original mod")
        self.git("add", ".")
        self.git("commit", "-m", "initial")
        self.old = self.git("rev-parse", "HEAD")
        self.git("checkout", "-b", "incoming")
        (self.repo / "main.lua").write_text("new editor")
        self.git("commit", "-am", "editor update")
        self.target = self.git("rev-parse", "HEAD")
        self.git("checkout", "main")
        (self.repo / "mods/project/main.lua").write_bytes(b"unfinished mod\x00\xff")

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.repo), *args], check=True,
                              capture_output=True, text=True).stdout.strip()

    def cleanup(self):
        def retry(function, path, exc):
            os.chmod(path, stat.S_IWRITE)
            function(path)
        shutil.rmtree(self.base, onerror=retry)

    def update(self):
        script = self.base / ("update.ps1" if os.name == "nt" else "update.sh")
        env = dict(os.environ, TEST_ROOT=str(self.repo), TEST_SHA=self.target, TEST_SCRIPT=str(script))
        program = r'''
package.path = "tools/content-editor/?.lua;" .. package.path
local U = require("Updater")
assert(U.currentVersion(os.getenv("TEST_ROOT")), "checkout commit must be detected")
local f = assert(io.open(os.getenv("TEST_SCRIPT"), "wb"))
f:write(require("GitUpdate").script(os.getenv("TEST_ROOT"), os.getenv("TEST_SHA"),
  package.config:sub(1,1) == "\\", 2147483647))
f:close()
'''
        subprocess.run([LUA, "-e", program], cwd=ROOT, env=env, check=True)
        command = ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File"] if os.name == "nt" else ["sh"]
        return subprocess.run(command + [str(script)], capture_output=True, text=True)

    def assert_mod_preserved(self):
        self.assertEqual((self.repo / "mods/project/main.lua").read_bytes(), b"unfinished mod\x00\xff")

    def test_fast_forward_preserves_unfinished_mod(self):
        result = self.update()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.target)
        self.assert_mod_preserved()

    def test_local_editor_changes_pause_update(self):
        (self.repo / "main.lua").write_text("local changes")
        self.assertNotEqual(self.update().returncode, 0)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.old)
        self.assertEqual((self.repo / "main.lua").read_text(), "local changes")
        self.assert_mod_preserved()

    def test_divergent_commits_pause_update(self):
        (self.repo / "local.lua").write_text("local feature")
        self.git("add", "local.lua")
        self.git("commit", "-m", "local feature")
        local_head = self.git("rev-parse", "HEAD")
        self.assertNotEqual(self.update().returncode, 0)
        self.assertEqual(self.git("rev-parse", "HEAD"), local_head)
        self.assert_mod_preserved()

    def test_incoming_mod_changes_are_rejected(self):
        # Commit a separate incoming mod without changing the user's dirty file.
        self.git("checkout", "incoming")
        (self.repo / "mods/another.lua").write_text("incoming mod")
        self.git("add", "mods/another.lua")
        self.git("commit", "-m", "upstream mod change")
        self.target = self.git("rev-parse", "HEAD")
        self.git("checkout", "main")
        self.assertNotEqual(self.update().returncode, 0)
        self.assertEqual(self.git("rev-parse", "HEAD"), self.old)
        self.assertFalse((self.repo / "mods/another.lua").exists())
        self.assert_mod_preserved()


if __name__ == "__main__":
    unittest.main()
