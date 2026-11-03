package firebreak

import sdl.*

main(args: Array<String>): Int64 {
    try {
        let verify=args.size>0 && (args[0]=="--verify" || args[0]=="--verify-agent" || args[0]=="--verify-agent-live" || args[0]=="--verify-examples" || args[0]=="--verify-audio" || args[0]=="--verify-workflow" || args[0]=="--verify-grid" || args[0]=="--verify-study" || args[0]=="--verify-long" || args[0]=="--verify-agent-lab" || args[0]=="--verify-agent-lab-live" || args[0]=="--verify-knowledge" || args[0]=="--verify-knowledge-live" || args[0]=="--verify-pipeline" || args[0]=="--verify-pipeline-live")
        try (window=SdlWindow(WindowSpec("断火线 · 森林实验",1280,860,supersample:1),hidden:verify)) {
            try(icon=Surface.loadPng("assets/generated/app-icon-64.png")){window.setIcon(icon)}
            try (assets=Assets(window.renderer)) {
                if(args.size>0 && (args[0]=="--verify-agent" || args[0]=="--verify-agent-live")){let app=App(assets,preferencesPath:if(args[0]=="--verify-agent-live"){"settings.local.json"}else{""},audioEnabled:false);try{verifyAgentChat(app,window,live:args[0]=="--verify-agent-live")}finally{app.close()};return 0}
                if(args.size>0 && (args[0]=="--verify-agent-lab" || args[0]=="--verify-agent-lab-live")){let app=App(assets,preferencesPath:if(args[0]=="--verify-agent-lab-live"){"settings.local.json"}else{""},audioEnabled:false);try{verifyAgentLab(app,window,live:args[0]=="--verify-agent-lab-live")}finally{app.close()};return 0}
                if(args.size>0 && (args[0]=="--verify-knowledge" || args[0]=="--verify-knowledge-live")){let app=App(assets,preferencesPath:if(args[0]=="--verify-knowledge-live"){"settings.local.json"}else{""},audioEnabled:false);try{verifyKnowledge(app,window,live:args[0]=="--verify-knowledge-live")}finally{app.close()};return 0}
                if(args.size>0 && (args[0]=="--verify-pipeline" || args[0]=="--verify-pipeline-live")){let app=App(assets,preferencesPath:if(args[0]=="--verify-pipeline-live"){"settings.local.json"}else{""},audioEnabled:false);try{verifyPipeline(app,window,live:args[0]=="--verify-pipeline-live")}finally{app.close()};return 0}
                if(args.size>0 && args[0]=="--verify-long"){let app=App(assets);try{verifyLong(app,window)}finally{app.close()};return 0}
                if(args.size>0 && args[0]=="--verify-study"){let app=App(assets);try{verifyStudy(app,window)}finally{app.close()};return 0}
                if(args.size>0 && args[0]=="--verify-grid"){let app=App(assets);try{verifyGrid(app,window)}finally{app.close()};return 0}
                if(args.size>0 && args[0]=="--verify-workflow"){let app=App(assets);try{verifyWorkflow(app,window)}finally{app.close()};return 0}
                if(args.size>0 && args[0]=="--verify-audio"){let app=App(assets);try{verifyAudio(app,window)}finally{app.close()};return 0}
                if(args.size>0 && args[0]=="--verify-examples"){let app=App(assets);try{verifyExamples(app,window)}finally{app.close()};return 0}
                if(args.size>0 && args[0]=="--verify-gpu"){let app=App(assets);try{verifyGpu(app,window)}finally{app.close()};return 0}
                if(args.size>0 && args[0]=="--verify-terminal"){let app=App(assets);try{verifyTerminal(app,window)}finally{app.close()};return 0}
                if(args.size>0 && args[0]=="--verify-agent-transport"){
                    let job=AgentConnectionJob(0,"deepseek-flash","");job.execute();let result=job.progress()
                    println("DeepSeek unauthenticated TLS transport: "+result.error)
                    require(result.done && result.error.startsWith("HTTP "),"Native verified TLS probe did not reach an HTTP response")
                    return 0
                }
                if(args.size>0 && args[0]=="--verify-shaders"){let app=App(assets);try{verifyShaders(app,window)}finally{app.close()};return 0}
                if (args.size>0 && args[0]=="--benchmark-forest") { ForestBenchmark().run(window,assets); return 0 }
                if (args.size>0 && args[0]=="--benchmark-gpu") { ForestBenchmark(gpu:true).run(window,assets); return 0 }
                if (args.size>0 && args[0]=="--benchmark-shaders") { ShaderBenchmark().run(window,assets); return 0 }
                if (args.size>0 && args[0]=="--forest-stress") { runForestLab(window,assets,readForestSpec(if (args.size>1) { args[1] } else { "examples/large-forest.json" })); return 0 }
                let app=App(assets,preferencesPath:if (verify) { "" } else { "settings.local.json" })
                if(verify){app.preferences.gpuEnabled=false}
                window.setTitle(app.t("断火线 · 森林实验","Firebreak - Forest Lab"))
                try {
                    if (verify) { verifyP1(app,window); verifyTopMap(app,window); verifyP2(app,window); verifyBurnDisplay(app,window); verifyP3(app,window); verifyMenu(app,window); verifyAdaptiveMenu(app,window); verifyP4(app,window); verifyPerformance(app,window); verifyRenderOptimization(app); verifyGpu(app,window); verifyMapNavigation(app,window); verifyShaders(app,window); verifyTerminal(app,window); verifyAgentChat(app,window); verifyExamples(app,window); verifyAudio(app,window); verifyWorkflow(app,window); verifyGrid(app,window); verifyStudy(app,window); verifyLong(app,window); verifyAgentLab(app,window); verifyKnowledge(app,window); verifyPipeline(app,window); verifyP0(app,window); return 0 }
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
