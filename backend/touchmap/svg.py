"""Bounded SVG profile. Curves are flattened before rendering and interaction."""
from __future__ import annotations
import math
import re
import uuid
import base64
import io
from pathlib import Path
from defusedxml import ElementTree as ET
from defusedxml.common import DefusedXmlException
from svgpathtools import parse_path, CubicBezier, QuadraticBezier, Line, Arc
from shapely.geometry import Polygon as SPolygon, LineString, Point as SPoint
from shapely.ops import unary_union, polygonize
from shapely.affinity import affine_transform
from .errors import TouchMapError
from .models import Diagram, Source, Region, Review, Evidence, Point, Polygon
from .packages import sha256

NUMBER=r"[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?"
MATRIX=(1.,0.,0.,1.,0.,0.)
TOLERANCE=0.0625  # 0.5 source-screen pixels at supported 8x zoom.
MAX_POINTS=100000

def render_preview(data: bytes) -> bytes:
    """Render checked SVG source, retaining its text/markers on native runtimes."""
    root=inspect_svg(data)
    view=numbers(root.get("viewBox",""))
    width=scalar(root.get("width"),view[2] if len(view)==4 else 0)
    height=scalar(root.get("height"),view[3] if len(view)==4 else 0)
    if width<=0 or height<=0 or math.ceil(width)*math.ceil(height)>20000000:
        raise TouchMapError("preview_dimensions","SVG preview exceeds 20 megapixels or has invalid dimensions",413)
    import resvg_py
    from PIL import Image
    # Use parsed/serialized XML to support declared XML encodings and ensure the
    # renderer sees exactly the safe, entity-free tree that was inspected.
    xml=ET.tostring(root,encoding="unicode")
    try:
        result=resvg_py.svg_to_bytes(svg_string=xml,width=math.ceil(width),height=math.ceil(height),skip_system_fonts=True,font_files=[str(Path(__file__).parent/"assets/DejaVuSans.ttf")],font_family="DejaVu Sans",sans_serif_family="DejaVu Sans",serif_family="DejaVu Sans",monospace_family="DejaVu Sans",cursive_family="DejaVu Sans",fantasy_family="DejaVu Sans")
        with Image.open(io.BytesIO(result)) as im:
            if im.size!=(math.ceil(width),math.ceil(height)):raise ValueError("Preview dimensions differ")
    except Exception:
        raise TouchMapError("preview_render","SVG rendering failed; supply an author-checked raster source") from None
    if len(result)>10*1024*1024:raise TouchMapError("preview_limit","SVG preview exceeds 10 MiB",413)
    return result

def tag(node):
    return node.tag.split("}")[-1]

def numbers(text):
    found=re.findall(NUMBER,text or "")
    remainder=re.sub(NUMBER,"",text or "")
    if remainder.strip(" ,\t\r\n"):
        raise TouchMapError("svg_number","Unsupported SVG numeric syntax")
    values=list(map(float,found))
    if any(not math.isfinite(v) or abs(v)>1e9 for v in values):
        raise TouchMapError("svg_number","Non-finite or unbounded coordinate")
    return values

def scalar(text,default=0.):
    if text is None:
        return default
    values=numbers(text.removesuffix("px"))
    if len(values)!=1:
        raise TouchMapError("svg_unit","Only explicit unitless or px SVG lengths are supported")
    return values[0]

def multiply(a,b):
    return (a[0]*b[0]+a[2]*b[1],a[1]*b[0]+a[3]*b[1],a[0]*b[2]+a[2]*b[3],a[1]*b[2]+a[3]*b[3],a[0]*b[4]+a[2]*b[5]+a[4],a[1]*b[4]+a[3]*b[5]+a[5])

def transform(text):
    result=MATRIX
    matches=list(re.finditer(r"([A-Za-z]+)\s*\(([^)]*)\)",text or ""))
    if re.sub(r"([A-Za-z]+)\s*\(([^)]*)\)","",text or "").strip(" ,\t\n"):
        raise TouchMapError("svg_transform","Malformed transform")
    for match in matches:
        name=match[1]; v=numbers(match[2])
        if name=="matrix" and len(v)==6: m=tuple(v)
        elif name=="translate" and len(v) in (1,2): m=(1,0,0,1,v[0],v[1] if len(v)==2 else 0)
        elif name=="scale" and len(v) in (1,2): m=(v[0],0,0,v[-1],0,0)
        elif name=="rotate" and len(v) in (1,3):
            c=math.cos(math.radians(v[0])); s=math.sin(math.radians(v[0])); m=(c,s,-s,c,0,0)
            if len(v)==3: m=multiply(multiply((1,0,0,1,v[1],v[2]),m),(1,0,0,1,-v[1],-v[2]))
        elif name in ("skewX","skewY") and len(v)==1:
            q=math.tan(math.radians(v[0])); m=(1,0,q,1,0,0) if name=="skewX" else (1,q,0,1,0,0)
        else: raise TouchMapError("svg_transform","Unsupported affine transform")
        result=multiply(result,m)
    if abs(result[0]*result[3]-result[1]*result[2])<1e-12:
        raise TouchMapError("svg_transform","Singular transforms are unsupported")
    return result

def apply(matrix,p):
    x,y=(p.real,p.imag) if isinstance(p,complex) else p
    return (matrix[0]*x+matrix[2]*y+matrix[4],matrix[1]*x+matrix[3]*y+matrix[5])

def inspect_svg(data):
    if len(data)>10*1024*1024:
        raise TouchMapError("svg_limit","SVG exceeds 10 MiB",413)
    try:
        root=ET.fromstring(data,forbid_dtd=True,forbid_entities=True,forbid_external=True)
    except (DefusedXmlException,ET.ParseError,ValueError):
        raise TouchMapError("unsafe_svg","Malformed SVG or forbidden DTD/entities") from None
    if tag(root)!="svg": raise TouchMapError("svg_root","Expected SVG root")
    pending=[(root,0)]; count=0
    while pending:
        node,depth=pending.pop(); count+=1
        if count>10000 or depth>64: raise TouchMapError("svg_complexity","SVG tree exceeds limits",413)
        if tag(node) in {"script","foreignObject","image","use","iframe","audio","video","animate","set","animateTransform"}:
            raise TouchMapError("active_svg",f"Unsupported active or external SVG element: {tag(node)}")
        for key,value in node.attrib.items():
            local=key.split("}")[-1]
            if "\\" in value or "/*" in value:
                raise TouchMapError("external_svg","CSS escapes and comments are outside the safe SVG profile")
            if local.startswith("on") or local in {"href","src"}:
                raise TouchMapError("external_svg","External resources, event handlers and embedded data are forbidden")
            for match in re.finditer(r"url\s*\(([^)]*)\)",value,re.I):
                reference=match[1].strip()
                if len(reference)>=2 and reference[0] in "\"'" and reference[-1]==reference[0]:reference=reference[1:-1]
                if not re.fullmatch(r"#[A-Za-z_][\w.-]*",reference):
                    raise TouchMapError("external_svg","Only local SVG fragment URLs are supported")
        if tag(node)=="style" and re.search(r"@import|url\(|expression\(|javascript:|\\|/\*","".join(node.itertext()),re.I):
            raise TouchMapError("external_svg","Stylesheets cannot reference external or executable resources")
        pending.extend((child,depth+1) for child in node)
    return root

def distance(p,a,b):
    if a==b:return abs(p-a)
    return abs((p-a).real*(b-a).imag-(p-a).imag*(b-a).real)/abs(b-a)

def flatten(segment,matrix,tolerance,output,depth=0):
    """Bezier convex-hull error bound; arc bound derives from transformed ellipse radius."""
    if len(output)>=MAX_POINTS: raise TouchMapError("geometry_limit","Curve tolerance cannot be preserved within point limit",413)
    if isinstance(segment,Line): output.append(apply(matrix,segment.end));return
    if isinstance(segment,Arc):
        radius=max(abs(segment.radius.real),abs(segment.radius.imag))
        norm=math.sqrt(sum(x*x for x in matrix[:4]))
        transformed=radius*norm
        step=math.pi/2 if transformed<=tolerance else 2*math.acos(max(-1.,min(1.,1-tolerance/transformed)))
        count=max(1,math.ceil(abs(math.radians(segment.delta))/max(step,1e-9)))
        if len(output)+count>MAX_POINTS:raise TouchMapError("geometry_limit","Arc exceeds tolerance complexity limit",413)
        output.extend(apply(matrix,segment.point(i/count)) for i in range(1,count+1));return
    controls=[segment.control] if isinstance(segment,QuadraticBezier) else [segment.control1,segment.control2]
    start=complex(*apply(matrix,segment.start));end=complex(*apply(matrix,segment.end))
    error=max(distance(complex(*apply(matrix,p)),start,end) for p in controls)
    # Also constrain the control polygon to avoid collinear backtracking flattening.
    length=sum(abs(b-a) for a,b in zip([start,*[complex(*apply(matrix,p)) for p in controls]],[*[complex(*apply(matrix,p)) for p in controls],end]))
    if error<=tolerance and length-abs(end-start)<=tolerance:
        output.append(apply(matrix,segment.end));return
    if depth>=24:raise TouchMapError("geometry_limit","Curve failed bounded adaptive subdivision",413)
    left,right=segment.split(0.5)
    flatten(left,matrix,tolerance,output,depth+1);flatten(right,matrix,tolerance,output,depth+1)

def winding(point,ring):
    x,y=point; count=0
    for a,b in zip(ring,ring[1:]+ring[:1]):
        cross=(b[0]-a[0])*(y-a[1])-(x-a[0])*(b[1]-a[1])
        if a[1]<=y<b[1] and cross>0:count+=1
        elif b[1]<=y<a[1] and cross<0:count-=1
    return count

def fill_contours(contours,rule):
    rings=[r for r in contours if len(set(r))>=3]
    if not rings:return []
    boundaries=unary_union([LineString(r+[r[0]] if r[-1]!=r[0] else r) for r in rings])
    selected=[]
    for face in polygonize(boundaries):
        p=face.representative_point();w=sum(winding((p.x,p.y),r) for r in rings)
        if (w!=0 if rule=="nonzero" else w%2!=0):selected.append(face)
    merged=unary_union(selected)
    return list(merged.geoms) if hasattr(merged,"geoms") else [merged] if not merged.is_empty else []

def convert_svg(data:bytes,revision:int=1,language:str="en",title:str="Imported diagram") -> dict:
    root=inspect_svg(data)
    view=numbers(root.get("viewBox",""))
    width=scalar(root.get("width"),view[2] if len(view)==4 else 0)
    height=scalar(root.get("height"),view[3] if len(view)==4 else 0)
    if not view:view=[0,0,width,height]
    if len(view)!=4 or width<=0 or height<=0 or view[2]<=0 or view[3]<=0:raise TouchMapError("svg_dimensions","SVG needs positive width/height or viewBox")
    source=Source(id="source",sha256=sha256(data),width=width,height=height,path="source/source.svg",attribution="Author must confirm source attribution",license="Unspecified",viewBox=view)
    sx,sy=width/view[2],height/view[3]
    aspect=root.get("preserveAspectRatio","xMidYMid meet").strip().split()
    if aspect and aspect[0]=="defer":aspect=aspect[1:]
    if aspect==["none"]:
        viewport=(sx,0,0,sy,-view[0]*sx,-view[1]*sy)
    else:
        alignment=aspect[0] if aspect else "xMidYMid"
        mode=aspect[1] if len(aspect)>1 else "meet"
        if not re.fullmatch(r"x(Min|Mid|Max)Y(Min|Mid|Max)",alignment) or mode not in ("meet","slice"):
            raise TouchMapError("svg_viewport","Unsupported preserveAspectRatio")
        scale=min(sx,sy) if mode=="meet" else max(sx,sy)
        fx={"Min":0,"Mid":.5,"Max":1}[alignment[1:4]];fy={"Min":0,"Mid":.5,"Max":1}[alignment[5:8]]
        viewport=(scale,0,0,scale,(width-view[2]*scale)*fx-view[0]*scale,(height-view[3]*scale)*fy-view[1]*scale)
    unsupported=[];unresolved=[];regions=[];mapping=[];texts=[]
    supported={"fill","fill-rule","stroke","stroke-width","stroke-linecap","stroke-linejoin","opacity","fill-opacity","stroke-opacity","display","visibility","marker-start","marker-end","color","font-size","font-family","font-weight","text-anchor"}
    def walk(node,parent_matrix,parent_style,in_defs=False):
        kind=tag(node);node_id=node.get("id",f"element-{len(mapping)+1}")
        matrix=multiply(parent_matrix,transform(node.get("transform","")))
        style=dict(parent_style)
        for k in supported:
            if k in node.attrib:style[k]=node.attrib[k]
        for declaration in node.get("style","").split(";"):
            if not declaration.strip():continue
            key,sep,value=declaration.partition(":")
            if not sep or key.strip() not in supported:unsupported.append(f"{node_id}: unsupported style {key.strip()}")
            else:style[key.strip()]=value.strip()
        for special in ("class","filter","mask","clip-path","stroke-dasharray","vector-effect"):
            if special in node.attrib:unsupported.append(f"{node_id}: unsupported {special}")
        if kind in ("style","filter","mask","clipPath","pattern","linearGradient","radialGradient","symbol"):
            unsupported.append(f"{node_id}: unsupported {kind}");return
        if kind=="svg" and node is not root:
            unsupported.append(f"{node_id}: nested SVG viewport");return
        if style.get("display")=="none" or style.get("visibility")=="hidden" or style.get("opacity")=="0":return
        if kind=="text":
            texts.append({"sourceId":node_id,"text":"".join(node.itertext()).strip(),"position":apply(matrix,(scalar(node.get("x")),scalar(node.get("y"))))})
        if kind in ("svg","g","defs","marker","a","text","tspan","title","desc","metadata"):
            if kind=="marker":
                unresolved.append(f"{node_id}: marker geometry retained as source evidence; attach arrow endpoints and confirm direction manually")
            for child in node:walk(child,matrix,style,in_defs or kind in ("defs","marker"))
            return
        if in_defs:return
        contours=[];is_line=False
        if kind=="rect":
            x=scalar(node.get("x"));y=scalar(node.get("y"));w=scalar(node.get("width"));h=scalar(node.get("height"))
            if w<=0 or h<=0:return
            rx=min(scalar(node.get("rx"),scalar(node.get("ry"))),w/2);ry=min(scalar(node.get("ry"),rx),h/2)
            if rx>0 and ry>0:
                d=f"M{x+rx},{y} H{x+w-rx} A{rx},{ry} 0 0 1 {x+w},{y+ry} V{y+h-ry} A{rx},{ry} 0 0 1 {x+w-rx},{y+h} H{x+rx} A{rx},{ry} 0 0 1 {x},{y+h-ry} V{y+ry} A{rx},{ry} 0 0 1 {x+rx},{y} Z"
                path=parse_path(d); pts=[apply(matrix,path[0].start)]
                for seg in path:flatten(seg,matrix,TOLERANCE,pts)
                contours=[pts]
            else:contours=[[apply(matrix,p) for p in [(x,y),(x+w,y),(x+w,y+h),(x,y+h)]]]
        elif kind in ("circle","ellipse"):
            cx=scalar(node.get("cx"));cy=scalar(node.get("cy"));rx=scalar(node.get("r")) if kind=="circle" else scalar(node.get("rx"));ry=rx if kind=="circle" else scalar(node.get("ry"))
            if rx<=0 or ry<=0:return
            path=parse_path(f"M{cx-rx},{cy} A{rx},{ry} 0 1 0 {cx+rx},{cy} A{rx},{ry} 0 1 0 {cx-rx},{cy} Z")
            pts=[apply(matrix,path[0].start)]
            for seg in path:flatten(seg,matrix,TOLERANCE,pts)
            contours=[pts]
        elif kind in ("polygon","polyline"):
            v=numbers(node.get("points",""))
            if len(v)%2:raise TouchMapError("svg_points","Odd polygon coordinate count")
            contours=[[apply(matrix,p) for p in zip(v[::2],v[1::2])]];is_line=kind=="polyline"
        elif kind=="line":
            contours=[[apply(matrix,(scalar(node.get("x1")),scalar(node.get("y1")))),apply(matrix,(scalar(node.get("x2")),scalar(node.get("y2"))))]];is_line=True
        elif kind=="path":
            try:
                path=parse_path(node.get("d",""))
                for subpath in path.continuous_subpaths():
                    pts=[apply(matrix,subpath[0].start)]
                    for seg in subpath:flatten(seg,matrix,TOLERANCE,pts)
                    contours.append(pts)
            except (ValueError,IndexError,AssertionError):raise TouchMapError("svg_path","Malformed SVG path") from None
            is_line=style.get("fill","black")=="none"
        else:
            unsupported.append(f"{node_id}: unsupported element {kind}");return
        if any("url(" in style.get(key,"") for key in ("fill","stroke")):unsupported.append(f"{node_id}: paint server unsupported")
        fill=style.get("fill","black")!="none" and not is_line and style.get("fill-opacity")!="0"
        has_stroke=style.get("stroke","none")!="none" and style.get("stroke-opacity")!="0"
        if not fill and not has_stroke:return
        rule=style.get("fill-rule","nonzero")
        if rule not in ("nonzero","evenodd"):raise TouchMapError("svg_fill","Unsupported fill rule")
        polygons=fill_contours(contours,rule) if fill else []
        if not polygons and not contours:return
        label=node.get("aria-label") or next((c.text for c in node if tag(c)=="title" and c.text),None) or node.get("data-label") or node_id
        if label==node_id:unresolved.append(f"{node_id}: confirm label assignment")
        if style.get("marker-start") or style.get("marker-end"):unresolved.append(f"{node_id}: arrow marker requires reviewed endpoint assignment and direction")
        raw_width=scalar(style.get("stroke-width"),1)
        width=raw_width*math.sqrt(abs(matrix[0]*matrix[3]-matrix[1]*matrix[2]))
        nonuniform=abs(matrix[0]*matrix[2]+matrix[1]*matrix[3])>1e-6 or abs(math.hypot(matrix[0],matrix[1])-math.hypot(matrix[2],matrix[3]))>1e-6
        if has_stroke and raw_width>0 and (polygons or nonuniform):
            # Buffer in pre-transform coordinates, then apply the same affine transform.
            det=matrix[0]*matrix[3]-matrix[1]*matrix[2]
            inverse=(matrix[3]/det,-matrix[1]/det,-matrix[2]/det,matrix[0]/det,(matrix[2]*matrix[5]-matrix[3]*matrix[4])/det,(matrix[1]*matrix[4]-matrix[0]*matrix[5])/det)
            radius=raw_width/2;norm=math.sqrt(sum(x*x for x in matrix[:4]))
            step=math.pi/2 if radius*norm<=TOLERANCE else 2*math.acos(max(-1.,min(1.,1-TOLERANCE/(radius*norm))))
            quad=max(1,math.ceil((math.pi/2)/max(step,1e-9)))
            if quad>25000:raise TouchMapError("geometry_limit","Stroke curve exceeds precision budget",413)
            caps={"butt":"flat","round":"round","square":"square"}
            joins={"miter":"mitre","round":"round","bevel":"bevel"}
            outlines=[]
            for contour in contours:
                if len(contour)<2:continue
                if polygons and contour[-1]!=contour[0]:contour=contour+[contour[0]]
                original=[apply(inverse,p) for p in contour]
                buffered=LineString(original).buffer(radius,quad_segs=quad,cap_style=caps.get(style.get("stroke-linecap","butt"),"flat"),join_style=joins.get(style.get("stroke-linejoin","miter"),"mitre"))
                outlines.append(affine_transform(buffered,[matrix[0],matrix[2],matrix[1],matrix[3],matrix[4],matrix[5]]))
            merged=unary_union([*polygons,*outlines])
            polygons=list(merged.geoms) if hasattr(merged,"geoms") else [merged] if not merged.is_empty else []
        # Disconnected unfilled subpaths stay separate regions, preserving reachability.
        parts=[([],c) for c in contours if len(c)>=2] if not polygons else [(polygons,[])]
        for index,(polys,line) in enumerate(parts):
            rid=re.sub(r"[^A-Za-z0-9_.-]","-",node_id)
            if not rid or not rid[0].isalnum():rid="region-"+rid
            rid=(rid[:100]+(f"-{index+1}" if len(parts)>1 else ""))
            if any(r.id==rid for r in regions):rid+=f"-{len(regions)+1}"
            review=Review(status="needs_review",revision=revision,issues=["Confirm geometry against source"])
            regions.append(Region(id=rid,label=label,description=next((c.text or "" for c in node if tag(c)=="desc"),""),polygons=[Polygon(outer=[Point(x=x,y=y) for x,y in list(p.exterior.coords)[:-1]],holes=[[Point(x=x,y=y) for x,y in list(h.coords)[:-1]] for h in p.interiors]) for p in polys],line=[Point(x=x,y=y) for x,y in line],lineWidth=max(width,.001),zIndex=len(regions),readingOrder=len(regions),evidence=[Evidence(sourceId=source.id,reference=f"SVG #{node_id}",origin="source-derived")],geometryReview=review,meaningReview=Review(status="needs_review",revision=revision,issues=["Confirm label, reading order and semantics"])))
            mapping.append({"sourceId":node_id,"regionId":rid})
            if len(regions)>500:raise TouchMapError("region_limit","SVG exceeds 500 regions; split material",413)
    walk(root,viewport,{})
    preview=render_preview(data)
    source=Source.model_validate({**source.model_dump(),"previewPath":"source/preview.png","previewSha256":sha256(preview)})
    diagram=Diagram(packageId="material-"+uuid.uuid4().hex[:12],revision=revision,title=title,language=language,source=source,regions=regions,description="")
    return {"diagram":diagram.model_dump(),"previewBase64":base64.b64encode(preview).decode(),"report":{"unsupported":sorted(set(unsupported)),"unresolved":sorted(set(unresolved)),"sourceMapping":mapping,"textMetadata":texts,"toleranceSourceUnits":TOLERANCE,"maximumZoom":8,"previewRenderer":"resvg_py 0.5.0","previewFontPolicy":"Bundled DejaVu Sans substitutes font families reproducibly; author checks source layout and text before publication"}}
