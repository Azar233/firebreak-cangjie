package firebreak

import sdl.*
import std.fs.{File,exists}
import std.collection.{HashMap,ArrayList}

func clusterColor(label: Int64): Color {
    match(label%6) {
        case 0=>Color.rgb(134,216,104); case 1=>Color.rgb(92,173,222); case 2=>Color.rgb(214,151,224)
        case 3=>Color.rgb(232,194,96); case 4=>Color.rgb(102,213,192); case _=>Color.rgb(228,133,136)
    }
}

// Explicit P0 textures. The build script copies only these families and referenced font pages.
let BLOCK_PATHS=["grass_block_top","grass_block_side","dirt","oak_log","oak_log_top","oak_leaves","stone","oak_planks","bricks","dirt_path_top"]
let TOOL_PATHS=["map","compass_16","iron_shovel","water_bucket","oak_sign","iron_axe","iron_shovel","oak_sign","barrier"]

class Tile {
    let pixels=Array<Color>(256,repeat:Color.rgba(0,0,0,0))
    init(path: String) {
        try (surface=Surface.load(path)) {
            require(surface.size().w==16.0 && surface.size().h==16.0,"P0 block must be 16x16: "+path)
            for (i in 0..256) { pixels[i]=surface.readPixel(Int32(i%16),Int32(i/16)) }
        }
    }
    func sample(u: Float64,v: Float64): Color {
        pixels[min(15,max(0,Int64(v*16.0)))*16+min(15,max(0,Int64(u*16.0)))]
    }
}
class Assets <: Resource {
    let tiles=ArrayList<Tile>()
    let images=HashMap<String,Texture>()
    let r: Renderer
    var closed=false
    init(r: Renderer) {
        this.r=r
        try {
            for (name in BLOCK_PATHS) { tiles.add(Tile("assets/minecraft/textures/block/"+name+".png")) }
            image("textures/gui/widgets.png")
            image("textures/gui/container/generic_54.png")
            for (name in TOOL_PATHS) { image("textures/item/"+name+".png") }
        } catch (e: Exception) { close(); throw e }
    }
    func image(path: String): Texture {
        if (let Some(t) <- images.get(path)) { return t }
        let t=r.loadTexture("assets/minecraft/"+path)
        images[path]=t; return t
    }
    func sample(hit: Hit): Color {
        if (hit.material==10) {
            let stone=tiles[6].sample(hit.u,hit.v)
            let gray=(Int64(stone.r)+Int64(stone.g)+Int64(stone.b))/3
            return Color.rgb(gray*3/4,gray*3/4,gray*3/4)
        }
        if (hit.material==9) { return Color.rgb(49,114,178) }
        let index=match (hit.material) {
            case 1 => if (hit.axis==1) { 0 } else { 1 }
            case 2 => 2
            case 3 => if (hit.axis==1) { 4 } else { 3 }
            case 4 => 5
            case 5 => 6
            case 6 => 7
            case 7 => 8
            case _ => 9
        }
        let c=tiles[index].sample(hit.u,hit.v)
        if (hit.material==4 || (hit.material==1 && hit.axis==1)) {
            return Color.rgba(Int64(c.r)*91/255,Int64(c.g)*157/255,Int64(c.b)*57/255,Int64(c.a))
        }
        return c
    }
    func blit(path: String,b: Rect,source!: ?Rect=None,tint!: Color=Color.rgb(255,255,255)): Unit {
        r.textureStyled(image(path),b,source:source,style:TextureStyle(tint:tint,sampling:TextureScaleMode.Nearest))
    }
    public func close(): Unit {
        if (closed) { return }; closed=true
        for ((_,t) in images) { t.close() }; images.clear()
    }
    public func isClosed(): Bool { closed }
}
func hexByte(n: Int64): String {
    let digits="0123456789abcdef"
    return String.fromUtf8([digits[(n/16)%16],digits[n%16]])
}

// Legacy MC bitmap font: ASCII atlas + glyph_sizes.bin/Unicode pages. No fabricated TTF.
class PixelFont {
    let assets: Assets
    let widths: Array<UInt8>
    let asciiWidth=Array<Int64>(128,repeat:1)
    let availablePages=HashMap<Int64,Bool>()
    init(assets: Assets) {
        this.assets=assets
        widths=File.readFrom("assets/minecraft/font/glyph_sizes.bin")
        require(widths.size==65536,"Invalid MC glyph sizes")
        try (s=Surface.load("assets/minecraft/textures/font/ascii.png")) {
            for (code in 0..128) {
                var last: Int64 = 0
                for (y in 0..8) { for (x in 0..8) {
                    if (s.readPixel(Int32(code%16*8+x),Int32(code/16*8+y)).a>UInt8(0)) { last=max(last,x+1) }
                } }
                asciiWidth[code]=if (code==32) { 4 } else { max(1,last) }
            }
        }
    }
    func glyph(raw: Int64): Int64 {
        if (raw<32) { return 32 }
        if (raw<127) { return raw }
        if (raw>=widths.size || widths[raw]==UInt8(0)) { return 63 }
        let page=raw/256
        if (!availablePages.contains(page)) { availablePages[page]=exists("assets/minecraft/textures/font/unicode_page_"+hexByte(page)+".png") }
        return if (availablePages[page]) { raw } else { 63 }
    }
    func advance(raw: Int64,scale: Float32): Float32 {
        let code=glyph(raw)
        if (code>=32 && code<127) { return Float32(asciiWidth[code]+1)*2.0*scale }
        if (code<0 || code>=widths.size || widths[code]==UInt8(0)) { return 16.0*scale }
        let packed=Int64(widths[code]); return Float32((packed&15)-(packed>>4)+2)*scale
    }
    func measure(s: String,scale!: Float32=1.0): Float32 {
        var width: Float32=0.0
        for (ch in s.runes()) { width+=advance(Int64(UInt32(ch)),scale) }; return width
    }
    func draw(s: String,x: Float32,y: Float32,color!: Color=Color.rgb(235,235,224),scale!: Float32=1.0): Unit {
        var cursor=x
        for (ch in s.runes()) {
            if (UInt32(ch)<32) { continue }
            let code=glyph(Int64(UInt32(ch)))
            var path="textures/font/ascii.png"
            var source=Rect(Float32(code%16*8),Float32(code/16*8),Float32(asciiWidth[min(127,code)]),8.0)
            var factor: Float32=2.0*scale
            if (code>=127) {
                let packed=Int64(widths[code]); let left=packed>>4; let right=packed&15
                path="textures/font/unicode_page_"+hexByte(code/256)+".png"
                source=Rect(Float32(code%16*16+left),Float32(code/16%16*16),Float32(right-left+1),16.0)
                factor=scale
            }
            if (code!=32) {
                assets.blit(path,Rect(cursor+scale,y+scale,source.w*factor,source.h*factor),source:Some(source),tint:Color.rgb(25,28,24))
                assets.blit(path,Rect(cursor,y,source.w*factor,source.h*factor),source:Some(source),tint:color)
            }
            cursor+=advance(code,scale)
        }
    }
    func center(s: String,b: Rect,color!: Color=Color.rgb(235,235,224)): Unit {
        draw(s,b.centerX()-measure(s)/2.0,b.centerY()-8.0,color:color)
    }
}
