"""Planner, PNG/pHYs helpers, extract and CLI — all without Fusion.

    python3 -m unittest discover -s .claude/skills/fusion-import/tests
"""

import ast
import copy
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import helpers
import import_ccpart as ic


def plan_of(doc, **kw):
    with tempfile.TemporaryDirectory() as td:
        return ic.plan_import(helpers.build_zip(td, doc, **kw))


class GoldenPlan(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.td = tempfile.TemporaryDirectory()
        cls.zip = helpers.build_zip(cls.td.name)
        cls.plan = ic.plan_import(cls.zip)

    @classmethod
    def tearDownClass(cls):
        cls.td.cleanup()

    def test_nine_parameters_with_exact_expressions(self):
        p = self.plan
        self.assertEqual(p["slug"], "norcold_freezer_hinge_pin")
        self.assertEqual(p["units"], "mm")
        self.assertEqual(
            [(x["name"], x["expression"]) for x in p["parameters"]],
            [
                ("chamfer", "0.8 mm"),
                ("groove_depth", "1.1 mm"),
                ("groove_w", "2 mm"),
                ("head_dia", "9 mm"),
                ("head_h", "3.2 mm"),
                ("overall_l", "42.18 mm"),
                ("overall_w", "12.4 mm"),
                ("pin_dia", "6.51 mm"),
                ("wall", "1.8 mm"),
            ],
        )
        overall = next(x for x in p["parameters"] if x["name"] == "overall_l")
        self.assertEqual(overall["comment"], "length ±0.1 mm · faces top · ccpart:norcold_freezer_hinge_pin")
        self.assertEqual(overall["unit"], "mm")
        self.assertFalse(overall["flagged"])
        self.assertTrue(all(x["comment"].endswith("ccpart:norcold_freezer_hinge_pin") for x in p["parameters"]))

    def test_three_sketches_on_the_right_planes_with_canvases(self):
        s = self.plan["sketches"]
        self.assertEqual([(x["name"], x["plane"]) for x in s], [("top", "xYConstructionPlane"), ("side", "xZConstructionPlane"), ("end", "yZConstructionPlane")])
        self.assertEqual([x["canvas_name"] for x in s], ["top_photo", "side_photo", "end_photo"])
        self.assertEqual([x["canvas_file"] for x in s], ["faces/top_dimensioned.png", "faces/side_dimensioned.png", "faces/end_dimensioned.png"])
        self.assertEqual([(x["png_width"], x["png_height"]) for x in s], [(1600, 1200), (1600, 1200), (1200, 1600)])

    def test_group_name_and_no_warnings(self):
        self.assertEqual(self.plan["group_name"], "norcold_freezer_hinge_pin import")
        self.assertEqual(self.plan["warnings"], [])
        self.assertEqual(self.plan["flagged"], [])
        self.assertEqual(self.plan["canvas_width_mm"], 100.0)
        self.assertEqual(self.plan["canvas_opacity"], 60)

    def test_plan_snapshot_byte_for_byte(self):
        text = json.dumps(self.plan, indent=2, ensure_ascii=False) + "\n"
        expected, path = helpers.snapshot("hinge_pin.plan.json", text)
        self.assertEqual(text, expected, "plan drifted from {} (UPDATE_GOLDEN=1 to accept)".format(path))

    def test_dry_run_cli_prints_the_snapshot(self):
        r = subprocess.run([sys.executable, str(helpers.SCRIPT), "--dry-run", str(self.zip)], capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(r.returncode, 0, r.stderr)
        expected, _ = helpers.snapshot("hinge_pin.plan.json", r.stdout)
        self.assertEqual(r.stdout, expected)

    def test_plan_has_no_absolute_paths(self):
        self.assertNotIn(self.td.name, json.dumps(self.plan))

    def test_bare_folder_plans_the_same_parameters_but_skips_canvases(self):
        p = ic.plan_import(helpers.GOLDEN_FEATURES.parent)  # fixtures/hinge_pin/ has JPEGs, no dimensioned PNGs
        self.assertEqual([x["expression"] for x in p["parameters"]], [x["expression"] for x in self.plan["parameters"]])
        self.assertEqual([x["canvas_file"] for x in p["sketches"]], [None, None, None])
        self.assertEqual(len(p["warnings"]), 3)
        self.assertTrue(all("missing from the bundle" in w for w in p["warnings"]))

    def test_bare_json_skips_every_canvas_with_a_warning(self):
        p = ic.plan_import(helpers.GOLDEN_FEATURES)
        self.assertEqual([x["canvas_file"] for x in p["sketches"]], [None, None, None])
        self.assertTrue(all("bare features.json" in w for w in p["warnings"]))


class Validation(unittest.TestCase):
    def setUp(self):
        self.doc = helpers.golden_doc()

    def refuse(self, doc=None, **kw):
        with self.assertRaises(ic.RefuseImport) as cm:
            plan_of(doc if doc is not None else self.doc, **kw)
        return "\n".join(cm.exception.reasons)

    def test_wrong_schema_refuses_and_shows_the_string(self):
        self.doc["schema"] = "caliper-companion/features/2"
        self.assertIn("'caliper-companion/features/2'", self.refuse())

    def test_flagged_feature_gets_prefix_and_warning(self):
        f = self.doc["features"][5]
        f["flagged"] = True
        f["spread"] = 0.12
        p = plan_of(self.doc)
        overall = next(x for x in p["parameters"] if x["name"] == "overall_l")
        self.assertTrue(overall["comment"].startswith("FLAGGED spread 0.12 > ±0.1 · "))
        self.assertTrue(overall["flagged"])
        self.assertEqual(overall["expression"], "42.18 mm")  # value still verbatim
        self.assertEqual(p["flagged"], ["overall_l"])
        self.assertEqual(len(p["warnings"]), 1)
        self.assertIn("FLAGGED", p["warnings"][0])

    def test_missing_annotated_file_warns_and_skips_that_canvas(self):
        p = plan_of(self.doc, drop=("faces/side_dimensioned.png",))
        side = next(x for x in p["sketches"] if x["name"] == "side")
        self.assertIsNone(side["canvas_file"])
        self.assertEqual(len(p["warnings"]), 1)
        self.assertIn("side_dimensioned.png", p["warnings"][0])
        self.assertEqual(len([x for x in p["sketches"] if x["canvas_file"]]), 2)

    def test_inch_part(self):
        self.doc["part"]["units"] = "in"
        self.doc["features"][5]["value"] = 1.375
        p = plan_of(self.doc)
        overall = next(x for x in p["parameters"] if x["name"] == "overall_l")
        self.assertEqual(overall["expression"], "1.375 in")
        self.assertEqual(overall["unit"], "in")
        self.assertIn("±0.1 in", overall["comment"])

    def test_kind_conflict_refuses(self):
        dup = copy.deepcopy(self.doc["features"][5])
        dup["kind"] = "diameter"
        self.doc["features"].append(dup)
        self.assertIn("kind conflict: feature 'overall_l'", self.refuse())

    def test_duplicate_feature_refuses(self):
        self.doc["features"].append(copy.deepcopy(self.doc["features"][5]))
        self.assertIn("duplicate feature 'overall_l'", self.refuse())

    def test_name_rule_refuses(self):
        for bad in ("Overall", "1x", "a-b", "a" * 33, "", None):
            doc = copy.deepcopy(self.doc)
            doc["features"][0]["name"] = bad
            self.assertIn("fails the name rule", self.refuse(doc), repr(bad))

    def test_reserved_names_refuse(self):
        for bad in ("pi", "sqrt", "d1", "d12", "mm", "in", "deg"):
            doc = copy.deepcopy(self.doc)
            doc["features"][0]["name"] = bad
            self.assertIn("{!r} is reserved".format(bad), self.refuse(doc))

    def test_faces_empty_refuses(self):
        self.doc["faces"] = []
        self.assertIn("nothing to import", self.refuse())

    def test_features_empty_is_a_warning_not_a_refusal(self):
        self.doc["features"] = []
        p = plan_of(self.doc)
        self.assertEqual(p["parameters"], [])
        self.assertEqual(len(p["sketches"]), 3)
        self.assertTrue(any("photos-only" in w for w in p["warnings"]))

    def test_unknown_face_id_refuses(self):
        self.doc["features"][0]["faceIds"] = ["face:nope"]
        self.assertIn("faceIds entry 'face:nope' is not in faces[]", self.refuse())

    def test_bad_values_refuse(self):
        for bad in (0, -1, "42", None, float("nan"), float("inf"), True):
            doc = copy.deepcopy(self.doc)
            doc["features"][0]["value"] = bad
            self.assertIn("must be a finite number > 0", self.refuse(doc), repr(bad))
        doc = copy.deepcopy(self.doc)
        doc["features"][0]["value"] = 0.00001
        self.assertIn("rounds to 0", self.refuse(doc))

    def test_unknown_feature_kind_refuses(self):
        self.doc["features"][0]["kind"] = "angle"
        self.assertIn("unknown kind 'angle'", self.refuse())

    def test_unknown_face_kind_refuses(self):
        self.doc["faces"][0]["kind"] = "bottom"
        self.assertIn("unknown kind 'bottom'", self.refuse())

    def test_bad_units_refuse(self):
        self.doc["part"]["units"] = "cm"
        self.assertIn("part.units 'cm'", self.refuse())

    def test_bad_slug_refuses(self):
        self.doc["part"]["slug"] = "Hinge Pin"
        self.assertIn("part.slug 'Hinge Pin'", self.refuse())

    def test_all_errors_are_collected(self):
        self.doc["features"][0]["name"] = "pi"
        self.doc["features"][1]["value"] = -3
        reasons = self.refuse()
        self.assertIn("'pi' is reserved", reasons)
        self.assertIn("groove_depth", reasons)

    def test_unknown_json_fields_are_ignored(self):
        self.doc["future"] = {"x": 1}
        self.doc["part"]["colour"] = "red"
        self.doc["faces"][0]["extra"] = [1, 2]
        self.doc["features"][0]["note"] = "hi"
        self.assertEqual(len(plan_of(self.doc)["parameters"]), 9)

    def test_part_path_defaults_to_empty(self):
        self.doc["part"].pop("path", None)
        self.assertEqual(plan_of(self.doc)["part_path"], "")
        self.doc["part"]["path"] = "Miata/Interior"
        self.assertEqual(plan_of(self.doc)["part_path"], "Miata/Interior")


class Ordering(unittest.TestCase):
    def test_faces_by_kind_order_then_label_and_custom_faces(self):
        doc = helpers.golden_doc()
        faces = doc["faces"]
        custom = copy.deepcopy(faces[1])
        custom.update({"id": "face:custom", "label": "left_side", "image": "faces/left_side.jpg", "annotated": "faces/left_side_dimensioned.png"})
        detail = copy.deepcopy(faces[0])
        detail.update({"id": "face:detail", "kind": "detail", "label": "a_detail", "image": "faces/a_detail.jpg", "annotated": "faces/a_detail_dimensioned.png"})
        doc["faces"] = [detail, faces[2], custom, faces[1], faces[0]]  # scrambled
        p = plan_of(doc)
        self.assertEqual([x["name"] for x in p["sketches"]], ["top", "left_side", "side", "end", "a_detail"])
        self.assertEqual(next(x for x in p["sketches"] if x["name"] == "left_side")["plane"], "xZConstructionPlane")
        self.assertEqual(next(x for x in p["sketches"] if x["name"] == "a_detail")["plane"], "xYConstructionPlane")
        self.assertEqual(next(x for x in p["sketches"] if x["name"] == "left_side")["canvas_name"], "left_side_photo")

    def test_parameters_keep_file_order(self):
        doc = helpers.golden_doc()
        doc["features"].reverse()
        p = plan_of(doc)
        self.assertEqual([x["name"] for x in p["parameters"]], [f["name"] for f in doc["features"]])

    def test_pre_a7_face_without_label_uses_kind(self):
        doc = helpers.golden_doc()
        for f in doc["faces"]:
            f.pop("label")
        self.assertEqual([x["name"] for x in plan_of(doc)["sketches"]], ["top", "side", "end"])

    def test_duplicate_label_refuses(self):
        doc = helpers.golden_doc()
        doc["faces"][1]["label"] = "top"
        with self.assertRaises(ic.RefuseImport) as cm:
            plan_of(doc)
        self.assertIn("duplicate face label 'top'", "\n".join(cm.exception.reasons))

    def test_png_size_disagreeing_with_json_warns_and_uses_the_png(self):
        doc = helpers.golden_doc()
        doc["faces"][0]["pixelWidth"] = 800
        p = plan_of(doc, extra_files={"faces/top_dimensioned.png": helpers.make_png(1600, 1200)})
        # build_zip writes 800x1200 for the face; the extra file overrides it inside the zip
        top = next(x for x in p["sketches"] if x["name"] == "top")
        self.assertEqual((top["png_width"], top["png_height"]), (1600, 1200))
        self.assertTrue(any("1600x1200 px but features.json says 800x1200" in w for w in p["warnings"]))

    def test_render_scale_is_applied_to_the_expected_size(self):
        doc = helpers.golden_doc()
        doc["faces"][0]["pixelWidth"] = 4000
        doc["faces"][0]["pixelHeight"] = 3000
        doc["faces"][0]["renderScale"] = 0.4
        p = plan_of(doc)  # build_zip writes 1600x1200
        self.assertEqual(p["warnings"], [])


class Numbers(unittest.TestCase):
    def test_fmt_number(self):
        for v, s in ((42.18, "42.18"), (2, "2"), (2.0, "2"), (0.1, "0.1"), (0.05, "0.05"), (1.375, "1.375"), (0.00001, "0"), (1e-5, "0"), (12.3456, "12.3456"), (100, "100")):
            self.assertEqual(ic.fmt_number(v), s)
        self.assertNotIn("e", ic.fmt_number(0.0001))


class Png(unittest.TestCase):
    def test_write_phys_produces_a_valid_png_with_the_right_ppm(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "x.png"
            p.write_bytes(helpers.make_png(1600, 1200))
            self.assertIsNone(ic.read_phys(p.read_bytes()))
            ppm = ic.write_phys(p)
            self.assertEqual(ppm, 16000)
            data = p.read_bytes()
            chunks = list(ic.png_chunks(data))  # re-parses every CRC
            self.assertEqual([c[0] for c in chunks], [b"IHDR", b"pHYs", b"IDAT", b"IEND"])
            self.assertEqual(ic.read_phys(data), (16000, 16000, 1))
            self.assertEqual(ic.png_dimensions(p), (1600, 1200))
            # idempotent: a second write replaces, never duplicates
            ic.write_phys(p)
            self.assertEqual([c[0] for c in ic.png_chunks(p.read_bytes())].count(b"pHYs"), 1)

    def test_phys_math(self):
        self.assertEqual(ic.phys_pixels_per_metre(1600), 16000)
        self.assertEqual(ic.phys_pixels_per_metre(1200), 12000)
        self.assertEqual(ic.phys_pixels_per_metre(4096, 100.0), 40960)

    def test_non_png_is_rejected(self):
        with self.assertRaises(ValueError):
            ic.png_dimensions_bytes(b"\xff\xd8\xff\xd9" + b"\x00" * 30)
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "x.png"
            data = bytearray(helpers.make_png(4, 4))
            data[-1] ^= 0xFF  # corrupt the IEND CRC
            p.write_bytes(bytes(data))
            with self.assertRaises(ValueError):
                ic.write_phys(p)

    def test_non_png_annotated_refuses(self):
        doc = helpers.golden_doc()
        with self.assertRaises(ic.RefuseImport) as cm:
            plan_of(doc, extra_files={"faces/top_dimensioned.png": b"not a png at all"})
        self.assertIn("is not a PNG", "\n".join(cm.exception.reasons))


class ExtractAndEmit(unittest.TestCase):
    def test_extract_unzips_writes_phys_and_drops_a_stale_report(self):
        with tempfile.TemporaryDirectory() as td:
            z = helpers.build_zip(td)
            root = Path(td) / "imports"
            stale_dir = root / "norcold_freezer_hinge_pin"
            stale_dir.mkdir(parents=True)
            (stale_dir / ic.REPORT_FILE).write_text("{}")
            plan, dest = ic.extract_bundle(z, root)
            self.assertEqual(dest, stale_dir)
            self.assertFalse((dest / ic.REPORT_FILE).exists())
            self.assertTrue((dest / "features.json").exists())
            for s in plan["sketches"]:
                data = (dest / s["canvas_file"]).read_bytes()
                self.assertEqual(ic.read_phys(data), (ic.phys_pixels_per_metre(s["png_width"]), ic.phys_pixels_per_metre(s["png_width"]), 1))
            self.assertEqual(ic.read_phys((dest / "faces/end_dimensioned.png").read_bytes())[0], 12000)
            # the extracted folder plans identically
            self.assertEqual(ic.plan_import(dest), plan)

    def test_extract_stages_a_folder_and_a_bare_json_too(self):
        with tempfile.TemporaryDirectory() as td:
            z = helpers.build_zip(td)
            _, unzipped = ic.extract_bundle(z, Path(td) / "a")
            plan, dest = ic.extract_bundle(unzipped, Path(td) / "b")
            self.assertEqual(dest, Path(td) / "b" / "norcold_freezer_hinge_pin")
            self.assertEqual(sorted(p.name for p in (dest / "faces").iterdir()), ["end_dimensioned.png", "side_dimensioned.png", "top_dimensioned.png"])
            self.assertEqual(ic.plan_import(dest), plan)
            plan2, dest2 = ic.extract_bundle(helpers.GOLDEN_FEATURES, Path(td) / "c")
            self.assertEqual([s["canvas_file"] for s in plan2["sketches"]], [None, None, None])
            self.assertTrue((dest2 / "features.json").exists())
            with self.assertRaises(ic.RefuseImport):
                ic.extract_bundle(dest, Path(td) / "b")  # staging onto itself

    def test_zip_slip_is_refused(self):
        with tempfile.TemporaryDirectory() as td:
            z = helpers.build_zip(td, extra_files={"../evil.txt": b"x"})
            with self.assertRaises(ic.RefuseImport) as cm:
                ic.extract_bundle(z, Path(td) / "imports")
            self.assertIn("unsafe path", "\n".join(cm.exception.reasons))
            self.assertFalse((Path(td) / "evil.txt").exists())

    def test_extract_cli(self):
        with tempfile.TemporaryDirectory() as td:
            z = helpers.build_zip(td)
            r = subprocess.run([sys.executable, str(helpers.SCRIPT), "--extract", str(z), "--to", str(Path(td) / "imp")], capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(r.returncode, 0, r.stderr)
            out = json.loads(r.stdout)
            self.assertEqual(out["dir"], str(Path(td) / "imp" / "norcold_freezer_hinge_pin"))
            self.assertEqual(len(out["parameters"]), 9)

    def test_mcp_code_compiles_with_a_hostile_path_and_round_trips_args(self):
        hostile = "/Users/dwight/My Parts/it's \"quoted\" — café/norcold_freezer_hinge_pin"
        args = ic.default_args("inspect", hostile, new_document=False, group=True, force=False, strict=False)
        code = ic.mcp_code(args, helpers.SCRIPT)
        compile(code, "<mcp>", "exec")
        last = code.rstrip("\n").splitlines()[-1]
        self.assertTrue(last.startswith("__ccpart = run_import({"))
        self.assertNotIn("\n", last)
        literal = ast.literal_eval(last[len("__ccpart = run_import(") : -1])
        self.assertEqual(literal, args)
        self.assertEqual(literal["dir"], hostile)
        # the module-level CLI guard is inert under exec (no __name__ in the namespace)
        ns = {}
        exec(compile(code.replace("__ccpart = run_import(", "__probe = ("), "<mcp>", "exec"), ns)  # noqa: S102
        self.assertEqual(ns["__probe"], args)
        self.assertIn("run_import", ns)
        self.assertIn("run", ns)

    def test_emit_cli_matches_mcp_code(self):
        with tempfile.TemporaryDirectory() as td:
            r = subprocess.run([sys.executable, str(helpers.SCRIPT), "--emit", td, "--mode", "execute", "--force"], capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertEqual(r.stdout, ic.mcp_code(ic.default_args("execute", td, force=True), helpers.SCRIPT))

    def test_dry_run_refusal_exits_2(self):
        with tempfile.TemporaryDirectory() as td:
            doc = helpers.golden_doc()
            doc["schema"] = "nope"
            z = helpers.build_zip(td, doc)
            r = subprocess.run([sys.executable, str(helpers.SCRIPT), "--dry-run", str(z)], capture_output=True, text=True, encoding="utf-8")
            self.assertEqual(r.returncode, 2)
            out = json.loads(r.stdout)
            self.assertEqual(out["status"], "refused")
            self.assertIn("'nope'", out["reasons"][0])

    def test_dry_run_missing_path_exits_2(self):
        r = subprocess.run([sys.executable, str(helpers.SCRIPT), "--dry-run", "/nonexistent/x.ccpart.zip"], capture_output=True, text=True, encoding="utf-8")
        self.assertEqual(r.returncode, 2)

    def test_run_stays_a_noop_without_args(self):
        self.assertIsNone(ic.run(None))


if __name__ == "__main__":
    unittest.main()
