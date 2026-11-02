package firebreak

import std.fs.exists

foreign {
    func MIX_Init():Bool
    func MIX_Quit():Unit
    func MIX_CreateMixerDevice(id:UInt32,spec:CPointer<Unit>):CPointer<Unit>
    func MIX_DestroyMixer(mixer:CPointer<Unit>):Unit
    func MIX_LoadAudio(mixer:CPointer<Unit>,path:CString,predecode:Bool):CPointer<Unit>
    func MIX_DestroyAudio(audio:CPointer<Unit>):Unit
    func MIX_GetAudioDuration(audio:CPointer<Unit>):Int64
    func MIX_CreateTrack(mixer:CPointer<Unit>):CPointer<Unit>
    func MIX_SetTrackAudio(track:CPointer<Unit>,audio:CPointer<Unit>):Bool
    func MIX_SetTrackGain(track:CPointer<Unit>,gain:Float32):Bool
    func MIX_GetTrackGain(track:CPointer<Unit>):Float32
    func MIX_PlayTrack(track:CPointer<Unit>,options:UInt32):Bool
    func MIX_PauseTrack(track:CPointer<Unit>):Bool
    func MIX_ResumeTrack(track:CPointer<Unit>):Bool
    func MIX_GetTrackPlaybackPosition(track:CPointer<Unit>):Int64
    func SDL_CreateProperties():UInt32
    func SDL_SetNumberProperty(properties:UInt32,name:CString,value:Int64):Bool
    func SDL_DestroyProperties(properties:UInt32):Unit
}
class UiAudio <: Resource {
    var mixer=CPointer<Unit>()
    var clickAudio=CPointer<Unit>()
    var musicAudio=CPointer<Unit>()
    var clickTrack=CPointer<Unit>()
    var musicTrack=CPointer<Unit>()
    var initialized=false
    var closed=false
    var ready=false
    var musicPaused=false
    var error=""
    var clickCount:Int64=0
    func load(path:String,predecode:Bool):CPointer<Unit> {
        let c=unsafe{LibC.mallocCString(path)};var audio=CPointer<Unit>()
        try(name=c.asResource()){audio=unsafe{MIX_LoadAudio(mixer,name.value,predecode)}}
        require(audio.isNotNull(),"OGG 音频读取失败 / Could not decode OGG audio")
        return audio
    }
    func open(sound:Int64,music:Int64):Unit {
        if(initialized || closed){return}
        try{
            require(exists("assets/minecraft/sounds/click_stereo.ogg") && exists("assets/minecraft/sounds/Minecraft.ogg"),"未找到本地音频 / Local audio files missing")
            require(unsafe{MIX_Init()},"音频初始化失败 / Audio initialization failed");initialized=true
            mixer=unsafe{MIX_CreateMixerDevice(UInt32(0xffffffff),CPointer<Unit>())}
            require(mixer.isNotNull(),"音频设备不可用 / Audio device unavailable")
            clickAudio=load("assets/minecraft/sounds/click_stereo.ogg",true)
            musicAudio=load("assets/minecraft/sounds/Minecraft.ogg",false)
            clickTrack=unsafe{MIX_CreateTrack(mixer)};musicTrack=unsafe{MIX_CreateTrack(mixer)}
            require(clickTrack.isNotNull() && musicTrack.isNotNull(),"音轨创建失败 / Could not create audio tracks")
            require(unsafe{MIX_SetTrackAudio(clickTrack,clickAudio) && MIX_SetTrackAudio(musicTrack,musicAudio)},"音轨设置失败 / Could not set audio tracks")
            ready=true;setGains(sound,music)
            let options=unsafe{SDL_CreateProperties()};require(options!=0,"Audio loop options failed")
            try{
                let c=unsafe{LibC.mallocCString("SDL_mixer.play.loops")}
                try(name=c.asResource()){require(unsafe{SDL_SetNumberProperty(options,name.value,-1)},"Audio loop option failed")}
                require(unsafe{MIX_PlayTrack(musicTrack,options)},"音乐播放失败 / Music playback failed")
            }finally{unsafe{SDL_DestroyProperties(options)}}
            musicPaused=false;setLevels(sound,music)
        }catch(ex:Exception){error=ex.message;close()}
    }
    func setGains(sound:Int64,music:Int64):Unit {
        if(!ready){return}
        let _=unsafe{MIX_SetTrackGain(clickTrack,Float32(max(0,min(100,sound)))/100.0)}
        let _=unsafe{MIX_SetTrackGain(musicTrack,Float32(max(0,min(100,music)))/100.0)}
    }
    func setLevels(sound:Int64,music:Int64):Unit {
        setGains(sound,music);if(!ready){return}
        if(music==0 && !musicPaused){let _=unsafe{MIX_PauseTrack(musicTrack)};musicPaused=true}
        if(music>0 && musicPaused){let _=unsafe{MIX_ResumeTrack(musicTrack)};musicPaused=false}
    }
    func click(volume:Int64):Unit {
        if(!ready || volume<=0){return}
        let _=unsafe{MIX_SetTrackGain(clickTrack,Float32(min(100,volume))/100.0)}
        if(unsafe{MIX_PlayTrack(clickTrack,0)}){clickCount++}
    }
    public func isClosed():Bool {closed}
    public func close():Unit {
        if(closed){return};ready=false
        if(mixer.isNotNull()){unsafe{MIX_DestroyMixer(mixer)};mixer=CPointer<Unit>()}
        if(clickAudio.isNotNull()){unsafe{MIX_DestroyAudio(clickAudio)};clickAudio=CPointer<Unit>()}
        if(musicAudio.isNotNull()){unsafe{MIX_DestroyAudio(musicAudio)};musicAudio=CPointer<Unit>()}
        if(initialized){unsafe{MIX_Quit()};initialized=false};closed=true
    }
}
