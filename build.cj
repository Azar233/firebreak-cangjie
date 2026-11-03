import std.process.*
import std.fs.exists

func prepare(stage:String):Int64 {
    let process=launch("powershell",["-NoProfile","-ExecutionPolicy","Bypass","-File","tools/cjpm-build.ps1","-Stage",stage])
    return process.wait()
}
main():Int64 {
    match(Process.current.arguments[0]){
        // Bootstrap before cjpm resolves the first fresh checkout's path dependencies.
        case "pre-run"=>
            if(!exists("../.reference/CangjieMagic/cjpm.toml") || !exists("vendor/SDL/.sdl3/SDL3.dll") || !exists("../.tools/stdx-1.0.5.1/windows_x86_64_cjnative/dynamic/stdx/libstdx.encoding.json.dll")){return prepare("Prepare")};return 0
        case "pre-build"=>prepare("Prepare")
        case "post-build"=>prepare("Finalize")
        case _=>0
    }
}
