package sdl

import std.collection.ArrayList

// Windows D3D11 interop through SDL's public native-device/texture properties.
// COM slots follow Microsoft's d3d11.h. All methods run on the renderer owner thread.
foreign {
    func SDL_GetPointerProperty(properties: UInt32,name: CString,fallback: CPointer<Unit>): CPointer<Unit>
    func SDL_GetTextureProperties(texture: CPointer<Unit>): UInt32
    func SDL_FlushRenderer(renderer: CPointer<Unit>): Bool
    func SDL_LoadObject(path: CString): CPointer<Unit>
    func SDL_LoadFunction(handle: CPointer<Unit>,name: CString): CPointer<Unit>
    func SDL_UnloadObject(handle: CPointer<Unit>): Unit
}
@C
internal struct ComputeMapped {
    var data=CPointer<UInt8>()
    var pitch: UInt32=0
    var slice: UInt32=0
}
internal func computeMethod(p: CPointer<Unit>,slot: Int64): CPointer<Unit> {
    if(p.isNull()){throw SdlException("Null D3D11 interface")}
    unsafe { CPointer<CPointer<Unit>>(CPointer<CPointer<Unit>>(p).read()).read(slot) }
}
internal func computeRelease(p: CPointer<Unit>): Unit {
    if(p.isNotNull()){let _=unsafe{CFunc<(CPointer<Unit>)->UInt32>(computeMethod(p,2))(p)}}
}
internal func computeCheck(hr: Int32,operation: String): Unit { if(hr<0){throw SdlException("${operation}: HRESULT ${hr}")} }
internal func computeProperty(props: UInt32,name: String): CPointer<Unit> {
    let c=unsafe{LibC.mallocCString(name)}
    var result=CPointer<Unit>()
    try(r=c.asResource()){result=unsafe{SDL_GetPointerProperty(props,r.value,CPointer<Unit>())}}
    return result
}

/** A bounded four-input raw-buffer compute image on SDL's D3D11 device. The
 * returned texture is borrowed until resize/close. No GPU readback in dispatch. */
public class ComputeImage <: Resource {
    private let renderer: Renderer
    private let generation: UInt64
    private var device=CPointer<Unit>()
    private var context=CPointer<Unit>()
    private var shader=CPointer<Unit>()
    private var constants=CPointer<Unit>()
    private let buffers=Array<CPointer<Unit>>(4,repeat:CPointer<Unit>())
    private let views=Array<CPointer<Unit>>(4,repeat:CPointer<Unit>())
    private let capacities=Array<Int64>(4,repeat:0)
    private var target=CPointer<Unit>()
    private var targetView=CPointer<Unit>()
    private var image: ?Texture=None
    private var closed=false
    public var uploads: Int64=0
    public var dispatches: Int64=0
    public var adapterName="Unknown D3D11 adapter"
    public var profile=false
    public var lastGpuMs: Float64= -1.0
    private var disjoint=CPointer<Unit>()
    private var firstStamp=CPointer<Unit>()
    private var lastStamp=CPointer<Unit>()
    public init(renderer: Renderer,source: String) {
        this.renderer=renderer; generation=renderer.renderDevice().currentGeneration()
        renderer.ensureRenderAccess("create compute image")
        if(renderer.driverName()!="direct3d11"){throw SdlException("GPU voxel backend requires SDL direct3d11")}
        device=computeProperty(unsafe{SDL_GetRendererProperties(renderer.ptr)},"SDL.renderer.d3d11.device")
        if(device.isNull()){throw SdlException("SDL did not expose a D3D11 device")}
        try {
            var immediate=CPointer<Unit>()
            unsafe{CFunc<(CPointer<Unit>,CPointer<CPointer<Unit>>)->Unit>(computeMethod(device,40))(device,inout immediate)}
            context=immediate
            adapterName=adapterDescription()
            compile(source)
            constants=createBuffer(256,4,0)
        } catch(e: Exception){close(); throw e}
    }
    private func ensure(): Unit {
        renderer.ensureRenderAccess("use compute image")
        if(closed || generation!=renderer.renderDevice().currentGeneration()){throw SdlException("Compute device generation expired")}
    }
    private func adapterDescription(): String {
        let guid=[UInt32(0x54ec77fa),UInt32(0x44e61377),UInt32(0xfd88328c),UInt32(0x4cc8445f)]
        let raw=unsafe{acquireArrayRawData(guid)};var dxgi=CPointer<Unit>();var adapter=CPointer<Unit>()
        try{computeCheck(unsafe{CFunc<(CPointer<Unit>,CPointer<UInt32>,CPointer<CPointer<Unit>>)->Int32>(computeMethod(device,0))(device,raw.pointer,inout dxgi)},"Query IDXGIDevice")}
        finally{unsafe{releaseArrayRawData(raw)}}
        try{
            computeCheck(unsafe{CFunc<(CPointer<Unit>,CPointer<CPointer<Unit>>)->Int32>(computeMethod(dxgi,7))(dxgi,inout adapter)},"GetAdapter")
            let desc=Array<UInt64>(40,repeat:0);let data=unsafe{acquireArrayRawData(desc)}
            try{
                computeCheck(unsafe{CFunc<(CPointer<Unit>,CPointer<Unit>)->Int32>(computeMethod(adapter,8))(adapter,CPointer<Unit>(data.pointer))},"GetAdapterDesc")
                let text=CPointer<UInt16>(data.pointer);let result=ArrayList<Rune>();var i: Int64=0
                while(i<128){var scalar=UInt32(unsafe{text.read(i)});i++;if(scalar==0){break}
                    if(scalar>=0xd800 && scalar<=0xdbff && i<128){let low=UInt32(unsafe{text.read(i)});i++;scalar=0x10000+(scalar-0xd800)*1024+low-0xdc00}
                    result.add(Rune(scalar))
                };return String(result)
            }finally{unsafe{releaseArrayRawData(data)}}
        }finally{computeRelease(adapter);computeRelease(dxgi)}
    }
    private func compile(source: String): Unit {
        let name=unsafe{LibC.mallocCString("d3dcompiler_47.dll")}; var library=CPointer<Unit>()
        try(r=name.asResource()){library=unsafe{SDL_LoadObject(r.value)}}
        if(library.isNull()){throw SdlException("System d3dcompiler_47.dll unavailable")}
        var code=CPointer<Unit>(); var errors=CPointer<Unit>()
        try {
            let symbol=unsafe{LibC.mallocCString("D3DCompile")}
            var function=CPointer<Unit>()
            try(r=symbol.asResource()){function=unsafe{SDL_LoadFunction(library,r.value)}}
            if(function.isNull()){throw SdlException("D3DCompile unavailable")}
            let bytes=source.toArray(); let data=unsafe{acquireArrayRawData(bytes)}
            let entry=unsafe{LibC.mallocCString("main")}; let profile=unsafe{LibC.mallocCString("cs_5_0")}
            var hr: Int32=0
            try(e=entry.asResource()){try(p=profile.asResource()){
                hr=unsafe{CFunc<(CPointer<UInt8>,UIntNative,CString,CPointer<Unit>,CPointer<Unit>,CString,CString,UInt32,UInt32,CPointer<CPointer<Unit>>,CPointer<CPointer<Unit>>)->Int32>(function)(data.pointer,UIntNative(bytes.size),CString(CPointer<UInt8>()),CPointer<Unit>(),CPointer<Unit>(),e.value,p.value,UInt32(1<<15),0,inout code,inout errors)}
            }} finally {unsafe{releaseArrayRawData(data)}}
            if(hr<0){
                var message="HLSL compilation failed"
                if(errors.isNotNull()){
                    let p=unsafe{CFunc<(CPointer<Unit>)->CPointer<UInt8>>(computeMethod(errors,3))(errors)}
                    let size=unsafe{CFunc<(CPointer<Unit>)->UIntNative>(computeMethod(errors,4))(errors)}
                    message=String.fromUtf8(Array<UInt8>(Int64(size),{i=>unsafe{p.read(i)}}))
                }
                throw SdlException(message)
            }
            let p=unsafe{CFunc<(CPointer<Unit>)->CPointer<Unit>>(computeMethod(code,3))(code)}
            let size=unsafe{CFunc<(CPointer<Unit>)->UIntNative>(computeMethod(code,4))(code)}
            var compiled=CPointer<Unit>()
            computeCheck(unsafe{CFunc<(CPointer<Unit>,CPointer<Unit>,UIntNative,CPointer<Unit>,CPointer<CPointer<Unit>>)->Int32>(computeMethod(device,18))(device,p,size,CPointer<Unit>(),inout compiled)},"CreateComputeShader")
            shader=compiled
        } finally {computeRelease(errors); computeRelease(code); unsafe{SDL_UnloadObject(library)}}
    }
    private func createBuffer(size: Int64,bind: UInt32,misc: UInt32): CPointer<Unit> {
        let desc=[UInt32(size),UInt32(0),bind,UInt32(0),misc,UInt32(0)]
        let data=unsafe{acquireArrayRawData(desc)}; var result=CPointer<Unit>()
        try {computeCheck(unsafe{CFunc<(CPointer<Unit>,CPointer<UInt32>,CPointer<Unit>,CPointer<CPointer<Unit>>)->Int32>(computeMethod(device,3))(device,data.pointer,CPointer<Unit>(),inout result)},"CreateBuffer")}
        finally {unsafe{releaseArrayRawData(data)}}
        return result
    }
    /** Replace one raw input; same-sized buffers update in place. */
    public func upload(slot: Int64,bytes: Array<UInt8>): Unit {
        ensure(); if(slot<0 || slot>=4 || bytes.isEmpty() || bytes.size%4!=0){throw SdlException("Compute input must be aligned and slot must be 0..3")}
        if(capacities[slot]!=bytes.size){
            var buffer=CPointer<Unit>(); var view=CPointer<Unit>()
            try {
                buffer=createBuffer(bytes.size,8,32)
                let desc=[UInt32(39),UInt32(11),UInt32(0),UInt32(bytes.size/4),UInt32(1),UInt32(0),UInt32(0),UInt32(0)]
                let data=unsafe{acquireArrayRawData(desc)}
                try{computeCheck(unsafe{CFunc<(CPointer<Unit>,CPointer<Unit>,CPointer<UInt32>,CPointer<CPointer<Unit>>)->Int32>(computeMethod(device,7))(device,buffer,data.pointer,inout view)},"CreateShaderResourceView")}
                finally{unsafe{releaseArrayRawData(data)}}
            }catch(e: Exception){computeRelease(view); computeRelease(buffer); throw e}
            computeRelease(views[slot]); computeRelease(buffers[slot]); views[slot]=view; buffers[slot]=buffer; capacities[slot]=bytes.size
        }
        let data=unsafe{acquireArrayRawData(bytes)}
        try{update(buffers[slot],CPointer<Unit>(data.pointer))}finally{unsafe{releaseArrayRawData(data)}}
        uploads++
    }
    private func update(resource: CPointer<Unit>,data: CPointer<Unit>): Unit {
        unsafe{CFunc<(CPointer<Unit>,CPointer<Unit>,UInt32,CPointer<Unit>,CPointer<Unit>,UInt32,UInt32)->Unit>(computeMethod(context,48))(context,resource,0,CPointer<Unit>(),data,0,0)}
    }
    private func query(kind: UInt32): CPointer<Unit> {
        let desc=[kind,UInt32(0)];let raw=unsafe{acquireArrayRawData(desc)};var result=CPointer<Unit>()
        try{computeCheck(unsafe{CFunc<(CPointer<Unit>,CPointer<UInt32>,CPointer<CPointer<Unit>>)->Int32>(computeMethod(device,24))(device,raw.pointer,inout result)},"Create timestamp query")}
        finally{unsafe{releaseArrayRawData(raw)}}
        return result
    }
    private func mark(q: CPointer<Unit>,begin: Bool): Unit {
        unsafe{CFunc<(CPointer<Unit>,CPointer<Unit>)->Unit>(computeMethod(context,if(begin){27}else{28}))(context,q)}
    }
    private func queryData(q: CPointer<Unit>,words: Int64): Array<UInt64> {
        let values=Array<UInt64>(words,repeat:0);let raw=unsafe{acquireArrayRawData(values)};let start=unsafe{SDL_GetTicks()}
        try{
            while(true){
                let hr=unsafe{CFunc<(CPointer<Unit>,CPointer<Unit>,CPointer<Unit>,UInt32,UInt32)->Int32>(computeMethod(context,29))(context,q,CPointer<Unit>(raw.pointer),UInt32(words*8),0)}
                computeCheck(hr,"Read GPU timestamp");if(hr==0){break}
                if(unsafe{SDL_GetTicks()}-start>5000){throw SdlException("GPU timestamp timed out")};unsafe{SDL_Delay(1)}
            }
        }finally{unsafe{releaseArrayRawData(raw)}}
        return values
    }
    private func resize(width: Int64,height: Int64): Unit {
        if(let Some(t)<-image){if(Int64(t.width)==width && Int64(t.height)==height){return}}
        var next=CPointer<Unit>(); var view=CPointer<Unit>(); var replacement: ?Texture=None
        try {
            let desc=[UInt32(width),UInt32(height),UInt32(1),UInt32(1),UInt32(28),UInt32(1),UInt32(0),UInt32(0),UInt32(128),UInt32(0),UInt32(0)]
            let data=unsafe{acquireArrayRawData(desc)}
            try{computeCheck(unsafe{CFunc<(CPointer<Unit>,CPointer<UInt32>,CPointer<Unit>,CPointer<CPointer<Unit>>)->Int32>(computeMethod(device,5))(device,data.pointer,CPointer<Unit>(),inout next)},"CreateTexture2D")}
            finally{unsafe{releaseArrayRawData(data)}}
            computeCheck(unsafe{CFunc<(CPointer<Unit>,CPointer<Unit>,CPointer<Unit>,CPointer<CPointer<Unit>>)->Int32>(computeMethod(device,8))(device,next,CPointer<Unit>(),inout view)},"CreateUnorderedAccessView")
            let texture=unsafe{SDL_CreateTexture(renderer.ptr,SDL_PIXELFORMAT_RGBA32,0,Int32(width),Int32(height))}
            if(texture.isNull()){throw SdlException("Create compute presentation texture: ${lastSdlError()}")}
            replacement=Some(Texture(texture,renderer.renderDevice()))
            let native=computeProperty(unsafe{SDL_GetTextureProperties(texture)},"SDL.texture.d3d11.texture")
            if(native.isNull()){throw SdlException("SDL presentation texture has no D3D11 resource")}
        }catch(e: Exception){if(let Some(t)<-replacement){t.close()}; computeRelease(view); computeRelease(next); throw e}
        if(let Some(t)<-image){t.close()}; computeRelease(targetView); computeRelease(target)
        image=replacement; target=next; targetView=view
    }
    /** Submit at native output resolution; returns a borrowed SDL presentation texture. */
    public func dispatch(width: Int64,height: Int64,parameters: Array<Float32>): Texture {
        ensure()
        if(width<=0 || height<=0 || width>8192 || height>8192 || width*height>16777216 || parameters.size!=64){throw SdlException("Invalid compute output or constants")}
        for(v in views){if(v.isNull()){throw SdlException("Compute input not uploaded")}}
        ensureSdl(unsafe{SDL_FlushRenderer(renderer.ptr)},"SDL_FlushRenderer")
        resize(width,height)
        let data=unsafe{acquireArrayRawData(parameters)}
        try{update(constants,CPointer<Unit>(data.pointer))}finally{unsafe{releaseArrayRawData(data)}}
        let inputs=unsafe{acquireArrayRawData(views)}; let uav=[targetView]; let cb=[constants]
        let u=unsafe{acquireArrayRawData(uav)}; let c=unsafe{acquireArrayRawData(cb)}
        try {
            if(profile){
                if(disjoint.isNull()){disjoint=query(3);firstStamp=query(2);lastStamp=query(2)}
                mark(disjoint,true);mark(firstStamp,false)
            }
            unsafe{
                CFunc<(CPointer<Unit>,UInt32,UInt32,CPointer<CPointer<Unit>>)->Unit>(computeMethod(context,67))(context,0,4,inputs.pointer)
                CFunc<(CPointer<Unit>,UInt32,UInt32,CPointer<CPointer<Unit>>,CPointer<UInt32>)->Unit>(computeMethod(context,68))(context,0,1,u.pointer,CPointer<UInt32>())
                CFunc<(CPointer<Unit>,UInt32,UInt32,CPointer<CPointer<Unit>>)->Unit>(computeMethod(context,71))(context,0,1,c.pointer)
                CFunc<(CPointer<Unit>,CPointer<Unit>,CPointer<Unit>,UInt32)->Unit>(computeMethod(context,69))(context,shader,CPointer<Unit>(),0)
                CFunc<(CPointer<Unit>,UInt32,UInt32,UInt32)->Unit>(computeMethod(context,41))(context,UInt32((width+7)/8),UInt32((height+7)/8),1)
            }
            // Unbind UAV before copying, and leave no compute bindings in SDL's context.
            unsafe{
                u.pointer.write(CPointer<Unit>())
                CFunc<(CPointer<Unit>,UInt32,UInt32,CPointer<CPointer<Unit>>,CPointer<UInt32>)->Unit>(computeMethod(context,68))(context,0,1,u.pointer,CPointer<UInt32>())
                CFunc<(CPointer<Unit>,UInt32,UInt32,CPointer<CPointer<Unit>>)->Unit>(computeMethod(context,71))(context,0,1,u.pointer)
                CFunc<(CPointer<Unit>,CPointer<Unit>,CPointer<Unit>,UInt32)->Unit>(computeMethod(context,69))(context,CPointer<Unit>(),CPointer<Unit>(),0)
            }
            let blank=Array<CPointer<Unit>>(4,repeat:CPointer<Unit>()); let raw=unsafe{acquireArrayRawData(blank)}
            try{unsafe{CFunc<(CPointer<Unit>,UInt32,UInt32,CPointer<CPointer<Unit>>)->Unit>(computeMethod(context,67))(context,0,4,raw.pointer)}}finally{unsafe{releaseArrayRawData(raw)}}
            let output=image.getOrThrow(); let native=computeProperty(unsafe{SDL_GetTextureProperties(output.ptr)},"SDL.texture.d3d11.texture")
            unsafe{CFunc<(CPointer<Unit>,CPointer<Unit>,CPointer<Unit>)->Unit>(computeMethod(context,47))(context,native,target)}
            if(profile){
                mark(lastStamp,false);mark(disjoint,false)
                let timing=queryData(disjoint,2);let first=queryData(firstStamp,1)[0];let last=queryData(lastStamp,1)[0]
                if(timing[1]!=0 || timing[0]==0 || last<first){throw SdlException("GPU clock changed during timestamp sample")}
                lastGpuMs=Float64(last-first)*1000.0/Float64(timing[0])
            }
            computeCheck(unsafe{CFunc<(CPointer<Unit>)->Int32>(computeMethod(device,39))(device)},"D3D11 device removed")
            dispatches++; return output
        } finally {unsafe{releaseArrayRawData(inputs); releaseArrayRawData(u); releaseArrayRawData(c)}}
    }
    /** Explicit synchronization/readback for validation and completed-frame timings only. */
    public func readback(): Array<UInt8> {
        ensure(); let t=image.getOrThrow(); var staging=CPointer<Unit>()
        var result=Array<UInt8>()
        let desc=[UInt32(t.width),UInt32(t.height),UInt32(1),UInt32(1),UInt32(28),UInt32(1),UInt32(0),UInt32(3),UInt32(0),UInt32(0x20000),UInt32(0)]
        let raw=unsafe{acquireArrayRawData(desc)}
        try{computeCheck(unsafe{CFunc<(CPointer<Unit>,CPointer<UInt32>,CPointer<Unit>,CPointer<CPointer<Unit>>)->Int32>(computeMethod(device,5))(device,raw.pointer,CPointer<Unit>(),inout staging)},"Create readback texture")}
        finally{unsafe{releaseArrayRawData(raw)}}
        try{
            unsafe{CFunc<(CPointer<Unit>,CPointer<Unit>,CPointer<Unit>)->Unit>(computeMethod(context,47))(context,staging,target)}
            var mapped=ComputeMapped()
            computeCheck(unsafe{CFunc<(CPointer<Unit>,CPointer<Unit>,UInt32,UInt32,UInt32,CPointer<ComputeMapped>)->Int32>(computeMethod(context,14))(context,staging,0,1,0,inout mapped)},"Map readback")
            let pixels=mapped.data; let pitch=Int64(mapped.pitch)
            try{result=Array<UInt8>(Int64(t.width)*Int64(t.height)*4,{i=>unsafe{pixels.read((i/(Int64(t.width)*4))*pitch+i%(Int64(t.width)*4))}})}
            finally{unsafe{CFunc<(CPointer<Unit>,CPointer<Unit>,UInt32)->Unit>(computeMethod(context,15))(context,staging,0)}}
        }finally{computeRelease(staging)}
        return result
    }
    public func isClosed(): Bool {closed}
    public func isCurrent(): Bool {!closed && renderer.renderDevice().isActive() && generation==renderer.renderDevice().currentGeneration()}
    public func close(): Unit {
        if(closed){return}; if(renderer.renderDevice().isActive()){renderer.ensureRenderAccess("close compute image")}
        closed=true; if(let Some(t)<-image){t.close()}; image=None
        computeRelease(targetView); computeRelease(target)
        for(i in 0..4){computeRelease(views[i]); computeRelease(buffers[i])}
        computeRelease(constants); computeRelease(shader); computeRelease(context)
        computeRelease(disjoint);computeRelease(firstStamp);computeRelease(lastStamp)
    }
}
