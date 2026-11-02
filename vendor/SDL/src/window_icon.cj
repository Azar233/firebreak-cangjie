package sdl

foreign { func SDL_SetWindowIcon(window: CPointer<Unit>,icon: CPointer<Unit>): Bool }

extend SdlWindow {
    /** Sets the native window/taskbar icon. The caller retains the surface and
     * may close it after this call. Must run on the window's owning thread. */
    public func setIcon(icon: Surface): Unit {
        renderer.ensureRenderAccess("set SdlWindow icon")
        if(icon.isClosed()){throw SdlException("Cannot use a closed icon surface")}
        ensureSdl(unsafe{SDL_SetWindowIcon(windowPtr,icon.ptr)},"SDL_SetWindowIcon")
    }
}
