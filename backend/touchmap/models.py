"""Public wire models. Hashes establish integrity, never author trust."""
from __future__ import annotations
from typing import Annotated, Literal
import math
from pydantic import BaseModel, ConfigDict, Field, model_validator
from shapely.geometry import Polygon as SPolygon

Id = Annotated[str, Field(min_length=1, max_length=128, pattern=r"^[A-Za-z0-9][A-Za-z0-9_.-]*$")]
Text = Annotated[str, Field(max_length=10000)]
Hash = Annotated[str, Field(pattern=r"^[a-f0-9]{64}$")]
Number = Annotated[float, Field(allow_inf_nan=False)]
Language = Annotated[str, Field(min_length=2,max_length=35,pattern=r"^[a-zA-Z]{2,3}(?:-[a-zA-Z0-9]{2,8})*$")]

class Model(BaseModel):
    model_config = ConfigDict(extra="forbid", validate_assignment=True, str_max_length=10000, strict=True)

class Point(Model):
    x: Number = Field(ge=-1000000,le=1000000)
    y: Number = Field(ge=-1000000,le=1000000)

class Polygon(Model):
    outer: list[Point] = Field(min_length=3, max_length=100000)
    holes: list[list[Point]] = Field(default_factory=list, max_length=1000)

    @model_validator(mode="after")
    def valid(self):
        for ring in [self.outer, *self.holes]:
            coordinates=[(p.x,p.y) for p in ring]
            if coordinates and coordinates[0]==coordinates[-1]:coordinates=coordinates[:-1]
            if len(coordinates)<3 or len(set(coordinates))!=len(coordinates):
                raise ValueError("Ring requires at least three distinct vertices")
        polygon=SPolygon([(p.x,p.y) for p in self.outer], [[(p.x,p.y) for p in h] for h in self.holes])
        if not polygon.is_valid or polygon.area<=0:
            raise ValueError("Invalid polygon topology")
        rings=[polygon.exterior,*polygon.interiors]
        if any(rings[i].intersects(rings[j]) for i in range(len(rings)) for j in range(i)):
            raise ValueError("Polygon rings must not touch")
        return self

class Evidence(Model):
    sourceId: Id
    reference: Text
    origin: Literal["source-derived", "human-authored", "AI-proposed"]

class Review(Model):
    status: Literal["draft", "needs_review", "reviewed"] = "draft"
    revision: int = Field(ge=1)
    reviewer: Text = ""
    issues: list[Text] = Field(default_factory=list, max_length=1000)

    @model_validator(mode="after")
    def declaration(self):
        if self.status == "reviewed" and (not self.reviewer.strip() or self.issues):
            raise ValueError("Reviewed content requires reviewer and no unresolved issues")
        return self

class Source(Model):
    id: Id
    sha256: Hash
    width: Number = Field(gt=0, le=100000)
    height: Number = Field(gt=0, le=100000)
    path: str = Field(max_length=256)
    attribution: Text
    license: Text
    viewBox: list[Number] = Field(min_length=4, max_length=4)
    previewPath: str = Field(default="",max_length=256)
    previewSha256: str = Field(default="",pattern=r"^(?:|[a-f0-9]{64})$")

    @model_validator(mode="after")
    def dimensions(self):
        if self.viewBox[2] <= 0 or self.viewBox[3] <= 0:
            raise ValueError("Invalid viewBox")
        if bool(self.previewPath)!=bool(self.previewSha256) or self.previewPath and self.previewPath==self.path:
            raise ValueError("Preview path and hash must be supplied together and separate from source")
        return self

class Region(Model):
    id: Id
    label: Text
    description: Text = ""
    polygons: list[Polygon] = Field(default_factory=list, max_length=10000)
    line: list[Point] = Field(default_factory=list, max_length=100000)
    lineWidth: Number = Field(default=1, ge=0, le=100000)
    zIndex: int = 0
    readingOrder: int = Field(default=0, ge=0)
    evidence: list[Evidence] = Field(default_factory=list, max_length=1000)
    geometryReview: Review
    meaningReview: Review

    @model_validator(mode="after")
    def geometry(self):
        if not self.polygons and len(self.line) < 2:
            raise ValueError("Region needs polygons or at least two line points")
        if self.line and len(self.line) < 2:
            raise ValueError("Line needs two points")
        if self.line and self.lineWidth <= 0:
            raise ValueError("Line width must be positive")
        return self

class Relation(Model):
    id: Id
    fromId: Id
    toId: Id
    label: Text
    type: str = Field(max_length=128)
    direction: Literal["forward", "both", "unknown"]
    path: list[Point] | None = Field(default=None, max_length=100000)
    evidence: list[Evidence] = Field(default_factory=list, max_length=1000)
    review: Review

    @model_validator(mode="after")
    def path_length(self):
        if self.path is not None and len(self.path) < 2:
            raise ValueError("Known relation path requires two points")
        return self

class Tick(Model):
    value: Number
    label: Text
class Axis(Model):
    label: Text
    unit: Text
    scale: Literal["linear", "log", "category"]
    domain: list[Number] = Field(max_length=1000)
    ticks: list[Tick] = Field(max_length=1000)

    @model_validator(mode="after")
    def scale_valid(self):
        if self.scale != "category" and (len(self.domain) != 2 or self.domain[0] >= self.domain[1]):
            raise ValueError("Numeric axis requires increasing domain")
        if self.scale == "log" and (self.domain[0] <= 0 or any(t.value <= 0 for t in self.ticks)):
            raise ValueError("Logarithmic scale requires positive numbers")
        return self

class ChartValue(Model):
    id: Id
    regionId: Id
    x: Text
    value: Number | None
    precision: int = Field(ge=0, le=10)
    evidence: list[Evidence] = Field(max_length=1000)
class Series(Model):
    id: Id
    label: Text
    values: list[ChartValue] = Field(max_length=10000)
class Chart(Model):
    id: Id
    title: Text
    kind: Literal["bar", "line"]
    xAxis: Axis
    yAxis: Axis
    series: list[Series] = Field(max_length=1000)
    evidence: list[Evidence] = Field(max_length=1000)
    review: Review
class AnswerOption(Model):
    id: Id
    label: Text
class Question(Model):
    id: Id
    prompt: Text
    type: Literal["adjacency", "direction", "sequence", "comparison", "value"]
    factIds: list[Id] = Field(min_length=1, max_length=1000)
    options: list[AnswerOption] = Field(min_length=2, max_length=100)
    acceptedAnswers: list[Id] = Field(min_length=1, max_length=100)
    hint: Text = ""
    explanation: Text
    requiredRevision: int = Field(ge=1)
    review: Review

    @model_validator(mode="after")
    def answers(self):
        ids = [o.id for o in self.options]
        if len(set(ids)) != len(ids) or len(set(self.acceptedAnswers)) != len(self.acceptedAnswers) or not set(self.acceptedAnswers).issubset(ids):
            raise ValueError("Question options and accepted answer IDs must be consistent")
        return self

class Audio(Model):
    id: Id
    targetId: Id
    kind: Literal["label", "description", "question", "overview"]
    path: str = Field(max_length=256)
    textHash: Hash
    language: Language
    provider: Text
    voice: Text
    sha256: Hash
    durationMs: int = Field(gt=0, le=3600000)

class Diagram(Model):
    schemaVersion: Literal[1] = 1
    packageId: Id
    revision: int = Field(ge=1)
    title: Text
    language: Language
    source: Source
    regions: list[Region] = Field(max_length=500)
    relations: list[Relation] = Field(default_factory=list, max_length=2000)
    charts: list[Chart] = Field(default_factory=list, max_length=100)
    questions: list[Question] = Field(default_factory=list, max_length=1000)
    audio: list[Audio] = Field(default_factory=list, max_length=2000)
    description: Text = ""

    @model_validator(mode="after")
    def graph(self):
        values = [v for c in self.charts for s in c.series for v in s.values]
        all_nodes = [*self.regions, *self.relations, *self.charts, *self.questions, *values, *[s for c in self.charts for s in c.series], *self.audio]
        ids = [x.id for x in all_nodes]
        if len(ids) != len(set(ids)) or self.packageId in ids:
            raise ValueError("Duplicate or reserved fact IDs")
        region_ids = {r.id for r in self.regions}
        if any(r.fromId not in region_ids or r.toId not in region_ids for r in self.relations):
            raise ValueError("Dangling relation endpoint")
        if any(v.regionId not in region_ids for v in values):
            raise ValueError("Dangling chart region")
        facts = {x.id for x in [*self.regions, *self.relations, *self.charts, *values]}
        if any(q.review.status == "reviewed" and not set(q.factIds).issubset(facts) for q in self.questions):
            raise ValueError("Dangling question fact")
        region_ids={r.id for r in self.regions};relation_ids={r.id for r in self.relations};question_ids={q.id for q in self.questions}
        for a in self.audio:
            targets={"overview":{self.packageId},"question":question_ids,"description":region_ids,"label":region_ids|relation_ids}
            if a.targetId not in targets[a.kind]:raise ValueError("Invalid audio target or kind")
        if len({(a.targetId,a.kind,a.language) for a in self.audio})!=len(self.audio):raise ValueError("Duplicate audio target")
        if len({a.id for a in self.audio}) != len(self.audio):
            raise ValueError("Duplicate audio IDs")
        count = 0
        for r in self.regions:
            count += len(r.line) + sum(len(p.outer) + sum(map(len,p.holes)) for p in r.polygons)
        count += sum(len(r.path or []) for r in self.relations)
        if count > 100000:
            raise ValueError("Geometry exceeds 100000 points; split or simplify material")
        for x in [*self.regions, *self.relations, *self.charts, *values]:
            if any(e.sourceId != self.source.id for e in x.evidence):
                raise ValueError("Evidence refers to unknown source")
        return self

class Asset(Model):
    path: str = Field(max_length=256)
    sha256: Hash
    bytes: int = Field(ge=0, le=50*1024*1024)
    mediaType: str = Field(max_length=128)
class Author(Model):
    name: Text
    declaration: Text
class Manifest(Model):
    schemaVersion: Literal[1] = 1
    packageId: Id
    revision: int = Field(ge=1)
    title: Text
    language: Language
    author: Author
    license: Text
    assets: list[Asset] = Field(max_length=999)
