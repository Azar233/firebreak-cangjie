package firebreak

import std.collection.ArrayList
import std.convert.*
import std.fs.{File, exists, remove}
import std.math.abs
import stdx.encoding.json.*
import stdx.encoding.base64.*
import sdl.*

let GRID_X: Int64=24
let GRID_Z: Int64=20
let CELL_COUNT: Int64=480
let LAND_NAMES=["空地","林地","道路","水域","建筑"]

// Baseline annotations and intervention mask are independent. Fuel is a relative index,
// not measured biomass; P1 deliberately contains no spread prediction.
class Project {
    var land=Array<Int64>(CELL_COUNT,repeat:0)
    var targets=Array<Int64>(CELL_COUNT,repeat:0)
    var forbidden=Array<Int64>(CELL_COUNT,repeat:0)
    var treatment=Array<Int64>(CELL_COUNT,repeat:0)
    var metersWide: Float64=120.0
    var aspect: Float64=1.2
    var budget: Float64=100000.0
    var clearingPrice: Float64=2.0
    var breakPrice: Float64=5.0
    var image=""
    var source="教学营地示例"
    var ignition: Int64 = -1
    var spreadProbability: Float64=0.65
    var burnSteps: Int64=2
    var seed: Int64=42
    init(demo!: Bool=true) {
        if (demo) {
            for (z in 0..GRID_Z) { for (x in 0..GRID_X) {
                land[z*GRID_X+x]=if (z==9 || z==10) { 2 } else { 1 }
            } }
            for (z in 3..7) { for (x in 16..20) { land[z*GRID_X+x]=4; targets[z*GRID_X+x]=1 } }
            for (z in 15..20) { for (x in 0..3) { forbidden[z*GRID_X+x]=1 } }
        }
    }
    func cellArea(): Float64 { metersWide*metersWide/aspect/Float64(CELL_COUNT) }
    func count(mask: Array<Int64>): Int64 { var n: Int64=0; for (v in mask) { if (v!=0) { n++ } }; return n }
    func cost(): Float64 {
        var sum=0.0
        for (v in treatment) { sum+=if (v==1) { clearingPrice } else if (v==2) { breakPrice } else { 0.0 } }
        return sum*cellArea()
    }
    func fuel(i: Int64,planned!: Bool=false): Float64 {
        if (planned && treatment[i]!=0) { return 0.0 }; return if (land[i]==1) { 1.0 } else { 0.0 }
    }
    func validate(): Unit {
        require(ignition>= -1 && ignition<CELL_COUNT && spreadProbability>=0.0 && spreadProbability<=1.0 && !spreadProbability.isNaN(),"非法起火点或传播概率")
        require(burnSteps>=1 && burnSteps<=8 && seed>=0 && seed<=2147483647,"燃烧步数须为 1 至 8，seed 须为 0 至 2147483647")
        require(aspect>=0.05 && aspect<=20.0 && !aspect.isNaN(),"底图宽高比超出 1:20 至 20:1")
        require(metersWide>=0.0 && metersWide<=100000.0 && !metersWide.isNaN(),"场地宽度须在 0 至 100000 米内")
        for (v in [budget,clearingPrice,breakPrice]) { require(!v.isNaN() && v>=0.0 && v<=1.0e9,"费用参数超出范围") }
        for (i in 0..CELL_COUNT) {
            require(land[i]>=0 && land[i]<=4 && targets[i]>=0 && targets[i]<=1 && forbidden[i]>=0 && forbidden[i]<=1 && treatment[i]>=0 && treatment[i]<=2,"非法格子数据")
            require(treatment[i]==0 || (land[i]==1 && targets[i]==0 && forbidden[i]==0),"处理带与地类、保护目标或禁区冲突")
        }
        require(count(treatment)==0 || metersWide>0.0,"未标定的场地不能保存收费处理方案")
        require(cost()<=budget+1.0e-7,"方案超过预算")
        require(image.size<=12000000 && source.size<=1024,"底图或来源信息过大")
    }
    func text(): String {
        let j=JsonObject()
        j.put("format",JsonString("firebreak")); j.put("version",JsonInt(2))
        j.put("ignitionCell",JsonInt(ignition)); j.put("spreadProbability",JsonString("${spreadProbability}"))
        j.put("spreadRuleVersion",JsonInt(1))
        j.put("burnSteps",JsonInt(burnSteps)); j.put("seed",JsonInt(seed))
        j.put("nx",JsonInt(GRID_X)); j.put("nz",JsonInt(GRID_Z))
        j.put("land",JsonString(maskText(land))); j.put("targets",JsonString(maskText(targets)))
        j.put("forbidden",JsonString(maskText(forbidden))); j.put("treatment",JsonString(maskText(treatment)))
        j.put("metersWide",JsonString("${metersWide}")); j.put("aspect",JsonString("${aspect}"))
        j.put("budget",JsonString("${budget}")); j.put("clearingPrice",JsonString("${clearingPrice}")); j.put("breakPrice",JsonString("${breakPrice}"))
        j.put("imageBase64",JsonString(image)); j.put("source",JsonString(source))
        return j.toJsonString()
    }
    func copy(): Project { readProjectText(text()) }
}
func maskText(mask: Array<Int64>): String { String.fromUtf8(Array<UInt8>(mask.size,{i => UInt8(48+mask[i])})) }
func parseMask(s: String): Array<Int64> {
    require(s.size==CELL_COUNT,"格子数量不匹配")
    return Array<Int64>(CELL_COUNT,{i => Int64(s[i])-48})
}
func readProjectText(text: String): Project {
    require(text.size<=13000000,"项目文件过大")
    let j=JsonValue.fromStr(text).asObject()
    let version=j["version"].asInt().getValue()
    require(j["format"].asString().getValue()=="firebreak" && (version==1 || version==2),"不支持的项目格式或版本")
    require(j["nx"].asInt().getValue()==GRID_X && j["nz"].asInt().getValue()==GRID_Z,"P1 支持 24 x 20 标注网格")
    let p=Project(demo:false)
    if (version==2) {
        require(j["spreadRuleVersion"].asInt().getValue()==1,"不支持的传播规则版本")
        p.ignition=j["ignitionCell"].asInt().getValue(); p.spreadProbability=Float64.parse(j["spreadProbability"].asString().getValue())
        p.burnSteps=j["burnSteps"].asInt().getValue(); p.seed=j["seed"].asInt().getValue()
    }
    p.land=parseMask(j["land"].asString().getValue()); p.targets=parseMask(j["targets"].asString().getValue())
    p.forbidden=parseMask(j["forbidden"].asString().getValue()); p.treatment=parseMask(j["treatment"].asString().getValue())
    p.metersWide=Float64.parse(j["metersWide"].asString().getValue()); p.aspect=Float64.parse(j["aspect"].asString().getValue())
    p.budget=Float64.parse(j["budget"].asString().getValue()); p.clearingPrice=Float64.parse(j["clearingPrice"].asString().getValue())
    p.breakPrice=Float64.parse(j["breakPrice"].asString().getValue()); p.image=j["imageBase64"].asString().getValue(); p.source=j["source"].asString().getValue()
    p.validate(); return p
}
func decodeReference(p: Project): ?Surface {
    if (p.image.isEmpty()) { return None }
    let bytes=fromBase64String(p.image).getOrThrow()
    require(bytes.size<=8000000,"底图上限 8 MB")
    let s=Surface.loadBytes(bytes,options:ImageLoadOptions(maxPixels:16000000))
    let ratio=Float64(s.size().w)/Float64(s.size().h)
    if (abs(ratio-p.aspect)>1.0e-6) { s.close(); throw Exception("底图尺寸与项目不符") }
    return Some(s)
}

// Same-volume Windows rename replaces the directory entry without first deleting the old file.
// Kernel32 is a platform API; all project logic and serialization stay in Cangjie.
foreign { func MoveFileExW(from: CPointer<UInt16>,to: CPointer<UInt16>,flags: UInt32): Int32 }
func widePath(s: String): Array<UInt16> {
    require(!s.isEmpty() && !s.contains("\u{0}"),"非法文件路径")
    let a=ArrayList<UInt16>()
    for (r in s.runes()) {
        let n=UInt32(r)
        if (n<65536) { a.add(UInt16(n)) } else { a.add(UInt16(55296+(n-65536)/1024)); a.add(UInt16(56320+(n-65536)%1024)) }
    }
    a.add(0); return a.toArray()
}
func safeWrite(path: String,text: String): Unit {
    let temp=path+".writing"
    require(!exists(temp),"保存临时文件已存在，请先检查："+temp)
    File.writeTo(temp,text.toArray())
    try {
        let src=widePath(temp); let dst=widePath(path)
        let a=unsafe { acquireArrayRawData(src) }; let b=unsafe { acquireArrayRawData(dst) }
        let ok=unsafe { MoveFileExW(a.pointer,b.pointer,UInt32(9)) }
        unsafe { releaseArrayRawData(b); releaseArrayRawData(a) }
        require(ok!=0,"无法安全替换目标文件；原文件保留")
    } finally { if (exists(temp)) { remove(temp) } }
}

class Workbench {
    var project=Project()
    let undo=ArrayList<String>()
    let redo=ArrayList<String>()
    var saved=""
    var path=""
    var revision: Int64=0
    var unsaved=false
    init() { saved=project.text() }
    func dirty(): Bool { unsaved }
    func trimHistory(): Unit {
        var size: Int64=0
        for (s in undo) { size+=s.size }; for (s in redo) { size+=s.size }
        while (undo.size>1 && (size>24000000 || undo.size>50)) { size-=undo[0].size; undo.remove(at:0) }
    }
    func commit(next: Project): Bool {
        next.validate()
        let before=project.text(); if (before==next.text()) { return false }
        undo.add(before); redo.clear(); trimHistory(); project=next; unsaved=next.text()!=saved; revision++; return true
    }
    func history(back: Bool): Bool {
        let from=if (back) { undo } else { redo }; let to=if (back) { redo } else { undo }
        if (from.isEmpty()) { return false }
        let next=readProjectText(from[from.size-1]); to.add(project.text()); from.remove(at:from.size-1); project=next; unsaved=next.text()!=saved; trimHistory(); revision++; return true
    }
    func apply(cells: Array<Int64>,tool: Int64,erase: Bool): Bool {
        let p=project.copy()
        for (i in cells) {
            require(i>=0 && i<CELL_COUNT,"选区超出场地")
            if (tool>=1 && tool<=4) { p.land[i]=if (erase) { 0 } else { tool }; p.treatment[i]=0 }
            else if (tool==5 || tool==6) {
                require(erase || (p.forbidden[i]==0 && p.targets[i]==0),"选区含禁区或保护目标，整笔操作未应用")
                if (erase) { p.treatment[i]=0 } else if (p.land[i]==1) { p.treatment[i]=tool-4 }
            } else if (tool==7) { p.targets[i]=if (erase) { 0 } else { 1 }; p.treatment[i]=0 }
            else if (tool==8) { p.forbidden[i]=if (erase) { 0 } else { 1 }; p.treatment[i]=0 }
        }
        return commit(p)
    }
    func save(file: String): Unit {
        project.validate(); let text=project.text(); safeWrite(file,text); path=file; saved=text; unsaved=false
    }
    func load(file: String): Unit {
        let next=readProjectText(String.fromUtf8(File.readFrom(file)))
        if (let Some(s) <- decodeReference(next)) { s.close() }
        acceptLoaded(next,file)
    }
    func acceptLoaded(next: Project,file: String): Unit {
        project=next; saved=next.text(); path=file; unsaved=false; undo.clear(); redo.clear(); revision++
    }
}

