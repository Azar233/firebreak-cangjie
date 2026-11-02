package firebreak

import sdl.*

main(args: Array<String>): Int64 {
    try {
        let verify=args.size>0 && args[0]=="--verify"
        try (window=SdlWindow(WindowSpec("断火线 · P3 多情景方案对比",1280,860,supersample:1),hidden:verify)) {
            try(icon=Surface.loadPng("assets/generated/app-icon-64.png")){window.setIcon(icon)}
            try (assets=Assets(window.renderer)) {
                if(args.size>0 && args[0]=="--verify-gpu"){let app=App(assets);try{verifyGpu(app,window)}finally{app.close()};return 0}
                if(args.size>0 && args[0]=="--verify-shaders"){let app=App(assets);try{verifyShaders(app,window)}finally{app.close()};return 0}
                if (args.size>0 && args[0]=="--benchmark-forest") { ForestBenchmark().run(window,assets); return 0 }
                if (args.size>0 && args[0]=="--benchmark-gpu") { ForestBenchmark(gpu:true).run(window,assets); return 0 }
                if (args.size>0 && args[0]=="--benchmark-shaders") { ShaderBenchmark().run(window,assets); return 0 }
                if (args.size>0 && args[0]=="--forest-stress") { runForestLab(window,assets,readForestSpec(if (args.size>1) { args[1] } else { "examples/large-forest.json" })); return 0 }
                let app=App(assets,preferencesPath:if (verify) { "" } else { "settings.local.json" })
                if(verify){app.preferences.gpuEnabled=false}
                window.setTitle(app.t("断火线 · 场地规划工作台","Firebreak - Site Planning Workbench"))
                try {
                    if (verify) { verifyP1(app,window); verifyTopMap(app,window); verifyP2(app,window); verifyBurnDisplay(app,window); verifyP3(app,window); verifyMenu(app,window); verifyAdaptiveMenu(app,window); verifyP4(app,window); verifyPerformance(app,window); verifyRenderOptimization(app); verifyGpu(app,window); verifyMapNavigation(app,window); verifyShaders(app,window); verifyP0(app,window); return 0 }
                    var running=true
                    while (running) {
                        while (let Some(record) <- window.pollEventRecord()) { if (!app.handle(window,record)) { running=false; break } }
                        if (!running) { break }
                        app.pollFile(window)
                        if (app.exitReady) { break }
                        app.updateExperiment(window.ticks())
                        render(app,window); window.delay(12)
                    }
                } finally { app.close() }
            }
        }
        return 0
    } catch (e: Exception) { eprintln("Firebreak: "+e.message); return 1 }
}
