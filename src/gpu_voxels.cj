package firebreak

import sdl.*
import std.fs.File

func gpuWordBytes(words: Array<UInt32>): Array<UInt8> {
    let raw=unsafe{acquireArrayRawData(words)}
    try { let p=CPointer<UInt8>(raw.pointer); return Array<UInt8>(words.size*4,{i=>unsafe{p.read(i)}}) }
    finally {unsafe{releaseArrayRawData(raw)}}
}
func gpuAligned(bytes: Array<UInt8>): Array<UInt8> {
    if(bytes.size%4==0){return bytes}
    return Array<UInt8>((bytes.size+3)/4*4,{i=>if(i<bytes.size){bytes[i]}else{0}})
}
class GpuVoxels <: Resource {
    let engine: ComputeImage
    var texture: ?Texture=None
    var sceneRevision: Int64= -1
    var displayRevision: Int64= -1
    init(assets: Assets) {
        engine=ComputeImage(assets.r,String.fromUtf8(File.readFrom("assets/shaders/voxel.hlsl")))
        try {
            let atlas=Array<UInt8>(assets.tiles.size*256*4,{i=>
                let p=assets.tiles[i/1024].pixels[(i/4)%256]
                match(i%4){case 0=>p.r;case 1=>p.g;case 2=>p.b;case _=>p.a}
            })
            engine.upload(2,atlas)
        }catch(e: Exception){engine.close(); throw e}
    }
    func prepare(view: VoxelView,camera: Camera,b: Rect,width: Int64,height: Int64): Unit {
        let scene=view.scene
        if(sceneRevision!=scene.revision){
            engine.upload(0,gpuAligned(scene.blocks))
            engine.upload(3,gpuAligned(Array<UInt8>(scene.chunkCounts.size,{i=>if(scene.chunkCounts[i]>0){1}else{0}})))
        }
        if(sceneRevision!=scene.revision || displayRevision!=view.displayRevision){
            let words=Array<UInt32>(scene.nx*scene.nz,{i=>
                let label=view.clusterLabels[i]
                return UInt32(scene.heights[i])|(UInt32(view.burnStages[i])<<8)|
                    (if(view.fireAge[i]>0){UInt32(4096)}else if(view.fireAge[i]<0){UInt32(8192)}else{UInt32(0)})|
                    (if(label>=0){UInt32(65536)|(UInt32(label%6)<<17)}else{UInt32(0)})
            })
            engine.upload(1,gpuWordBytes(words)); displayRevision=view.displayRevision; sceneRevision=scene.revision
        }
        let p=Array<Float32>(64,repeat:0.0)
        p[0]=Float32(scene.nx); p[1]=Float32(scene.ny); p[2]=Float32(scene.nz); p[3]=if(view.topDown){1.0}else{0.0}
        p[4]=Float32(width); p[5]=Float32(height); p[6]=if(view.showCanopy){1.0}else{0.0}; p[7]=Float32(view.selectedX)
        p[8]=Float32(view.selectedZ); p[9]=Float32(camera.zoom); p[10]=b.w; p[11]=b.h
        let target=camera.target(); p[12]=Float32(target.x);p[13]=Float32(target.y);p[14]=Float32(target.z);p[15]=Float32(camera.distance)
        let right=camera.right();p[16]=Float32(right.x);p[17]=Float32(right.y);p[18]=Float32(right.z);p[19]=Float32(camera.panX)
        let up=camera.up();p[20]=Float32(up.x);p[21]=Float32(up.y);p[22]=Float32(up.z);p[23]=Float32(camera.panY)
        let outward=camera.outward();p[24]=Float32(outward.x);p[25]=Float32(outward.y);p[26]=Float32(outward.z)
        p[28]=Float32(scene.chunksX);p[29]=Float32(scene.chunksY)
        texture=Some(engine.dispatch(width,height,p))
    }
    public func isClosed(): Bool {engine.isClosed()}
    public func close(): Unit {engine.close();texture=None}
}
