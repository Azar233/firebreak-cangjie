package firebreak

import std.collection.ArrayList

foreign {
    func QueryPerformanceCounter(value: CPointer<Int64>): Int32
    func QueryPerformanceFrequency(value: CPointer<Int64>): Int32
    func GetCurrentProcess(): CPointer<Unit>
    func K32GetProcessMemoryInfo(process: CPointer<Unit>,counters: CPointer<UInt64>,bytes: UInt32): Int32
}
func performanceCounter(frequency: Bool): Int64 {
    let value=Array<Int64>(1,repeat:0); let data=unsafe { acquireArrayRawData(value) }
    let ok=unsafe { if (frequency) { QueryPerformanceFrequency(data.pointer) } else { QueryPerformanceCounter(data.pointer) } }
    unsafe { releaseArrayRawData(data) }; require(ok!=0,"Windows performance counter unavailable"); return value[0]
}
class PerformanceClock {
    let frequency=Float64(performanceCounter(true))
    func ms(): Float64 { Float64(performanceCounter(false))*1000.0/frequency }
}
class ProcessMemory {
    let workingMiB: Float64
    let peakWorkingMiB: Float64
    let commitMiB: Float64
    init() {
        // PROCESS_MEMORY_COUNTERS on Windows x64: two DWORDs followed by eight SIZE_Ts.
        let counters=Array<UInt64>(9,repeat:0); counters[0]=72
        let data=unsafe { acquireArrayRawData(counters) }
        let ok=unsafe { K32GetProcessMemoryInfo(GetCurrentProcess(),data.pointer,UInt32(72)) }
        unsafe { releaseArrayRawData(data) }; require(ok!=0,"Windows process memory counters unavailable")
        workingMiB=Float64(counters[2])/1048576.0; peakWorkingMiB=Float64(counters[1])/1048576.0
        commitMiB=Float64(counters[7])/1048576.0
    }
}
class FrameStats {
    let median: Float64
    let p95: Float64
    let maximum: Float64
    init(values: Array<Float64>) {
        require(!values.isEmpty(),"Empty frame measurements")
        let sorted=ArrayList<Float64>()
        for (value in values) {
            var at: Int64=0; while (at<sorted.size && sorted[at]<=value) { at++ }; sorted.add(value,at:at)
        }
        median=sorted[sorted.size/2]; p95=sorted[min(sorted.size-1,(sorted.size*95+99)/100-1)]; maximum=sorted[sorted.size-1]
    }
}
class FrameMeter {
    let clock=PerformanceClock()
    var started: Float64=0.0
    var frames: Int64=0
    var fps: Float64=0.0
    func tick(now: Float64): Unit {
        if (started==0.0) { started=now; return }
        frames++
        if (now-started>=500.0) { fps=Float64(frames)*1000.0/(now-started); frames=0; started=now }
    }
}
