"""fake_adsk.py — a small recording fake of the `adsk` surface `import_ccpart.py` touches. Tests only.

Install it into `sys.modules` (`install()`) before the executor imports `adsk`; every call and property
set is appended to `Recorder.calls` (plain JSON-able rows) and every mutation to `Recorder.writes`, so
tests can snapshot the call log, assert zero writes on a refusal, and inject a failure on the n-th call
of any method (`rec.fail_on["canvases.add"] = 2`). Unknown attributes raise (typos never pass silently),
`ValueInput.createByReal` raises (cookbook trap 1: lengths are expression strings only).

It models only what the executor uses: Application/Design/Component, userParameters, sketches, canvases
(+ CanvasInput, Matrix2D transform), attributes, timeline (+ groups, marker), documents.add.
"""

import sys
import types


class FakeError(RuntimeError):
    pass


class Recorder(object):
    def __init__(self):
        self.calls = []
        self.writes = []
        self.fail_on = {}  # "canvases.add" → 1-based occurrence that raises
        self.delete_fails = set()  # entity names whose deleteMe() returns False
        self.dialog_file = None  # what the fake file dialog "chooses"; None → the user cancelled
        self.dialog_answers = []  # scripted messageBox results, popped in order; empty → DialogOK
        self._counts = {}

    def record(self, name, *args, **kw):
        write = kw.get("write", False)
        self.calls.append([name] + [plain(a) for a in args])
        if write:
            self.writes.append(name)
        n = self._counts.get(name, 0) + 1
        self._counts[name] = n
        if self.fail_on.get(name) == n:
            raise FakeError("injected failure: {} #{}".format(name, n))


def plain(a):
    """Entities → their names, inputs → dicts, matrices → lists; everything else as is."""
    if isinstance(a, Plane):
        return a.name
    if isinstance(a, ValueInput):
        return a.expression
    if isinstance(a, CanvasInput):
        return {"file": a.imageFilename, "plane": a.planarEntity.name, "opacity": a.opacity, "transform": plain(a.transform)}
    if isinstance(a, Matrix2D):
        return list(a.data)
    if isinstance(a, Base):
        return getattr(a, "name", a._tag)
    return a


class Base(object):
    _tag = "obj"
    _writable = ()

    def __init__(self, rec):
        object.__setattr__(self, "_rec", rec)

    def _ident(self):
        return object.__getattribute__(self, "__dict__").get("name")

    def __setattr__(self, k, v):
        if k.startswith("_"):
            object.__setattr__(self, k, v)
            return
        if k not in self._writable:
            raise AttributeError("{} has no writable attribute {!r}".format(self._tag, k))
        self._rec.record("{}.{}=".format(self._tag, k), self._ident(), v, write=True)
        object.__setattr__(self, k, v)

    def _set(self, k, v):  # silent set, for fixture building
        object.__setattr__(self, k, v)


# ---- core -------------------------------------------------------------------------------------------------------


class ValueInput(object):
    def __init__(self, expression):
        self.expression = expression

    @staticmethod
    def createByString(s):
        return ValueInput(s)

    @staticmethod
    def createByReal(v):
        raise FakeError("ValueInput.createByReal({}) — lengths must be expression strings".format(v))


class Matrix2D(object):
    def __init__(self, data=None):
        self.data = list(data) if data is not None else [1, 0, 0, 1, 0, 0]

    @staticmethod
    def create():
        return Matrix2D()

    def copy(self):
        return Matrix2D(self.data)


class Attribute(object):
    def __init__(self, group, name, value):
        self.groupName = group
        self.name = name
        self.value = value


class Attributes(Base):
    _tag = "attributes"

    def __init__(self, rec, owner):
        Base.__init__(self, rec)
        self._owner = owner
        self._store = {}

    def add(self, group, name, value):
        self._rec.record("{}.attributes.add".format(self._owner._tag), self._owner._ident(), group, name, value, write=True)
        a = Attribute(group, name, value)
        self._store[(group, name)] = a
        return a

    def itemByName(self, group, name):
        self._rec.record("{}.attributes.itemByName".format(self._owner._tag), self._owner._ident(), group, name)
        return self._store.get((group, name))

    def _preset(self, group, name, value):
        self._store[(group, name)] = Attribute(group, name, value)


class Document(Base):
    _tag = "document"

    def __init__(self, rec, name):
        Base.__init__(self, rec)
        self._set("name", name)


class Documents(Base):
    _tag = "documents"

    def __init__(self, rec, app):
        Base.__init__(self, rec)
        self._app = app

    def add(self, doc_type):
        self._rec.record("documents.add", doc_type, write=True)
        design = make_design(self._rec, name="Untitled")
        self._app._set("activeProduct", design)
        return design.parentDocument


class Application(Base):
    _tag = "application"
    _instance = None

    def __init__(self, rec, product=None):
        Base.__init__(self, rec)
        self._set("activeProduct", product)
        self._set("documents", Documents(rec, self))
        self._set("userInterface", UserInterface(rec))

    @classmethod
    def get(cls):
        cls._instance._rec.record("Application.get")
        return cls._instance


class DialogResults(object):
    DialogOK = 0
    DialogCancel = 1
    DialogYes = 2
    DialogNo = 3


class MessageBoxButtonTypes(object):
    OKButtonType = 0
    OKCancelButtonType = 1
    YesNoButtonType = 3


class MessageBoxIconTypes(object):
    NoIconIconType = 0
    QuestionIconType = 1
    InformationIconType = 2
    WarningIconType = 3


class FileDialog(Base):
    _tag = "fileDialog"
    _writable = ("title", "filter", "filterIndex", "isMultiSelectEnabled", "initialDirectory")

    def __init__(self, rec):
        Base.__init__(self, rec)
        self._set("filename", "")

    def showOpen(self):
        self._rec.record("fileDialog.showOpen")
        if self._rec.dialog_file is None:
            return DialogResults.DialogCancel
        self._set("filename", str(self._rec.dialog_file))
        return DialogResults.DialogOK


class UserInterface(Base):
    _tag = "userInterface"

    def createFileDialog(self):
        self._rec.record("userInterface.createFileDialog")
        return FileDialog(self._rec)

    def messageBox(self, text, title="", buttons=MessageBoxButtonTypes.OKButtonType, icon=MessageBoxIconTypes.NoIconIconType):
        self._rec.record("userInterface.messageBox", text, title, buttons, icon)
        if self._rec.dialog_answers:
            return self._rec.dialog_answers.pop(0)
        return DialogResults.DialogOK


# ---- fusion -----------------------------------------------------------------------------------------------------


class DesignTypes(object):
    DirectDesignType = 0
    ParametricDesignType = 1


class DocumentTypes(object):
    FusionDesignDocumentType = 0


class Plane(Base):
    _tag = "plane"

    def __init__(self, rec, name):
        Base.__init__(self, rec)
        self._set("name", name)


class TimelineObject(object):
    def __init__(self, timeline, entity):
        self._timeline = timeline
        self.entity = entity

    @property
    def index(self):
        return self._timeline._items.index(self)


class TimelineGroup(Base):
    _tag = "timelineGroup"
    _writable = ("name",)

    def __init__(self, rec, groups, members):
        Base.__init__(self, rec)
        self._groups = groups
        self._members = list(members)
        self._set("name", "Group")

    @property
    def startIndex(self):
        return min(m.index for m in self._members)

    @property
    def endIndex(self):
        return max(m.index for m in self._members)

    def deleteMe(self, delete_members=False):
        self._rec.record("timelineGroup.deleteMe", self.name, delete_members, write=True)
        self._groups._groups.remove(self)
        return True


class TimelineGroups(Base):
    _tag = "timelineGroups"

    def __init__(self, rec, timeline):
        Base.__init__(self, rec)
        self._timeline = timeline
        self._groups = []

    def add(self, start, end):
        self._rec.record("timelineGroups.add", start, end, write=True)
        if not (0 <= start <= end < len(self._timeline._items)):
            raise FakeError("timelineGroups.add({}, {}) out of range (count {})".format(start, end, len(self._timeline._items)))
        for g in self._groups:
            if not (end < g.startIndex or start > g.endIndex):
                raise FakeError("timelineGroups.add overlaps group {!r}".format(g.name))
        g = TimelineGroup(self._rec, self, self._timeline._items[start : end + 1])
        self._groups.append(g)
        return g

    @property
    def count(self):
        return len(self._groups)

    def item(self, i):
        return self._groups[i]


class Timeline(Base):
    _tag = "timeline"

    def __init__(self, rec):
        Base.__init__(self, rec)
        self._items = []
        self._marker = None  # None → follows count
        self._set("timelineGroups", TimelineGroups(rec, self))

    @property
    def count(self):
        return len(self._items)

    @property
    def markerPosition(self):
        return len(self._items) if self._marker is None else self._marker

    def item(self, i):
        return self._items[i]

    def _push(self, entity):
        to = TimelineObject(self, entity)
        self._items.append(to)
        return to

    def _remove(self, to):
        self._items.remove(to)
        for g in list(self.timelineGroups._groups):
            if to in g._members:
                g._members.remove(to)
                if not g._members:
                    self.timelineGroups._groups.remove(g)


class Sketch(Base):
    _tag = "sketch"
    _writable = ("name",)

    def __init__(self, rec, owner, plane, name):
        Base.__init__(self, rec)
        self._owner = owner
        self._set("name", name)
        self._set("referencePlane", plane)
        self._set("attributes", Attributes(rec, self))
        self._set("timelineObject", None)
        self._set("isDeleted", False)

    def deleteMe(self):
        self._rec.record("sketch.deleteMe", self.name, write=True)
        if self.name in self._rec.delete_fails:
            return False
        self._owner._remove(self)
        self._set("isDeleted", True)
        return True


class Sketches(Base):
    _tag = "sketches"

    def __init__(self, rec, component):
        Base.__init__(self, rec)
        self._component = component
        self._items = []
        self._serial = 0

    def add(self, plane):
        self._rec.record("sketches.add", plane, write=True)
        if not isinstance(plane, Plane):
            raise FakeError("sketches.add: not a planar entity: {!r}".format(plane))
        self._serial += 1
        sk = Sketch(self._rec, self, plane, "Sketch{}".format(self._serial))
        self._items.append(sk)
        sk._set("timelineObject", self._component._design.timeline._push(sk))
        return sk

    def itemByName(self, name):
        self._rec.record("sketches.itemByName", name)
        for s in self._items:
            if s.name == name:
                return s
        return None

    def item(self, i):
        return self._items[i]

    @property
    def count(self):
        return len(self._items)

    def _remove(self, sk):
        self._items.remove(sk)
        if sk.timelineObject is not None:
            self._component._design.timeline._remove(sk.timelineObject)

    def _preset(self, name, plane, attrs=None):
        sk = Sketch(self._rec, self, plane, name)
        self._items.append(sk)
        sk._set("timelineObject", self._component._design.timeline._push(sk))
        for k, v in (attrs or {}).items():
            sk.attributes._preset("caliper-companion", k, v)
        return sk


class CanvasInput(Base):
    _tag = "canvasInput"
    _writable = ("opacity", "transform", "isDisplayedThrough", "isFlippedHorizontal", "isFlippedVertical")

    def __init__(self, rec, image, plane):
        Base.__init__(self, rec)
        self._set("imageFilename", image)
        self._set("planarEntity", plane)
        self._set("opacity", 50)
        self._set("transform", Matrix2D())


class Canvas(Base):
    _tag = "canvas"
    _writable = ("name", "opacity", "isDisplayedThrough", "isFlippedHorizontal", "isFlippedVertical")

    def __init__(self, rec, owner, ci, name):
        Base.__init__(self, rec)
        self._owner = owner
        self._set("name", name)
        self._set("imageFilename", ci.imageFilename)
        self._set("planarEntity", ci.planarEntity)
        self._set("opacity", ci.opacity)
        self._set("transform", ci.transform.copy())
        self._set("attributes", Attributes(rec, self))
        self._set("timelineObject", None)
        self._set("isDeleted", False)

    def deleteMe(self):
        self._rec.record("canvas.deleteMe", self.name, write=True)
        if self.name in self._rec.delete_fails:
            return False
        self._owner._remove(self)
        self._set("isDeleted", True)
        return True


class Canvases(Base):
    _tag = "canvases"

    def __init__(self, rec, component):
        Base.__init__(self, rec)
        self._component = component
        self._items = []
        self._serial = 0

    def createInput(self, image_filename, planar_entity):
        self._rec.record("canvases.createInput", image_filename, planar_entity)
        if not isinstance(image_filename, str) or not isinstance(planar_entity, Plane):
            raise FakeError("canvases.createInput(imageFilename: str, planarEntity) — got ({!r}, {!r})".format(image_filename, planar_entity))
        return CanvasInput(self._rec, image_filename, planar_entity)

    def add(self, ci):
        self._rec.record("canvases.add", ci, write=True)
        if not isinstance(ci, CanvasInput):
            raise FakeError("canvases.add expects a CanvasInput")
        if not isinstance(ci.opacity, int) or not (0 <= ci.opacity <= 100):
            raise FakeError("opacity must be an int 0–100, got {!r}".format(ci.opacity))
        self._serial += 1
        cv = Canvas(self._rec, self, ci, "Canvas{}".format(self._serial))
        self._items.append(cv)
        cv._set("timelineObject", self._component._design.timeline._push(cv))
        return cv

    def itemByName(self, name):
        self._rec.record("canvases.itemByName", name)
        for c in self._items:
            if c.name == name:
                return c
        return None

    def item(self, i):
        return self._items[i]

    @property
    def count(self):
        return len(self._items)

    def _remove(self, cv):
        self._items.remove(cv)
        if cv.timelineObject is not None:
            self._component._design.timeline._remove(cv.timelineObject)

    def _preset(self, name, plane, image="old.png", transform=None, attrs=None):
        ci = CanvasInput(self._rec, image, plane)
        ci._set("transform", Matrix2D(transform) if transform else Matrix2D())
        cv = Canvas(self._rec, self, ci, name)
        self._items.append(cv)
        cv._set("timelineObject", self._component._design.timeline._push(cv))
        for k, v in (attrs or {}).items():
            cv.attributes._preset("caliper-companion", k, v)
        return cv


class Occurrences(object):
    def __init__(self):
        self.count = 0


class Component(Base):
    _tag = "component"

    def __init__(self, rec, design, name):
        Base.__init__(self, rec)
        self._design = design
        self._set("name", name)
        self._set("sketches", Sketches(rec, self))
        self._set("canvases", Canvases(rec, self))
        self._set("occurrences", Occurrences())
        self._set("xYConstructionPlane", Plane(rec, "xYConstructionPlane"))
        self._set("xZConstructionPlane", Plane(rec, "xZConstructionPlane"))
        self._set("yZConstructionPlane", Plane(rec, "yZConstructionPlane"))


class UserParameter(Base):
    _tag = "parameter"
    _writable = ("expression", "unit", "comment")

    def __init__(self, rec, owner, name, expression, unit, comment):
        Base.__init__(self, rec)
        self._owner = owner
        self._set("name", name)
        self._set("expression", expression)
        self._set("unit", unit)
        self._set("comment", comment)
        self._set("isDeleted", False)

    def deleteMe(self):
        self._rec.record("parameter.deleteMe", self.name, write=True)
        if self.name in self._rec.delete_fails:
            return False
        self._owner._items.remove(self)
        self._set("isDeleted", True)
        return True


class UserParameters(Base):
    _tag = "userParameters"

    def __init__(self, rec):
        Base.__init__(self, rec)
        self._items = []

    def itemByName(self, name):
        self._rec.record("userParameters.itemByName", name)
        for p in self._items:
            if p.name == name:
                return p
        return None

    def add(self, name, value_input, unit, comment):
        self._rec.record("userParameters.add", name, value_input, unit, comment, write=True)
        if not isinstance(value_input, ValueInput):
            raise FakeError("userParameters.add: value is not a ValueInput")
        if self.itemByName_silent(name) is not None:
            return None  # Fusion returns None on a duplicate name (cookbook ladder #3)
        p = UserParameter(self._rec, self, name, value_input.expression, unit, comment)
        self._items.append(p)
        return p

    def itemByName_silent(self, name):
        for p in self._items:
            if p.name == name:
                return p
        return None

    def item(self, i):
        return self._items[i]

    @property
    def count(self):
        return len(self._items)

    def _preset(self, name, expression, unit, comment):
        p = UserParameter(self._rec, self, name, expression, unit, comment)
        self._items.append(p)
        return p


class FusionUnitsManager(object):
    def __init__(self, unit):
        self.defaultLengthUnits = unit


class Design(Base):
    _tag = "design"
    _writable = ("isComputeDeferred",)

    def __init__(self, rec, name="Untitled", parametric=True, unit="mm"):
        Base.__init__(self, rec)
        self._set("designType", DesignTypes.ParametricDesignType if parametric else DesignTypes.DirectDesignType)
        self._set("parentDocument", Document(rec, name))
        self._set("userParameters", UserParameters(rec))
        self._set("timeline", Timeline(rec))
        self._set("fusionUnitsManager", FusionUnitsManager(unit))
        self._set("isComputeDeferred", False)
        root = Component(rec, self, "root")
        self._set("rootComponent", root)
        self._set("activeComponent", root)

    @staticmethod
    def cast(product):
        return product if isinstance(product, Design) else None

    def _activate_sub(self, name="bracket"):
        sub = Component(self._rec, self, name)
        self._set("activeComponent", sub)
        self.rootComponent.occurrences.count += 1
        return sub


# ---- install / helpers -------------------------------------------------------------------------------------------


def make_design(rec, **kw):
    return Design(rec, **kw)


_UNSET = object()


def install(rec=None, design=None, product=_UNSET):
    """Put fake `adsk`, `adsk.core`, `adsk.fusion` into sys.modules. Returns (rec, app).
    `product=None` models Fusion with no document open."""
    rec = rec or Recorder()
    if product is _UNSET:
        product = design if design is not None else make_design(rec)
    app = Application(rec, product)
    Application._instance = app

    core = types.ModuleType("adsk.core")
    core.Application = Application
    core.ValueInput = ValueInput
    core.Matrix2D = Matrix2D
    core.DocumentTypes = DocumentTypes
    core.DialogResults = DialogResults
    core.MessageBoxButtonTypes = MessageBoxButtonTypes
    core.MessageBoxIconTypes = MessageBoxIconTypes
    fusion = types.ModuleType("adsk.fusion")
    fusion.Design = Design
    fusion.DesignTypes = DesignTypes
    adsk = types.ModuleType("adsk")
    adsk.core = core
    adsk.fusion = fusion
    sys.modules["adsk"] = adsk
    sys.modules["adsk.core"] = core
    sys.modules["adsk.fusion"] = fusion
    return rec, app


def uninstall():
    for k in ("adsk", "adsk.core", "adsk.fusion"):
        sys.modules.pop(k, None)
    Application._instance = None
