package firebreak_probe

import magic.dsl.*
import magic.prelude.*
import std.collection.HashMap
import stdx.encoding.json.JsonValue

@tool[description: "Read the immutable P0 scene summary"]
func sceneSummary(): String { "P0 scene: 24 x 20 ground cells; no fire simulation yet" }

@agent[model: "deepseek:deepseek-chat", tools: [sceneSummary], skillBuiltinTools: false]
class Researcher {
    @prompt("Explain only the scene data returned by tools. P0 is an offline compatibility probe.")
}

main(): Int64 {
    let agent=Researcher()
    var found=false
    for (tool in agent.toolManager.tools) {
        if (tool.name=="sceneSummary") {
            let result=tool.invoke(HashMap<String,JsonValue>()).content
            if (!result.contains("24 x 20")) { eprintln("Tool returned wrong scene summary"); return 1 }
            found=true; println("PASS CangjieMagic @agent/@tool compile, construct, register and invoke offline")
        }
    }
    if (!found) { eprintln("Scene tool was not registered"); return 1 }
    println("No model request sent. Online research assistant is not implemented in P0.")
    return 0
}
