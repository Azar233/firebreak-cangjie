package firebreak

import sdl.*
import std.fs.{File,Directory,exists}

func menuClick(app: App,w: SdlWindow,id: Int64): Unit {
    let b=MenuLayout(Layout(Float32(w.width),Float32(w.height))).box(id,page:app.menuPage)
    event(app,w,UiEvent.MouseDown(MouseButton.Left,b.centerX(),b.centerY()))
    event(app,w,UiEvent.MouseUp(MouseButton.Left,b.centerX(),b.centerY()))
}
func verifyMenu(app: App,w: SdlWindow): Unit {
    app.exitReady=false; app.work.acceptLoaded(evaluationChain(),""); app.syncScene(); app.cancel()
    let run=app.experiment.create(app.work.project); run.play(w.ticks())
    event(app,w,UiEvent.KeyDown(Key.Escape,false))
    pass(app.menuOpen && app.menuPage==0 && !run.running,"Escape opens pause menu and pauses the current fire trial")
    let before=app.work.project.text(); let yaw=app.camera.yaw; let tool=app.tool
    let l=Layout(Float32(w.width),Float32(w.height))
    event(app,w,UiEvent.MouseDown(MouseButton.Right,l.canvas.x+20.0,l.canvas.y+20.0))
    event(app,w,UiEvent.MouseMove(l.canvas.x+180.0,l.canvas.y+30.0))
    event(app,w,UiEvent.MouseWheel(0.0,1.0,l.canvas.x+20.0,l.canvas.y+20.0))
    event(app,w,UiEvent.KeyDown(Key.Digit(UInt8(54)),false))
    event(app,w,UiEvent.KeyDown(Key.Letter(UInt8(87)),false))
    app.updateExperiment(w.ticks()+10000)
    pass(app.camera.yaw==yaw && app.tool==tool && app.work.project.text()==before && run.cursor==0 && !app.dragging,
        "modal menu blocks camera, world hotkeys, editing and simulation playback")
    let revision=app.work.revision; menuClick(app,w,85)
    pass(app.preferences.english && app.work.revision==revision && app.work.project.text()==before && menuLabel(app,80)=="Back to Workbench",
        "English switches immediately without changing site data or evaluation revision")
    pass(app.toolName(1)=="Forest" && app.landName(0)=="Empty" && localizedError("方案超过预算",true)=="Plan exceeds budget",
        "tools, land labels and model diagnostics have English text")
    for (size in [Size(1100.0,780.0),Size(1280.0,860.0),Size(2560.0,1380.0)]) {
        let layout=Layout(size.w,size.h); let m=MenuLayout(layout)
        for (page in 0..7) { for (id in m.controls(page)) {
            let b=m.box(id,page:page)
            require(b.w>=44.0 && b.h>=44.0 && b.x>=0.0 && b.y>=0.0 && b.right()<=size.w && b.bottom()<=size.h,"Menu target outside window")
            require(m.hit(b.centerX(),b.centerY(),page)==id,"Menu controls overlap")
        } }
    }
    pass(true,"menu, settings, exit and book targets fit three desktop sizes with non-overlapping 44px targets")
    app.menuFocus=80
    for (id in [81,82,83,84,85,98,86,87,80]) {
        event(app,w,UiEvent.KeyDown(Key.Tab,false)); require(app.menuFocus==id,"Menu tab order differs from visual order")
    }
    pass(true,"keyboard focus is trapped in the menu and follows visible row order")
    menuClick(app,w,81); menuClick(app,w,34); app.draft="-1"
    event(app,w,UiEvent.KeyDown(Key.Enter,false))
    pass(app.activeField==34 && app.work.project.budget==100000.0 && app.message.contains("out of range"),
        "menu budget input uses existing validation and retains invalid drafts")
    app.draft="200000"; event(app,w,UiEvent.KeyDown(Key.Enter,false)); menuClick(app,w,88)
    pass(app.menuPage==0 && app.work.project.budget==200000.0,"project settings commit through keyboard and return to menu")
    menuClick(app,w,83); menuClick(app,w,50); app.draft="1.5"; event(app,w,UiEvent.KeyDown(Key.Enter,false))
    pass(app.activeField==50 && app.work.project.burnSteps==1,"experiment settings reject fractional burn duration")
    event(app,w,UiEvent.KeyDown(Key.Escape,false)); event(app,w,UiEvent.KeyDown(Key.Escape,false))
    pass(app.menuPage==0 && app.menuOpen,"Escape first cancels numeric input, then returns to root menu")
    menuClick(app,w,82); let canopy=app.view.showCanopy; menuClick(app,w,90); menuClick(app,w,91); menuClick(app,w,92)
    pass(app.view.showCanopy!=canopy && app.camera.panX==0.0 && app.camera.zoom==20.0,"display settings apply to actual canopy, projection and camera state")
    event(app,w,UiEvent.KeyDown(Key.Escape,false)); menuClick(app,w,84)
    pass(menuTitle(app)=="Agent Settings" && MenuLayout(l).controls(4)==[88],"agent settings honestly shows disconnected status without fake active controls")
    event(app,w,UiEvent.KeyDown(Key.Escape,false)); menuClick(app,w,98)
    let bookTexture=app.assets.image("textures/gui/book.png")
    pass(app.menuPage==6 && bookTexture.width==256.0 && bookTexture.height==256.0 && !app.menuEnabled(96),
        "handbook opens original Minecraft book texture with previous page disabled on first page")
    for (english in [false,true]) {
        app.preferences.setEnglish(english)
        for (page in 0..BOOK_PAGES) {
            app.bookPage=page; let lines=bookLines(app.font,bookBody(app),350.0,1.0)
            require(lines.size<=18,"Handbook page exceeds readable paper area: ${page} / ${english} / ${lines.size}")
            for (line in lines) { require(app.font.measure(line)<=350.0,"Handbook line exceeds paper width") }
        }
    }
    pass(true,"all eight handbook pages wrap within the paper area in both languages")
    app.bookPage=0; event(app,w,UiEvent.KeyDown(Key.Right,false)); require(app.bookPage==1,"Book right key failed")
    event(app,w,UiEvent.KeyDown(Key.Left,false)); event(app,w,UiEvent.KeyDown(Key.Left,false))
    pass(app.bookPage==0,"book arrow keys turn pages and stop at first-page boundary")
    app.bookPage=BOOK_PAGES-1; menuClick(app,w,97)
    pass(app.bookPage==BOOK_PAGES-1 && !app.menuEnabled(97),"last page cannot advance beyond handbook content")
    menuClick(app,w,88); menuClick(app,w,98)
    pass(app.menuFocus==96,"reopening handbook at its last page focuses an enabled navigation target")
    app.bookPage=2; render(app,w,capture:"artifacts/handbook-en.png")
    app.preferences.setEnglish(false); render(app,w,capture:"artifacts/handbook-zh.png")
    menuClick(app,w,88); app.preferences.setEnglish(true); app.message="English interface / Esc menu / project handbook"
    render(app,w,capture:"artifacts/menu-en.png")
    menuClick(app,w,85); render(app,w,capture:"artifacts/menu-zh.png")
    let directory=Directory.createTemp("artifacts").toString(); let path=directory+"/settings.local.json"
    let preferences=Preferences(path); preferences.setEnglish(true); let loaded=Preferences(path)
    pass(loaded.english && exists(path),"language preference persists independently of saved project data")
    let temp=path+".writing"; File.writeTo(temp,"recovery".toArray())
    pass(rejected({=>preferences.setEnglish(false)}) && preferences.english && Preferences(path).english,
        "failed preference save preserves previous language and saved preference")
    let invalid=directory+"/invalid.json"; File.writeTo(invalid,"{}".toArray()); let fallback=Preferences(invalid)
    pass(!fallback.english && !fallback.loadError.isEmpty(),"malformed preferences safely fall back without blocking startup")
    let result=evaluated(evaluationChain(),[Scenario(0,0,42,1.0)])
    pass(evaluationReport(result,english:true).contains("Sample rates are not real-world fire probabilities") &&
        evaluationCsv(result).contains("baseline"),"English report preserves model limits and language-neutral numeric exports")
    app.preferences.setEnglish(true); menuClick(app,w,87)
    pass(app.menuPage==5 && !app.exitReady && app.menuFocus==95,"dirty project quit opens save/discard/cancel with safe cancel focus")
    menuClick(app,w,95)
    pass(app.menuPage==0 && app.work.dirty() && !app.exitReady,"cancelling exit preserves all unsaved changes")
    app.startCell=0; app.endCell=1; menuClick(app,w,87)
    pass(!app.menuEnabled(93) && app.selection().size==2,"unapplied preview is preserved and cannot be silently saved on exit")
    app.menuAction(w,93); require(!app.exitReady,"Disabled save-and-quit executed")
    app.cancel(); app.work.path=directory+"/saved.firebreak"; app.menuAction(w,93)
    pass(app.exitReady && !app.work.dirty() && exists(app.work.path) &&
        readProjectText(String.fromUtf8(File.readFrom(app.work.path))).budget==200000.0,"save-and-quit safely writes the current document before requesting exit")
    app.exitReady=false; app.menuPage=1; app.activeField=34; app.draft="123.45"
    event(app,w,UiEvent.WindowCloseRequested)
    event(app,w,UiEvent.TextInput("9"))
    require(app.draft=="123.45" && app.menuPage==5,"Quit prompt edited a hidden draft")
    event(app,w,UiEvent.KeyDown(Key.Escape,false))
    pass(app.menuOpen && app.menuPage==1 && app.activeField==34 && app.draft=="123.45" && !app.exitReady,
        "cancelling window-close returns to the original settings page with the numeric draft intact")
    app.menuOpen=false; app.activeField=34; app.draft="321.0"
    event(app,w,UiEvent.WindowCloseRequested); app.menuAction(w,95)
    pass(!app.menuOpen && app.activeField==34 && app.draft=="321.0" && !app.exitReady,
        "cancelling window-close from workbench restores the pending workbench input")
    app.cancel()
    app.exitReady=false; app.menuOpen=false; app.work.acceptLoaded(Project(),""); app.syncScene()
    event(app,w,UiEvent.KeyDown(Key.Escape,false)); event(app,w,UiEvent.KeyDown(Key.Escape,false))
    pass(!app.menuOpen && !app.experiment.run.isSome(),"Escape resumes workbench without automatically restarting simulation")
    click(app,w,53); pass(app.menuOpen,"visible Esc-menu button opens the same menu")
    app.work.apply([0],5,false); app.syncScene(); app.menuAction(w,87); app.menuAction(w,94)
    pass(app.exitReady && app.work.dirty(),"explicit discard-and-quit requests exit without pretending to save")
    app.exitReady=false; app.menuOpen=false; app.preferences.setEnglish(false); app.bookPage=0
    app.work.acceptLoaded(Project(),""); app.refreshReference(); app.syncScene(); app.camera.reset(); app.mapMode=false; app.view.showCanopy=true; app.cancel(); app.tool=0; app.focus=0
    println("Menu, bilingual UI, handbook, persistence and exit checks completed; visual quality awaits user review.")
}
