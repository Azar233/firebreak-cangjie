package firebreak

import sdl.*
import std.math.{round,abs}
import std.fs.remove

func verifyAdaptiveMenu(app: App,w: SdlWindow): Unit {
    let small=MenuLayout(Layout(1100.0,780.0)); let large=MenuLayout(Layout(2560.0,1380.0))
    pass(small.scale==1.0 && large.scale==small.scale && large.width==small.width && large.book.h*uiScale(2560.0,1380.0)>small.book.h,
        "Fullscreen scales the shared UI coordinate space, including menu, paper, buttons and text")
    for (size in [Size(1100.0,780.0),Size(1280.0,860.0),Size(1920.0,1080.0),Size(2560.0,1380.0),Size(3840.0,2160.0)]) {
        let m=MenuLayout(Layout(size.w,size.h))
        require(m.scale>=1.0 && m.scale<=3.0 && m.book.x>=0.0 && m.book.y>=0.0 && m.book.right()<=size.w &&
            m.bookAt(0.0,612.0,438.0,24.0).bottom()<=size.h,"Adaptive paper or footer outside window")
        for (page in 0..12) { for (id in m.controls(page)) {
            let b=m.box(id,page:page)
            require(b.x>=0.0 && b.y>=0.0 && b.right()<=size.w && b.bottom()<=size.h && b.w>=44.0 && b.h>=44.0,"Adaptive button outside window")
            require(m.hit(b.centerX(),b.centerY(),page)==id,"Scaled menu hit area differs from rendering")
        } }
        for (english in [false,true]) {
            app.preferences.setEnglish(english)
            for (page in 0..BOOK_PAGES) {
                app.bookPage=page; let body=m.bookBodyBox(); let lines=bookLines(app.font,bookBody(app),body.w,m.scale)
                require(Float32(lines.size-1)*22.0*m.scale+16.0*m.scale<=body.h,"Scaled book text exceeds paper height")
                for (line in lines) { require(app.font.measure(line,scale:m.scale)<=body.w,"Scaled book line exceeds paper width") }
            }
        }
    }
    pass(true,"all menu pages and bilingual book pages fit five sizes through 4K with aligned input targets")
    let ratios: Array<Float32>=[1.0,1.25,1.5,2.0]
    for (ratio in ratios) {
        let b=fontPixelRect(Rect(41.3,23.6,15.75,18.25),ratio)
        for (v in [b.x,b.y,b.right(),b.bottom()]) {
            require(abs(Float64(v*ratio)-round(Float64(v*ratio)))<0.0001,"Glyph corner is off the physical pixel grid")
        }
        require(b.w>0.0 && b.h>0.0,"Snapping removed glyph")
    }
    pass(rejected({=>fontPixelRect(Rect(1.0,1.0,16.0,16.0),0.0)}),"glyph snapping supports 100/125/150/200 percent DPI and rejects invalid ratios")
    let r=w.renderer; let ratio=Float32(w.scale)*Float32(w.currentPixelDensity)
    r.beginScene(Float32(w.width),Float32(w.height),Color.rgb(255,255,255))
    app.font.draw("中文 Ab",40.3,40.6,color:Color.rgb(53,40,28),shadow:false,snap:true,pixelRatio:ratio)
    app.font.draw("中文 Ab",300.3,40.6,color:Color.rgb(53,40,28),scale:2.0,shadow:true,snap:true,pixelRatio:ratio)
    r.endScene(); r.captureBmp("artifacts/font-clarity.bmp")
    try (s=Surface.loadBmp("artifacts/font-clarity.bmp")) {
        let px=s.size().w/Float32(w.width); var ink: Int64=0; var shadow: Int64=0; var control: Int64=0
        for (y in 0..Int64(100.0*px)) { for (x in 0..Int64(650.0*px)) {
            let c=s.readPixel(Int32(x),Int32(y))
            if (x<Int64(240.0*px)) {
                if (c.r==UInt8(53) && c.g==UInt8(40) && c.b==UInt8(28)) { ink++ }
                if (c.r==UInt8(25) && c.g==UInt8(28) && c.b==UInt8(24)) { shadow++ }
            } else if (c.r==UInt8(25) && c.g==UInt8(28) && c.b==UInt8(24)) { control++ }
        } }
        pass(ink>40 && shadow==0 && control>10,"native bitmap text draws legible ink without shadow while the shadowed control remains detectable")
    }
    remove("artifacts/font-clarity.bmp"); r.present()
    app.preferences.setEnglish(false); app.menuOpen=true; app.menuPage=6; app.bookPage=6; app.mapMode=true
    app.message=""; w.setSize(2560,1380); w.refreshSize()
    render(app,w,capture:"artifacts/handbook-fullscreen.png")
    let m=MenuLayout(Layout(Float32(w.width),Float32(w.height)))
    let previous=m.box(96,page:6)
    event(app,w,UiEvent.MouseDown(MouseButton.Left,previous.centerX(),previous.centerY()))
    event(app,w,UiEvent.MouseUp(MouseButton.Left,previous.centerX(),previous.centerY()))
    pass(app.bookPage==5,"fullscreen book arrows receive pointer events at their actual scaled positions")
    app.menuPage=0; render(app,w,capture:"artifacts/menu-fullscreen.png")
    w.setSize(1280,860); w.refreshSize()
    let back=MenuLayout(Layout(Float32(w.width),Float32(w.height))).box(80)
    event(app,w,UiEvent.MouseDown(MouseButton.Left,back.centerX(),back.centerY()))
    event(app,w,UiEvent.MouseUp(MouseButton.Left,back.centerX(),back.centerY()))
    pass(!app.menuOpen,"resizing an open menu updates both its layout and resume-button hit target")
    app.bookPage=0; app.mapMode=false; app.menuOpen=false; app.focus=0; app.cancel(); app.camera.reset()
}
