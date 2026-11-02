package sdl

extend Surface {
    /** Write RGBA32 rows under one native lock, respecting pitch. The callback must
     * not close or mutate this surface. Unlocks even when the callback throws. */
    public func writeRgbaRows(from: Int64,to: Int64,pixel: (Int64,Int64)->Color): Unit {
        if (isClosed()) { throw SdlException("Surface is already closed.") }
        ensureSdl(unsafe { SDL_LockSurface(ptr) },"SDL_LockSurface")
        try {
            let header=unsafe { CPointer<SdlSurfaceHeader>(ptr).read() }
            if (header.format!=SDL_PIXELFORMAT_RGBA32 || from<0 || to<from || to>Int64(header.height) ||
                Int64(header.pitch)<Int64(header.width)*4 || header.pixels.isNull()) {
                throw SdlException("Invalid RGBA32 row storage or range")
            }
            for (y in from..to) { for (x in 0..Int64(header.width)) {
                let c=pixel(x,y); let at=y*Int64(header.pitch)+x*4
                unsafe { header.pixels.write(at,c.r); header.pixels.write(at+1,c.g)
                    header.pixels.write(at+2,c.b); header.pixels.write(at+3,c.a) }
            } }
        } finally { unsafe { SDL_UnlockSurface(ptr) } }
    }
}
