package firebreak

import std.fs.{File,exists}
import stdx.encoding.json.*

// Application preference, deliberately separate from the saved site and model inputs.
class Preferences {
    let path: String
    var english=false
    var showFps=false
    var gpuEnabled=true
    var shadersEnabled=false
    var soundVolume:Int64=35
    var musicVolume:Int64=15
    var loadError=""
    init(path: String) {
        this.path=path
        if (path.isEmpty() || !exists(path)) { return }
        try {
            let bytes=File.readFrom(path); require(bytes.size<=4096,"Preferences file is too large")
            let j=JsonValue.fromStr(String.fromUtf8(bytes)).asObject()
            let language=j["language"].asString().getValue()
            require(language=="zh-CN" || language=="en-US","Unsupported language preference")
            english=language=="en-US"
            try { showFps=j["showFps"].asBool().getValue() } catch(_: Exception) { showFps=false }
            try { gpuEnabled=j["gpuEnabled"].asBool().getValue() } catch(_: Exception) { gpuEnabled=true }
            try { shadersEnabled=j["shadersEnabled"].asBool().getValue() } catch(_: Exception) { shadersEnabled=false }
            try{let n=j["soundVolume"].asInt().getValue();require(n>=0 && n<=100,"Invalid sound volume");soundVolume=n}catch(_:Exception){soundVolume=35}
            try{let n=j["musicVolume"].asInt().getValue();require(n>=0 && n<=100,"Invalid music volume");musicVolume=n}catch(_:Exception){musicVolume=15}
        } catch(e: Exception) { loadError=e.message }
    }
    func save(language: Bool,fps: Bool,gpu: Bool,shaders: Bool,sound:Int64,music:Int64): Unit {
        if (!path.isEmpty()) {
            let j=JsonObject(); j.put("language",JsonString(if (language) { "en-US" } else { "zh-CN" }))
            j.put("showFps",JsonBool(fps)); j.put("gpuEnabled",JsonBool(gpu));j.put("shadersEnabled",JsonBool(shaders));j.put("soundVolume",JsonInt(sound));j.put("musicVolume",JsonInt(music));safeWrite(path,j.toJsonString())
        }
    }
    func setEnglish(value: Bool): Unit { save(value,showFps,gpuEnabled,shadersEnabled,soundVolume,musicVolume); english=value
    }
    func setShowFps(value: Bool): Unit { save(english,value,gpuEnabled,shadersEnabled,soundVolume,musicVolume); showFps=value
    }
    func setGpu(value: Bool): Unit {save(english,showFps,value,shadersEnabled,soundVolume,musicVolume);gpuEnabled=value}
    func setShaders(value: Bool): Unit {save(english,showFps,gpuEnabled,value,soundVolume,musicVolume);shadersEnabled=value}
    func setAudio(sound:Int64,music:Int64):Unit {require(sound>=0 && sound<=100 && music>=0 && music<=100,"Volume must be 0-100");save(english,showFps,gpuEnabled,shadersEnabled,sound,music);soundVolume=sound;musicVolume=music}
    func text(zh: String,en: String): String { if (english) { en } else { zh } }
}
