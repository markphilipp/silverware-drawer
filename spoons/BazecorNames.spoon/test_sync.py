"""sync.py

Run from the repo root: python3 -m unittest discover -s spoons/BazecorNames.spoon -p "test_*.py"
"""

import json
import os
import pathlib
import subprocess
import sys
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).resolve().parent / "sync.py"


def config(layer="Main", macro="M Third", sk="Backspace"):
    return {
        "settings": {"keep": True},
        "neurons": [{
            "id": "n1",
            "layers": [{"id": 0, "name": layer}],
            "macros": [{"id": 0, "name": macro, "actions": [1]}],
            "superkeys": [{"id": 0, "name": sk, "actions": [2]}],
        }],
    }


class Machine:
    def __init__(self, root, shared, cfg):
        self.config = root / "config.json"
        self.state = root / "state"
        self.shared = shared
        self.config.write_text(json.dumps(cfg))
        self.last = None

    def run(self, running=False, check=True):
        env = {
            **os.environ,
            "BAZECOR_CONFIG": str(self.config),
            "BAZECOR_SYNC_FILE": str(self.shared),
            "BAZECOR_SYNC_STATE": str(self.state),
            "BAZECOR_RUNNING": "1" if running else "0",
        }
        proc = subprocess.run([sys.executable, "-I", str(SCRIPT)], env=env,
                              capture_output=True, text=True, check=check)
        self.last = proc
        return proc.stdout

    def load(self):
        return json.loads(self.config.read_text())

    def edit(self, **names):
        self.config.write_text(json.dumps(config(**names)))


class BazecorSync(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = pathlib.Path(tmp.name)
        self.shared = root / "icloud/names.json"
        self.shared.parent.mkdir()
        (root / "a").mkdir()
        (root / "b").mkdir()
        self.a = Machine(root / "a", self.shared, config(layer="Nav", macro="Mine"))
        self.b = Machine(root / "b", self.shared, config())

    def test_first_run_pushes_when_no_shared_file(self):
        self.a.run()
        self.assertEqual(json.loads(self.shared.read_text())["n1"]["layers"], {"0": "Nav"})

    def test_first_run_on_second_machine_pulls_shared_names_only(self):
        self.a.run()
        self.b.run()
        got = self.b.load()
        self.assertEqual(got["neurons"][0]["layers"][0]["name"], "Nav")
        self.assertEqual(got["neurons"][0]["macros"][0]["name"], "Mine")
        self.assertEqual(got["neurons"][0]["macros"][0]["actions"], [1])
        self.assertEqual(got["settings"], {"keep": True})

    def test_local_edit_is_pushed_then_pulled_by_peer(self):
        self.a.run()
        self.b.run()
        self.a.edit(layer="Renamed", macro="Mine")
        self.a.run()
        self.b.run()
        self.assertEqual(self.b.load()["neurons"][0]["layers"][0]["name"], "Renamed")

    def test_pull_is_deferred_while_bazecor_runs(self):
        self.a.run()
        before = self.b.config.read_text()
        out = self.b.run(running=True)
        self.assertIn("deferred", out)
        self.assertEqual(self.b.config.read_text(), before)

    def test_converged_run_is_a_noop(self):
        self.a.run()
        self.b.run()
        self.assertIn("in sync", self.b.run())

    def test_icloud_placeholder_is_never_overwritten(self):
        (self.shared.parent / ".names.json.icloud").write_text("")
        out = self.a.run()
        self.assertIn("not downloaded", out)
        self.assertFalse(self.shared.exists())


class Safety(unittest.TestCase):
    """Nothing here may ever leave config.json or names.json half-written."""

    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = pathlib.Path(tmp.name)
        self.shared = self.root / "icloud/names.json"
        self.shared.parent.mkdir()
        (self.root / "a").mkdir()
        (self.root / "b").mkdir()
        self.a = Machine(self.root / "a", self.shared, config(layer="Nav"))
        self.b = Machine(self.root / "b", self.shared, config())
        self.a.run()

    def snapshot(self, machine):
        state = machine.state.read_text() if machine.state.exists() else None
        return machine.config.read_bytes(), self.shared.read_bytes(), state

    def assert_untouched_and_failed(self, machine, **kw):
        before = self.snapshot(machine)
        machine.run(check=False, **kw)
        self.assertNotEqual(machine.last.returncode, 0, machine.last.stdout)
        self.assertIn("nothing written", machine.last.stderr)
        self.assertEqual(self.snapshot(machine), before)

    def test_corrupt_shared_file_aborts_without_writes(self):
        for bad in ('{"n1": {"layers": {"0": "Na', "not json", "[]", '{"n1": []}',
                    '{"n1": {"layers": {"0": 5}}}', '{"n1": {"layers": {"0": null}}}',
                    '{"n1": {"bogus": {"0": "x"}}}', '{"n1": {"layers": ["x"]}}', "null"):
            with self.subTest(bad=bad):
                self.shared.write_text(bad)
                self.b.state.unlink(missing_ok=True)
                self.assert_untouched_and_failed(self.b)
                self.assert_untouched_and_failed(self.a)

    def test_empty_shared_file_is_skipped_not_overwritten(self):
        self.shared.write_text("")
        before = self.snapshot(self.a)
        out = self.a.run()
        self.assertIn("empty", out)
        self.assertEqual(self.snapshot(self.a), before)

    def test_corrupt_local_config_aborts_without_writes(self):
        for bad in ("", "{", "[]", '{"neurons": [{"layers": []}]}', '{"neurons": 3}'):
            with self.subTest(bad=bad):
                self.b.config.write_text(bad)
                self.assert_untouched_and_failed(self.b)

    def test_shared_file_with_unknown_ids_is_harmless(self):
        self.shared.write_text(json.dumps(
            {"other": {"layers": {"0": "x"}}, "n1": {"layers": {"99": "ghost"}}}))
        before = self.b.config.read_text()
        self.b.run()
        self.assertEqual(self.b.config.read_text(), before)

    def test_icloud_placeholder_blocks_pull_and_push_with_shared_present(self):
        (self.shared.parent / ".names.json.icloud").write_text("")
        before = self.snapshot(self.b)
        self.assertIn("not downloaded", self.b.run())
        self.assertEqual(self.snapshot(self.b), before)

    def test_missing_shared_dir_is_created_when_icloud_exists(self):
        shared = self.root / "drive/Bazecor/names.json"
        (self.root / "drive").mkdir()
        Machine(self.root / "a", shared, config()).run()
        self.assertTrue(shared.exists())

    def test_missing_icloud_drive_creates_nothing(self):
        shared = self.root / "nodrive/Bazecor/names.json"
        out = Machine(self.root / "a", shared, config()).run()
        self.assertIn("iCloud", out)
        self.assertFalse((self.root / "nodrive").exists())

    def test_pull_does_not_change_anything_but_names(self):
        self.b.config.write_text(json.dumps(config(), indent="\t", ensure_ascii=False) + "\n")
        self.b.config.chmod(0o666)
        self.b.run()
        got, want = self.b.load(), config(layer="Nav")
        self.assertEqual(got, want)
        self.assertEqual(self.b.config.stat().st_mode & 0o777, 0o666)
        self.assertEqual(self.b.config.read_text(),
                         json.dumps(want, indent="\t", ensure_ascii=False) + "\n")

    def test_unicode_names_survive_in_both_files(self):
        self.a.edit(layer="Nav \u2318 \U0001f3b9")
        self.a.run()
        self.b.run()
        self.assertEqual(self.b.load()["neurons"][0]["layers"][0]["name"], "Nav \u2318 \U0001f3b9")
        self.assertIn("\u2318", self.shared.read_text(encoding="utf-8"))
        self.assertIn("\u2318", self.b.config.read_text(encoding="utf-8"))

    def test_push_leaves_local_config_untouched(self):
        self.a.edit(layer="Renamed")
        before = self.a.config.read_bytes()
        self.assertIn("pushed", self.a.run())
        self.assertEqual(self.a.config.read_bytes(), before)

    def test_in_sync_run_rewrites_neither_file(self):
        self.b.run()
        stamps = [(p.stat().st_mtime_ns, p.stat().st_ino) for p in (self.b.config, self.shared)]
        for _ in range(2):
            self.assertIn("in sync", self.b.run())
            self.assertEqual(
                [(p.stat().st_mtime_ns, p.stat().st_ino) for p in (self.b.config, self.shared)],
                stamps)

    def test_no_stray_temp_files_after_runs(self):
        self.b.run()
        self.a.edit(layer="Again")
        self.a.run()
        self.b.run()
        left = [p.name for d in (self.shared.parent, self.b.config.parent) for p in d.iterdir()
                if p.name.startswith(".") and p.name != ".names.json.icloud"]
        self.assertEqual(left, [])


class Deferral(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = pathlib.Path(tmp.name)
        self.shared = root / "icloud/names.json"
        self.shared.parent.mkdir()
        (root / "a").mkdir()
        (root / "b").mkdir()
        self.a = Machine(root / "a", self.shared, config(layer="Nav"))
        self.b = Machine(root / "b", self.shared, config())

    def test_first_run_pull_deferred_then_applied_after_quit(self):
        self.a.run()
        self.assertIn("deferred", self.b.run(running=True))
        self.assertFalse(self.b.state.exists())
        self.assertIn("pulled", self.b.run())
        self.assertEqual(self.b.load()["neurons"][0]["layers"][0]["name"], "Nav")

    def test_later_pull_deferred_repeatedly_then_applied(self):
        self.a.run()
        self.b.run()
        state = self.b.state.read_text()
        self.a.edit(layer="Renamed")
        self.a.run()
        for _ in range(3):
            self.assertIn("deferred", self.b.run(running=True))
            self.assertEqual(self.b.state.read_text(), state)
        self.assertIn("pulled", self.b.run())
        self.assertEqual(self.b.load()["neurons"][0]["layers"][0]["name"], "Renamed")
        self.assertIn("in sync", self.b.run())

    def test_local_edit_while_pull_deferred_wins_and_is_pushed(self):
        self.a.run()
        self.b.run()
        self.a.edit(layer="FromA")
        self.a.run()
        self.assertIn("deferred", self.b.run(running=True))
        self.b.edit(layer="FromB")
        self.assertIn("pushed", self.b.run(running=True))
        self.assertEqual(json.loads(self.shared.read_text())["n1"]["layers"], {"0": "FromB"})
        self.assertIn("pulled", self.a.run())
        self.assertEqual(self.a.load()["neurons"][0]["layers"][0]["name"], "FromB")

    def test_push_is_allowed_while_bazecor_runs(self):
        self.a.run()
        self.b.run()
        self.b.edit(layer="Live")
        self.assertIn("pushed", self.b.run(running=True))


class Internals(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import importlib.util
        spec = importlib.util.spec_from_file_location("bazecor_sync", SCRIPT)
        cls.sync = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cls.sync)

    def test_failed_replace_keeps_target_and_cleans_temp(self):
        with tempfile.TemporaryDirectory() as d:
            target = pathlib.Path(d) / "f.json"
            target.write_text("old")
            real = os.replace
            os.replace = lambda *a: (_ for _ in ()).throw(OSError("boom"))
            try:
                with self.assertRaises(OSError):
                    self.sync.write_atomic(target, "new")
            finally:
                os.replace = real
            self.assertEqual(target.read_text(), "old")
            self.assertEqual([p.name for p in pathlib.Path(d).iterdir()], ["f.json"])

    def test_pgrep_error_counts_as_running(self):
        from unittest import mock
        saved = os.environ.pop("BAZECOR_RUNNING", None)
        try:
            for code, running in ((0, True), (1, False), (2, True), (-9, True)):
                with mock.patch.object(self.sync.subprocess, "run",
                                       return_value=mock.Mock(returncode=code)):
                    self.assertEqual(self.sync.bazecor_running(), running, code)
        finally:
            if saved is not None:
                os.environ["BAZECOR_RUNNING"] = saved


if __name__ == "__main__":
    unittest.main()
