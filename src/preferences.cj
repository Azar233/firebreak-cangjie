package firebreak

import std.fs.{File,exists}
import stdx.encoding.json.*

// Application preference, deliberately separate from the saved site and model inputs.
class Preferences {
    let path: String
    var english=false
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
        } catch(e: Exception) { loadError=e.message }
    }
    func setEnglish(value: Bool): Unit {
        if (!path.isEmpty()) {
            let j=JsonObject(); j.put("language",JsonString(if (value) { "en-US" } else { "zh-CN" }))
            safeWrite(path,j.toJsonString())
        }
        english=value
    }
    func text(zh: String,en: String): String { if (english) { en } else { zh } }
}
