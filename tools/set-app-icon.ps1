param(
    [Parameter(Mandatory=$true)][string]$SourceImage,
    [Parameter(Mandatory=$true)][string]$Executable
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
if (-not ('FirebreakIconResources' -as [type])) {
    # Build-time Windows resource interop only; no helper assembly ships with the app.
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class FirebreakIconResources {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr BeginUpdateResourceW(string path, bool deleteExisting);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool UpdateResourceW(IntPtr handle, IntPtr type, IntPtr name, ushort language, byte[] data, uint size);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool EndUpdateResourceW(IntPtr handle, bool discard);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr LoadLibraryExW(string path, IntPtr file, uint flags);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern IntPtr FindResourceW(IntPtr module, IntPtr name, IntPtr type);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern uint SizeofResource(IntPtr module, IntPtr resource);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern IntPtr LoadResource(IntPtr module, IntPtr resource);
    [DllImport("kernel32.dll")] static extern IntPtr LockResource(IntPtr resource);
    [DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr module);
    static void Check(bool ok) { if (!ok) throw new Win32Exception(Marshal.GetLastWin32Error()); }
    static byte[] Read(IntPtr module, int type, int id) {
        IntPtr found=FindResourceW(module,new IntPtr(id),new IntPtr(type)); Check(found!=IntPtr.Zero);
        byte[] bytes=new byte[checked((int)SizeofResource(module,found))];
        IntPtr data=LockResource(LoadResource(module,found)); Check(data!=IntPtr.Zero);
        Marshal.Copy(data,bytes,0,bytes.Length); return bytes;
    }
    static bool Equal(byte[] a, byte[] b) {
        if (a.Length!=b.Length) return false;
        for(int i=0;i<a.Length;i++) if(a[i]!=b[i]) return false; return true;
    }
    public static void EmbedAndVerify(string executable, byte[] ico) {
        byte[][] images; byte[] group;
        using(var reader=new BinaryReader(new MemoryStream(ico)))
        using(var output=new MemoryStream()) {
            if(reader.ReadUInt16()!=0 || reader.ReadUInt16()!=1) throw new InvalidDataException("Not an ICO file");
            ushort count=reader.ReadUInt16(); images=new byte[count][];
            using(var writer=new BinaryWriter(output)) {
                writer.Write((ushort)0);writer.Write((ushort)1);writer.Write(count);
                for(int i=0;i<count;i++) {
                    reader.BaseStream.Position=6+i*16;
                    writer.Write(reader.ReadBytes(8)); uint length=reader.ReadUInt32(); uint offset=reader.ReadUInt32();
                    writer.Write(length);writer.Write((ushort)(i+1));
                    reader.BaseStream.Position=offset;images[i]=reader.ReadBytes(checked((int)length));
                    if(images[i].Length!=length) throw new InvalidDataException("Truncated ICO image");
                }
                group=output.ToArray();
            }
        }
        IntPtr handle=BeginUpdateResourceW(executable,false); Check(handle!=IntPtr.Zero);
        try {
            for(int i=0;i<images.Length;i++) Check(UpdateResourceW(handle,new IntPtr(3),new IntPtr(i+1),0,images[i],(uint)images[i].Length));
            Check(UpdateResourceW(handle,new IntPtr(14),new IntPtr(1),0,group,(uint)group.Length));
            bool saved=EndUpdateResourceW(handle,false);handle=IntPtr.Zero;Check(saved);
        } finally { if(handle!=IntPtr.Zero) EndUpdateResourceW(handle,true); }
        IntPtr module=LoadLibraryExW(executable,IntPtr.Zero,2); Check(module!=IntPtr.Zero);
        try {
            if(!Equal(group,Read(module,14,1))) throw new InvalidDataException("Executable icon group differs");
            for(int i=0;i<images.Length;i++) if(!Equal(images[i],Read(module,3,i+1))) throw new InvalidDataException("Executable icon image differs");
        } finally { FreeLibrary(module); }
    }
}
'@
}
$sourcePath = (Resolve-Path -LiteralPath $SourceImage).Path
$executablePath = (Resolve-Path -LiteralPath $Executable).Path
$generated = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../assets/generated'))
New-Item -ItemType Directory -Force -Path $generated | Out-Null
$sizes = @(16,24,32,48,64,128,256)
$frames = [Collections.Generic.List[byte[]]]::new()
$source = [Drawing.Image]::FromFile($sourcePath)
try {
    foreach ($size in $sizes) {
        $bitmap = [Drawing.Bitmap]::new($size,$size,[Drawing.Imaging.PixelFormat]::Format32bppArgb)
        try {
            $graphics = [Drawing.Graphics]::FromImage($bitmap)
            try {
                $graphics.CompositingMode = [Drawing.Drawing2D.CompositingMode]::SourceCopy
                $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
                $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::Half
                $graphics.DrawImage($source,[Drawing.Rectangle]::new(0,0,$size,$size),0,0,$source.Width,$source.Height,[Drawing.GraphicsUnit]::Pixel)
            } finally { $graphics.Dispose() }
            $stream = [IO.MemoryStream]::new()
            try { $bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Png); $frames.Add($stream.ToArray()) }
            finally { $stream.Dispose() }
            if ($size -eq 64) { $bitmap.Save((Join-Path $generated 'app-icon-64.png'),[Drawing.Imaging.ImageFormat]::Png) }
        } finally { $bitmap.Dispose() }
    }
} finally { $source.Dispose() }
$stream = [IO.MemoryStream]::new()
$writer = [IO.BinaryWriter]::new($stream)
try {
    $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$sizes.Count)
    $offset = 6 + 16*$sizes.Count
    for ($i=0;$i -lt $sizes.Count;$i++) {
        $writer.Write([byte]($sizes[$i] % 256));$writer.Write([byte]($sizes[$i] % 256))
        $writer.Write([byte]0);$writer.Write([byte]0);$writer.Write([uint16]1);$writer.Write([uint16]32)
        $writer.Write([uint32]$frames[$i].Length);$writer.Write([uint32]$offset);$offset += $frames[$i].Length
    }
    foreach ($frame in $frames) { $writer.Write([byte[]]$frame) }
    $ico = $stream.ToArray()
    [IO.File]::WriteAllBytes((Join-Path $generated 'app.ico'),$ico)
    [FirebreakIconResources]::EmbedAndVerify($executablePath,$ico)
} finally { $writer.Dispose();$stream.Dispose() }
Write-Host 'Oak sapling icon: 16/24/32/48/64/128/256px embedded and verified in executable.'
