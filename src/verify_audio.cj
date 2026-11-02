package firebreak

import sdl.*
import std.fs.{File,remove}
import std.math.abs

func verifyAudio(app:App,w:SdlWindow):Unit {
    let path="artifacts/audio-prefs-test.json"
    try{
        File.writeTo(path,"{\"language\":\"zh-CN\"}".toArray());let p=Preferences(path)
        pass(p.soundVolume==35 && p.musicVolume==15,"Legacy settings retain safe default sound and music volumes")
        p.setAudio(25,40);p.setEnglish(true);p.setShowFps(true);p.setGpu(false);p.setShaders(true)
        let restored=Preferences(path)
        pass(restored.soundVolume==25 && restored.musicVolume==40,"Independent volumes persist across language and display preference changes")
        let bytes=File.readFrom(path)
        pass(rejected({=>p.setAudio(101,-1)}) && File.readFrom(path)==bytes && p.soundVolume==25 && p.musicVolume==40,"Out-of-range audio settings cannot overwrite existing preferences")
        File.writeTo(path,"{\"language\":\"zh-CN\",\"soundVolume\":-1,\"musicVolume\":300}".toArray())
        let invalid=Preferences(path);pass(invalid.soundVolume==35 && invalid.musicVolume==15,"Malformed saved volumes fall back without excessive gain")
    }finally{remove(path)}
    app.cancel();app.menuOpen=true;app.menuPage=0;app.menuFocus=80
    menuClick(app,w,103);pass(app.menuPage==8 && app.menuFocus==114,"Esc menu opens the dedicated sound settings page")
    let m=MenuLayout(Layout(Float32(w.width),Float32(w.height)));let b=m.box(114,page:8)
    app.preferences.setAudio(35,15)
    event(app,w,UiEvent.MouseDown(MouseButton.Left,b.x+b.w/2.0,b.centerY()))
    event(app,w,UiEvent.MouseMove(b.right()+100.0,b.centerY()))
    pass(app.audioDrag==114 && audioLevel(app,114)==100 && app.preferences.soundVolume==35,"Dragging previews clamped volume without persisting on every motion event")
    event(app,w,UiEvent.MouseUp(MouseButton.Left,b.right()+100.0,b.centerY()))
    pass(app.audioDrag== -1 && app.preferences.soundVolume==100 && app.preferences.musicVolume==15,"Releasing a slider commits its volume while preserving the other channel")
    terminalKey(app,w,Key.Home);pass(app.preferences.soundVolume==0,"Home mutes a focused sound slider")
    terminalKey(app,w,Key.Right);pass(app.preferences.soundVolume==5,"Keyboard arrows adjust volume by five percent")
    event(app,w,UiEvent.MouseDown(MouseButton.Left,b.right()-8.0,b.centerY()));event(app,w,UiEvent.WindowFocusLost)
    pass(app.audioDrag== -1 && app.preferences.soundVolume==5,"Focus loss cancels the transient slider draft")
    event(app,w,UiEvent.MouseDown(MouseButton.Left,b.right()-8.0,b.centerY()));terminalKey(app,w,Key.Escape)
    pass(app.audioDrag== -1 && app.preferences.soundVolume==5 && app.menuOpen,"Escape cancels slider dragging before closing the sound menu")
    app.preferences.setAudio(0,0);app.audio.open(0,0)
    require(app.audio.ready,"Native OGG playback unavailable: "+app.audio.error)
    pass(unsafe{MIX_GetAudioDuration(app.audio.clickAudio)>0 && MIX_GetAudioDuration(app.audio.musicAudio)>0},"SDL_mixer decodes both original OGG files without a conversion runtime")
    app.audio.setLevels(25,40)
    pass(abs(Float64(unsafe{MIX_GetTrackGain(app.audio.clickTrack)})-0.25)<0.001 && abs(Float64(unsafe{MIX_GetTrackGain(app.audio.musicTrack)})-0.4)<0.001,
        "Actual mixer tracks have independent sound and background music gains")
    let start=unsafe{MIX_GetTrackPlaybackPosition(app.audio.musicTrack)}
    for(_ in 0..100){if(unsafe{MIX_GetTrackPlaybackPosition(app.audio.musicTrack)}>start){break};w.delay(10)}
    pass(unsafe{MIX_GetTrackPlaybackPosition(app.audio.musicTrack)}>start,"Background music progresses on the native audio device independently of rendering")
    app.audio.setLevels(0,0);w.delay(30);let paused=unsafe{MIX_GetTrackPlaybackPosition(app.audio.musicTrack)};w.delay(40)
    pass(app.audio.musicPaused && unsafe{MIX_GetTrackPlaybackPosition(app.audio.musicTrack)}==paused,"Zero music volume pauses playback rather than leaving decoding active")
    app.preferences.setAudio(15,0);let clicks=app.audio.clickCount
    app.menuAction(w,88);app.menuAction(w,103)
    pass(app.audio.clickCount==clicks+2,"Real menu activations enqueue the provided UI sound once per button")
    app.preferences.setAudio(0,0);let muted=app.audio.clickCount;app.menuAction(w,88)
    pass(app.audio.clickCount==muted,"Muted UI buttons remain functional without starting click playback")
    app.menuAction(w,103);app.preferences.setAudio(35,15)
    app.preferences.setEnglish(false);render(app,w,capture:"artifacts/p6-audio-settings.png")
    app.audio.close();app.audio.close();pass(app.audio.isClosed(),"Audio tracks, streams, device and mixer close idempotently before SDL teardown")
    app.menuOpen=false;app.audioDrag = -1
}
