package firebreak

import std.convert.*
import std.fs.File
import stdx.encoding.json.*

func forestRandom(seed: Int64,x: Int64,z: Int64): Float64 {
    var h=(UInt64(seed)^UInt64(x+1)*UInt64(374761393)^UInt64(z+1)*UInt64(668265263))&UInt64(0xffffffff)
    h=((h^(h>>13))*UInt64(2246822519))&UInt64(0xffffffff)
    h=((h^(h>>16))*UInt64(3266489917))&UInt64(0xffffffff)
    return Float64(h^(h>>16))/4294967296.0
}
class ForestSpec {
    let size: Int64
    let density: Float64
    let seed: Int64
    init(size: Int64,density: Float64,seed: Int64) {
        require(size>=32 && size<=2048 && density>=0.0 && density<=1.0 && !density.isNaN() && seed>=0 && seed<=2147483647,"Invalid forest stress parameters")
        this.size=size; this.density=density; this.seed=seed
    }
}
func readForestSpec(path: String): ForestSpec {
    let bytes=File.readFrom(path); require(bytes.size<4096,"Forest descriptor too large")
    let j=JsonValue.fromStr(String.fromUtf8(bytes)).asObject()
    require(j["format"].asString().getValue()=="firebreak-forest-stress" && j["version"].asInt().getValue()==1,"Unsupported forest descriptor")
    return ForestSpec(j["size"].asInt().getValue(),Float64.parse(j["density"].asString().getValue()),j["seed"].asInt().getValue())
}
func forestField(spec: ForestSpec): Array<Bool> {
    let coarse=spec.size/32+2
    let noise=Array<Float64>(coarse*coarse,{i=>forestRandom(spec.seed+17,i%coarse,i/coarse)})
    return Array<Bool>(spec.size*spec.size,{i=>
        let x=i%spec.size; let z=i/spec.size; let ix=x/32; let iz=z/32
        let u=Float64(x%32)/32.0; let v=Float64(z%32)/32.0
        let a=noise[iz*coarse+ix]*(1.0-u)+noise[iz*coarse+ix+1]*u
        let b=noise[(iz+1)*coarse+ix]*(1.0-u)+noise[(iz+1)*coarse+ix+1]*u
        let probability=clamp(spec.density+(a*(1.0-v)+b*v-0.5)*0.6,0.0,1.0)
        return forestRandom(spec.seed,x,z)<probability
    })
}
class ForestExample {
    let spec: ForestSpec
    let scene: Scene
    let occupied: Int64
    let fieldMs: Float64
    let voxelMs: Float64
    var largest: Int64=0
    var connectivityMs: Float64=0.0
    init(spec: ForestSpec,clock: PerformanceClock) {
        this.spec=spec; let start=clock.ms(); let field=forestField(spec); fieldMs=clock.ms()-start
        let build=clock.ms(); scene=Scene(nx:spec.size,nz:spec.size,demo:false)
        var count: Int64=0
        for (i in 0..field.size) {
            scene.heights[i]=1; scene.canopyColumns[i]=field[i]
            scene.set(i%spec.size,0,i/spec.size,if (field[i]) { count++; 1 } else { 2 })
        }
        for (z in 0..spec.size) { for (x in 0..spec.size) {
            if (x%4==3 && z%4==3 && field[z*spec.size+x]) { scene.tree(x,z) }
        } }
        occupied=count; voxelMs=clock.ms()-build
    }
    func largestLabels(clock: PerformanceClock): Array<Int64> {
        let start=clock.ms(); let graph=Connectivity(scene.canopyColumns,scene.nx,scene.nz)
        largest=graph.largest
        let labels=Array<Int64>(scene.nx*scene.nz,{i=>if (graph.labels[i]==graph.largestLabel && graph.largestLabel>=0) { 0 } else { -1 }})
        connectivityMs=clock.ms()-start; return labels
    }
}
