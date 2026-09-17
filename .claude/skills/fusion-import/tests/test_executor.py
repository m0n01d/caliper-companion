"""Executor against fake_adsk: golden call log, inspect is read-only, re-import semantics, ownership
collisions, rollback, timeline group placement, component targeting, no-adsk behaviour."""

import json
import sys
import tempfile
import unittest
from pathlib import Path

import helpers
import fake_adsk
import import_ccpart as ic

SLUG = "norcold_freezer_hinge_pin"


class Base(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.TemporaryDirectory()
        self.root = Path(self.td.name)
        self.zip = helpers.build_zip(self.root)
        self.plan, self.dir = ic.extract_bundle(self.zip, self.root / "imports")
        ic.__dict__.pop("__ccpart", None)

    def tearDown(self):
        fake_adsk.uninstall()
        self.td.cleanup()

    def install(self, design=None, **kw):
        self.rec = fake_adsk.Recorder()
        if design is None:
            design = fake_adsk.make_design(self.rec, **kw)
        self.design = design
        fake_adsk.install(self.rec, design=design)
        return design

    def run_import(self, mode="execute", **kw):
        args = ic.default_args(mode, self.dir, **kw)
        report = ic.run_import(args)
        # the report file is the channel the skill reads
        on_disk = json.loads((self.dir / ic.REPORT_FILE).read_text(encoding="utf-8"))
        self.assertEqual(on_disk["status"], report["status"])
        return report

    def prepopulate(self, design, transform=(2, 0, 0, 2, 5, 5), pixels=None, ours=True):
        """A design that already holds a previous import of the golden (an old timeline group included)."""
        tag = {"ccpart": SLUG} if ours else {"ccpart": "someone_else"}
        for p in self.plan["parameters"]:
            comment = "OLD ±0.2 mm · faces x · ccpart:" + SLUG if ours else "somebody's parameter"
            design.userParameters._preset(p["name"], "1 mm", "mm", comment)
        comp = design.activeComponent
        for s in self.plan["sketches"]:
            px = pixels or "{}x{}".format(s["png_width"], s["png_height"])
            comp.sketches._preset(s["name"], getattr(comp, s["plane"]), attrs=dict(tag, face=s["name"]))
            comp.canvases._preset(s["canvas_name"], getattr(comp, s["plane"]), transform=list(transform), attrs=dict(tag, face=s["name"], pixels=px))
        g = design.timeline.timelineGroups.add(0, design.timeline.count - 1)
        g._set("name", SLUG + " import")
        self.rec.calls.clear()
        self.rec.writes.clear()
        return design


class FreshDesign(Base):
    def test_golden_call_log(self):
        self.install()
        report = self.run_import("execute")
        self.assertTrue(report["ok"], report)
        self.assertEqual(report["status"], "executed")
        rows = [json.dumps(c, ensure_ascii=False).replace(str(self.dir), "<dir>") for c in self.rec.calls]
        text = "[\n" + ",\n".join(rows) + "\n]\n"
        expected, path = helpers.snapshot("hinge_pin.calls.json", text)
        self.assertEqual(text, expected, "call log drifted from {} (UPDATE_GOLDEN=1 to accept)".format(path))

    def test_result_lists(self):
        self.install()
        r = self.run_import("execute")["result"]
        self.assertEqual(r["created"][:9], ["parameter " + p["name"] for p in self.plan["parameters"]])
        self.assertEqual(r["created"][9:], ["sketch top", "canvas top_photo", "sketch side", "canvas side_photo", "sketch end", "canvas end_photo"])
        self.assertEqual(r["updated"], [])
        self.assertEqual(r["kept"], [])
        self.assertEqual(r["refreshed"], [])
        self.assertEqual(r["skipped"], [])
        self.assertEqual(r["group"], SLUG + " import")
        self.assertIn("100 mm", r["canvas_note"])
        self.assertIn("target component is the root component", r["warnings"])
        self.assertTrue(r["component_is_root"])

    def test_entities_land_where_the_plan_says(self):
        d = self.install()
        self.run_import("execute")
        comp = d.activeComponent
        self.assertEqual([p.name for p in d.userParameters._items], [p["name"] for p in self.plan["parameters"]])
        self.assertEqual(d.userParameters.itemByName_silent("overall_l").expression, "42.18 mm")
        self.assertEqual(d.userParameters.itemByName_silent("overall_l").unit, "mm")
        self.assertEqual([(s.name, s.referencePlane.name) for s in comp.sketches._items], [("top", "xYConstructionPlane"), ("side", "xZConstructionPlane"), ("end", "yZConstructionPlane")])
        self.assertEqual([(c.name, c.planarEntity.name, c.opacity) for c in comp.canvases._items], [("top_photo", "xYConstructionPlane", 60), ("side_photo", "xZConstructionPlane", 60), ("end_photo", "yZConstructionPlane", 60)])
        self.assertTrue(comp.canvases._items[0].imageFilename.endswith("faces/top_dimensioned.png"))
        top = comp.sketches._items[0]
        self.assertEqual(top.attributes._store[("caliper-companion", "ccpart")].value, SLUG)
        self.assertEqual(top.attributes._store[("caliper-companion", "face")].value, "top")
        self.assertEqual(comp.canvases._items[2].attributes._store[("caliper-companion", "pixels")].value, "1200x1600")
        g = d.timeline.timelineGroups.item(0)
        self.assertEqual((g.startIndex, g.endIndex, g.name), (0, 5, SLUG + " import"))
        self.assertFalse(d.isComputeDeferred)

    def test_no_create_by_real_and_no_message_box(self):
        self.install()
        self.run_import("execute")
        self.assertFalse(any(c[0].startswith("ValueInput.createByReal") for c in self.rec.calls))
        self.assertFalse(any("messageBox" in c[0] for c in self.rec.calls))

    def test_inspect_is_read_only(self):
        self.install()
        report = self.run_import("inspect")
        self.assertEqual(report["status"], "inspected")
        self.assertEqual(self.rec.writes, [])
        info = report["inspect"]
        self.assertEqual(info["design_type"], "parametric")
        self.assertEqual(info["component"], "root")
        self.assertTrue(info["component_is_root"])
        self.assertEqual(info["length_unit"], "mm")
        self.assertFalse(info["has_user_work"])
        self.assertEqual(info["touched"], [])
        self.assertEqual(info["collisions"], [])
        self.assertEqual(len(report["plan"]["parameters"]), 9)

    def test_no_group_flag(self):
        d = self.install()
        r = self.run_import("execute", group=False)["result"]
        self.assertIsNone(r["group"])
        self.assertEqual(d.timeline.timelineGroups.count, 0)

    def test_photos_only_import(self):
        doc = helpers.golden_doc()
        doc["features"] = []
        z = helpers.build_zip(self.root / "b", doc)
        self.plan, self.dir = ic.extract_bundle(z, self.root / "imports2")
        self.install()
        r = self.run_import("execute")
        self.assertTrue(r["ok"])
        self.assertEqual(len(r["result"]["created"]), 6)


class ReImport(Base):
    def test_parameters_updated_sketches_kept_canvases_refreshed_with_transform(self):
        d = self.prepopulate(self.install())
        before_sketches = list(d.activeComponent.sketches._items)
        inspect = self.run_import("inspect")["inspect"]
        self.assertTrue(inspect["has_user_work"])
        self.assertEqual(inspect["collisions"], [])
        self.assertEqual(sorted({t["action"] for t in inspect["touched"]}), ["keep", "refresh", "update"])
        self.assertEqual(self.rec.writes, [])

        report = self.run_import("execute")
        self.assertTrue(report["ok"], report)
        r = report["result"]
        self.assertEqual(r["updated"], ["parameter " + p["name"] for p in self.plan["parameters"]])
        self.assertEqual(r["created"], [])
        self.assertEqual(r["kept"], ["sketch top", "sketch side", "sketch end"])
        self.assertEqual(r["refreshed"], ["canvas top_photo", "canvas side_photo", "canvas end_photo"])
        self.assertEqual(r["carried_transforms"], ["top_photo", "side_photo", "end_photo"])
        self.assertEqual(r["previous"]["overall_l"]["expression"], "1 mm")
        self.assertIn("OLD", r["previous"]["overall_l"]["comment"])
        # nothing was deleted except the three old canvases; no parameter was added
        self.assertFalse(any(c[0] == "sketch.deleteMe" for c in self.rec.calls))
        self.assertFalse(any(c[0] == "userParameters.add" for c in self.rec.calls))
        self.assertEqual([c[1] for c in self.rec.calls if c[0] == "canvas.deleteMe"], ["top_photo", "side_photo", "end_photo"])
        # sketches are the very same objects
        self.assertEqual(d.activeComponent.sketches._items, before_sketches)
        # parameters carry the new expression, unit and comment
        p = d.userParameters.itemByName_silent("overall_l")
        self.assertEqual((p.expression, p.unit), ("42.18 mm", "mm"))
        self.assertTrue(p.comment.endswith("ccpart:" + SLUG))
        # canvases are new objects with the old transform and new attributes
        canvases = d.activeComponent.canvases._items
        self.assertEqual([c.name for c in canvases], ["top_photo", "side_photo", "end_photo"])
        self.assertEqual([c.transform.data for c in canvases], [[2, 0, 0, 2, 5, 5]] * 3)
        self.assertTrue(all(c.attributes._store[("caliper-companion", "ccpart")].value == SLUG for c in canvases))
        self.assertEqual(d.activeComponent.canvases.count, 3)
        # new-canvas-before-old-delete: createInput/add of the new one precede the old deleteMe
        names = [c[0] for c in self.rec.calls]
        self.assertLess(names.index("canvases.add"), names.index("canvas.deleteMe"))
        # the old group keeps the kept sketches (now 0..2); the new group spans only the three new canvases
        # (indices shift after the old canvases go)
        self.assertEqual(d.timeline.timelineGroups.count, 2)
        old_g, new_g = d.timeline.timelineGroups.item(0), d.timeline.timelineGroups.item(1)
        self.assertEqual((old_g.startIndex, old_g.endIndex), (0, 2))
        self.assertEqual((new_g.startIndex, new_g.endIndex, new_g.name), (3, 5, SLUG + " import"))
        self.assertEqual(d.timeline.count, 6)

    def test_transform_not_carried_when_pixel_size_changed(self):
        d = self.prepopulate(self.install(), pixels="800x600")
        r = self.run_import("execute")["result"]
        self.assertEqual(r["carried_transforms"], [])
        self.assertEqual([c.transform.data for c in d.activeComponent.canvases._items], [[1, 0, 0, 1, 0, 0]] * 3)
        self.assertTrue(any("pixel size changed (800x600 → 1600x1200)" in w for w in r["warnings"]))

    def test_second_import_is_idempotent(self):
        d = self.install()
        self.run_import("execute")
        self.rec.calls.clear()
        self.rec.writes.clear()
        r = self.run_import("execute")
        self.assertTrue(r["ok"])
        self.assertEqual(d.userParameters.count, 9)
        self.assertEqual(d.activeComponent.sketches.count, 3)
        self.assertEqual(d.activeComponent.canvases.count, 3)
        self.assertEqual(r["result"]["created"], [])
        self.assertEqual(len(r["result"]["refreshed"]), 3)


class Collisions(Base):
    def test_foreign_parameter_refuses_before_any_write(self):
        d = self.install()
        d.userParameters._preset("overall_l", "5 mm", "mm", "my own parameter")
        d.activeComponent.sketches._preset("top", d.activeComponent.xYConstructionPlane)
        inspect = self.run_import("inspect")
        self.assertEqual(inspect["inspect"]["collisions"], ["parameter overall_l", "sketch top"])
        report = self.run_import("execute")
        self.assertEqual(report["status"], "refused")
        self.assertEqual(len(report["reasons"]), 2)
        self.assertIn("parameter overall_l", report["reasons"][0])
        self.assertIn("sketch top", report["reasons"][1])
        self.assertIn("force=True", report["reasons"][0])
        self.assertEqual(self.rec.writes, [])
        self.assertEqual(d.userParameters.count, 1)

    def test_foreign_canvas_refuses(self):
        d = self.install()
        d.activeComponent.canvases._preset("side_photo", d.activeComponent.xZConstructionPlane)
        report = self.run_import("execute")
        self.assertEqual(report["status"], "refused")
        self.assertEqual(report["reasons"], ["name collision, not tagged ccpart:{}: canvas side_photo (pass force=True to overwrite)".format(SLUG)])
        self.assertEqual(self.rec.writes, [])

    def test_another_parts_import_refuses(self):
        d = self.prepopulate(self.install(), ours=False)
        report = self.run_import("execute")
        self.assertEqual(report["status"], "refused")
        self.assertEqual(len(report["reasons"]), 9 + 3 + 3)
        self.assertEqual(self.rec.writes, [])

    def test_force_overwrites(self):
        d = self.install()
        d.userParameters._preset("overall_l", "5 mm", "mm", "my own parameter")
        report = self.run_import("execute", force=True)
        self.assertTrue(report["ok"], report)
        self.assertEqual(report["result"]["updated"], ["parameter overall_l"])
        self.assertEqual(report["result"]["previous"]["overall_l"]["expression"], "5 mm")
        self.assertEqual(d.userParameters.itemByName_silent("overall_l").expression, "42.18 mm")


class Rollback(Base):
    def test_failure_on_second_canvas_deletes_exactly_the_created_in_reverse(self):
        d = self.install()
        self.rec.fail_on["canvases.add"] = 2
        report = self.run_import("execute")
        self.assertFalse(report["ok"])
        self.assertEqual(report["status"], "failed")
        self.assertIn("injected failure: canvases.add #2", report["result"]["error"])
        self.assertEqual(report["reasons"], ["fake_adsk.FakeError: injected failure: canvases.add #2"])
        deletes = [(c[0], c[1]) for c in self.rec.calls if c[0].endswith(".deleteMe")]
        expected = [("sketch.deleteMe", "side"), ("canvas.deleteMe", "top_photo"), ("sketch.deleteMe", "top")] + [("parameter.deleteMe", p["name"]) for p in reversed(self.plan["parameters"])]
        self.assertEqual(deletes, expected)
        self.assertEqual(report["result"]["rollback"], {"deleted": ["{} {}".format(k.split(".")[0], n) for k, n in expected], "failed": []})
        self.assertEqual(d.userParameters.count, 0)
        self.assertEqual(d.activeComponent.sketches.count, 0)
        self.assertEqual(d.activeComponent.canvases.count, 0)
        self.assertEqual(d.timeline.count, 0)
        self.assertEqual(report["result"]["created"], [])
        self.assertIsNone(report["result"]["group"])

    def test_rollback_names_what_would_not_delete(self):
        self.install()
        self.rec.fail_on["canvases.add"] = 2
        self.rec.delete_fails.add("top_photo")
        report = self.run_import("execute")
        self.assertEqual(report["result"]["rollback"]["failed"], ["canvas top_photo"])
        self.assertNotIn("canvas top_photo", report["result"]["rollback"]["deleted"])

    def test_failed_refresh_keeps_the_old_canvas_and_previous_expressions(self):
        d = self.prepopulate(self.install())
        old = list(d.activeComponent.canvases._items)
        self.rec.fail_on["canvases.add"] = 2
        report = self.run_import("execute")
        self.assertFalse(report["ok"])
        # the first refresh completed (old top deleted, new top exists) and was rolled back; side's old canvas survived
        self.assertEqual([c.name for c in d.activeComponent.canvases._items], ["side_photo", "end_photo"])
        self.assertIn(old[1], d.activeComponent.canvases._items)
        self.assertEqual(report["result"]["previous"]["overall_l"]["expression"], "1 mm")
        self.assertFalse(any(c[0] == "sketch.deleteMe" for c in self.rec.calls))

    def test_compute_deferred_is_reset_even_on_failure_above_six_faces(self):
        doc = helpers.golden_doc()
        base = doc["faces"][0]
        for i in range(5):
            f = dict(base)
            f.update({"id": "face:x{}".format(i), "label": "extra{}".format(i), "image": "faces/extra{}.jpg".format(i), "annotated": "faces/extra{}_dimensioned.png".format(i), "pixelWidth": 16, "pixelHeight": 16})
            doc["faces"].append(f)
        z = helpers.build_zip(self.root / "big", doc)
        self.plan, self.dir = ic.extract_bundle(z, self.root / "imports3")
        self.assertEqual(len(self.plan["sketches"]), 8)
        d = self.install()
        self.rec.fail_on["canvases.add"] = 4
        report = self.run_import("execute")
        self.assertFalse(report["ok"])
        sets = [c for c in self.rec.calls if c[0] == "design.isComputeDeferred="]
        self.assertEqual([c[2] for c in sets], [True, False])
        self.assertFalse(d.isComputeDeferred)
        # and with ≤ 6 faces it is never touched
        self.plan, self.dir = ic.extract_bundle(self.zip, self.root / "imports4")
        d = self.install()
        self.run_import("execute")
        self.assertFalse(any(c[0] == "design.isComputeDeferred=" for c in self.rec.calls))


class DesignState(Base):
    def test_rolled_back_timeline_refuses(self):
        d = self.install()
        d.activeComponent.sketches._preset("user_sketch", d.activeComponent.xYConstructionPlane)
        d.timeline._marker = 0
        inspect = self.run_import("inspect")["inspect"]
        self.assertTrue(inspect["timeline_rolled_back"])
        report = self.run_import("execute")
        self.assertEqual(report["status"], "refused")
        self.assertIn("timeline is rolled back (marker 0 of 1)", report["reasons"][0])
        self.assertEqual(self.rec.writes, [])

    def test_direct_modeling_proceeds_without_a_group(self):
        d = self.install(parametric=False)
        report = self.run_import("execute")
        self.assertTrue(report["ok"])
        self.assertIsNone(report["result"]["group"])
        self.assertIn("Direct-modeling design: no timeline group", report["warnings"])
        self.assertEqual(d.timeline.timelineGroups.count, 0)
        self.assertEqual(report["inspect"]["design_type"], "direct")

    def test_no_active_design_refuses(self):
        self.rec = fake_adsk.Recorder()
        fake_adsk.install(self.rec, product=None)
        report = self.run_import("execute")
        self.assertEqual(report["status"], "refused")
        self.assertIn("No active Fusion design", report["reasons"][0])
        self.assertEqual(self.rec.writes, [])

    def test_new_document(self):
        self.rec = fake_adsk.Recorder()
        _, app = fake_adsk.install(self.rec, product=None)
        report = self.run_import("execute", new_document=True)
        self.assertTrue(report["ok"], report)
        self.assertTrue(report["new_document"])
        self.assertEqual(self.rec.calls[1], ["documents.add", 0])
        self.assertEqual(app.activeProduct.userParameters.count, 9)

    def test_sub_component_is_the_target(self):
        d = self.install()
        sub = d._activate_sub("bracket")
        report = self.run_import("execute")
        self.assertTrue(report["ok"], report)
        self.assertEqual(report["inspect"]["component"], "bracket")
        self.assertFalse(report["inspect"]["component_is_root"])
        self.assertTrue(report["inspect"]["has_user_work"])
        self.assertEqual(sub.sketches.count, 3)
        self.assertEqual(d.rootComponent.sketches.count, 0)
        self.assertEqual(sub.canvases.count, 3)
        self.assertNotIn("target component is the root component", report["warnings"])

    def test_strict_refuses_flagged(self):
        doc = helpers.golden_doc()
        doc["features"][5]["flagged"] = True
        doc["features"][5]["spread"] = 0.3
        z = helpers.build_zip(self.root / "f", doc)
        self.plan, self.dir = ic.extract_bundle(z, self.root / "imports5")
        self.install()
        report = self.run_import("execute", strict=True)
        self.assertEqual(report["status"], "refused")
        self.assertEqual(report["reasons"], ["strict: flagged features overall_l"])
        self.assertEqual(self.rec.writes, [])
        report = self.run_import("execute")
        self.assertTrue(report["ok"])
        self.assertTrue(any("FLAGGED" in w for w in report["warnings"]))

    def test_bad_mode_and_missing_dir(self):
        self.install()
        self.assertEqual(ic.run_import({"mode": "nuke", "dir": str(self.dir)})["status"], "refused")
        self.assertEqual(ic.run_import({"mode": "inspect"})["status"], "refused")
        self.assertEqual(self.rec.writes, [])

    def test_planner_refusal_reaches_the_report(self):
        (self.dir / "features.json").write_text('{"schema": "x"}', encoding="utf-8")
        self.install()
        report = self.run_import("execute")
        self.assertEqual(report["status"], "refused")
        self.assertIn("unknown schema 'x'", report["reasons"][0])

    def test_scripts_dialog_run_uses_ccpart_args_once(self):
        self.install()
        ic.CCPART_ARGS = ic.default_args("inspect", self.dir)
        try:
            ic.run(None)
            self.assertEqual(ic.__dict__["__ccpart"]["status"], "inspected")
            n = len(self.rec.calls)
            ic.run(None)  # second call is a no-op
            self.assertEqual(len(self.rec.calls), n)
        finally:
            del ic.CCPART_ARGS
            ic.__dict__.pop("__ccpart", None)


class Standalone(Base):
    """The no-Claude path: Utilities → Scripts and Add-Ins → Run."""

    def message_boxes(self):
        return [c for c in self.rec.calls if c[0] == "userInterface.messageBox"]

    def test_standalone_plan_equals_mcp_plan_and_imports(self):
        d = self.install()
        self.rec.dialog_file = self.zip
        # clean slate for the staging dir: the standalone path stages the zip itself
        stage = self.root / "standalone"
        report = ic.run_standalone(stage)
        self.assertTrue(report["ok"], report)
        self.assertEqual(report["status"], "executed")
        mcp_plan = ic.run_import(ic.default_args("inspect", self.dir))["plan"]
        self.assertEqual(report["plan"], mcp_plan)
        self.assertEqual(report["plan"], ic.plan_import(self.zip))
        self.assertEqual(d.userParameters.count, 9)
        self.assertEqual(d.activeComponent.canvases.count, 3)
        staged = stage / SLUG
        self.assertTrue((staged / "features.json").exists())
        self.assertEqual(ic.read_phys((staged / "faces/top_dimensioned.png").read_bytes())[0], 16000)
        self.assertEqual(json.loads((staged / ic.REPORT_FILE).read_text(encoding="utf-8"))["status"], "executed")
        self.assertTrue(d.activeComponent.canvases._items[0].imageFilename.startswith(str(staged)))
        # dialogs: file dialog with the filter, then OK/Cancel confirmation, then the summary
        names = [c[0] for c in self.rec.calls]
        self.assertEqual(names.index("userInterface.createFileDialog"), 1)
        self.assertIn(["fileDialog.filter=", None, ic.STANDALONE_FILTER], self.rec.calls)
        boxes = self.message_boxes()
        self.assertEqual(len(boxes), 2)
        self.assertEqual(boxes[0][3], fake_adsk.MessageBoxButtonTypes.OKCancelButtonType)
        self.assertIn("overall_l", boxes[0][1])
        self.assertIn("42.18 mm", boxes[0][1])
        self.assertIn("Import into this design?", boxes[0][1])
        self.assertEqual(boxes[1][3], fake_adsk.MessageBoxButtonTypes.OKButtonType)
        self.assertIn("created (15)", boxes[1][1])
        self.assertIn("import-report.json", boxes[1][1])
        # the confirmation box comes before any write
        first_write = next(i for i, c in enumerate(self.rec.calls) if c[0] in self.rec.writes and not c[0].startswith("fileDialog."))
        self.assertLess(self.rec.calls.index(boxes[0]), first_write)

    def test_standalone_cancel_writes_nothing(self):
        self.install()
        self.rec.dialog_file = self.zip
        self.rec.dialog_answers = [fake_adsk.DialogResults.DialogCancel]
        report = ic.run_standalone(self.root / "standalone")
        self.assertEqual(report["status"], "cancelled")
        self.assertEqual([w for w in self.rec.writes if not w.startswith("fileDialog.")], [])
        self.assertEqual(len(self.message_boxes()), 1)

    def test_standalone_file_dialog_cancel(self):
        self.install()
        self.rec.dialog_file = None
        report = ic.run_standalone(self.root / "standalone")
        self.assertEqual(report["status"], "cancelled")
        self.assertEqual(self.message_boxes(), [])

    def test_standalone_collision_refuses_with_a_message(self):
        d = self.install()
        d.userParameters._preset("wall", "5 mm", "mm", "mine")
        self.rec.dialog_file = self.zip
        report = ic.run_standalone(self.root / "standalone")
        self.assertEqual(report["status"], "refused")
        self.assertEqual(report["reasons"], ["name collision: parameter wall"])
        boxes = self.message_boxes()
        self.assertEqual(len(boxes), 1)
        self.assertIn("parameter wall", boxes[0][1])
        self.assertEqual([w for w in self.rec.writes if not w.startswith("fileDialog.")], [])

    def test_standalone_bad_file_refuses_with_a_message(self):
        self.install()
        bad = self.root / "bad.ccpart.zip"
        bad.write_bytes(b"nope")
        self.rec.dialog_file = bad
        report = ic.run_standalone(self.root / "standalone")
        self.assertEqual(report["status"], "refused")
        self.assertEqual(len(self.message_boxes()), 1)
        self.assertIn("not valid JSON", self.message_boxes()[0][1])

    def test_standalone_accepts_a_bare_features_json(self):
        d = self.install()
        self.rec.dialog_file = self.dir / "features.json"  # the staged folder: has faces/ next to it
        report = ic.run_standalone(self.root / "standalone")
        self.assertEqual(report["status"], "executed", report)
        self.assertEqual(report["plan"]["sketches"][0]["canvas_file"], None)  # a bare json carries no bundle files
        self.assertEqual(d.activeComponent.canvases.count, 0)
        self.assertEqual(d.activeComponent.sketches.count, 3)

    def test_run_dispatches_to_standalone_when_no_args(self):
        d = self.install()
        self.rec.dialog_file = self.zip
        ic.DEFAULT_IMPORTS_DIR_BACKUP = ic.DEFAULT_IMPORTS_DIR
        try:
            ic.DEFAULT_IMPORTS_DIR = str(self.root / "standalone")
            ic.run_standalone.__defaults__ = (ic.DEFAULT_IMPORTS_DIR,)
            ic.run(None)
            self.assertEqual(ic.__dict__["__ccpart"]["status"], "executed")
            self.assertEqual(d.userParameters.count, 9)
            n = len(self.rec.calls)
            ic.run(None)  # __ccpart set → no-op
            self.assertEqual(len(self.rec.calls), n)
        finally:
            ic.DEFAULT_IMPORTS_DIR = ic.DEFAULT_IMPORTS_DIR_BACKUP
            ic.run_standalone.__defaults__ = (ic.DEFAULT_IMPORTS_DIR,)
            ic.__dict__.pop("__ccpart", None)

    def test_mcp_path_never_opens_a_dialog(self):
        self.prepopulate(self.install())
        self.run_import("inspect")
        self.run_import("execute")
        self.assertEqual(self.message_boxes(), [])
        self.assertFalse(any(c[0] == "userInterface.createFileDialog" for c in self.rec.calls))


class NoFusion(unittest.TestCase):
    def test_execute_outside_fusion_refuses_cleanly(self):
        fake_adsk.uninstall()
        with tempfile.TemporaryDirectory() as td:
            z = helpers.build_zip(td)
            _, d = ic.extract_bundle(z, Path(td) / "imports")
            report = ic.run_import(ic.default_args("execute", d))
            self.assertEqual(report["status"], "refused")
            self.assertIn("adsk", report["reasons"][0])
            self.assertTrue((d / ic.REPORT_FILE).exists())

    def test_cli_execute_outside_fusion_exits_2(self):
        with tempfile.TemporaryDirectory() as td:
            z = helpers.build_zip(td)
            _, d = ic.extract_bundle(z, Path(td) / "imports")
            import subprocess

            r = subprocess.run([sys.executable, str(helpers.SCRIPT), "--execute", str(d)], capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(r.returncode, 2)
            self.assertIn("adsk", json.loads(r.stdout)["reasons"][0])


if __name__ == "__main__":
    unittest.main()
