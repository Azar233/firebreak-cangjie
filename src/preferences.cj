package firebreak

import std.fs.{File,exists}
import stdx.encoding.json.*

// Application preference, deliberately separate from the saved site and model inputs.
class Preferences {
    let path: String
    var english=false
    var showFps=false
    var gpuEnabled=true
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
        } catch(e: Exception) { loadError=e.message }
    }
    func save(language: Bool,fps: Bool,gpu: Bool): Unit {
        if (!path.isEmpty()) {
            let j=JsonObject(); j.put("language",JsonString(if (language) { "en-US" } else { "zh-CN" }))
            j.put("showFps",JsonBool(fps)); j.put("gpuEnabled",JsonBool(gpu));safeWrite(path,j.toJsonString())
        }
    }
    func setEnglish(value: Bool): Unit { save(value,showFps,gpuEnabled); english=value
    }
    func setShowFps(value: Bool): Unit { save(english,value,gpuEnabled); showFps=value
    }
    func setGpu(value: Bool): Unit {save(english,showFps,value);gpuEnabled=value}
    func text(zh: String,en: String): String { if (english) { en } else { zh } }
}
