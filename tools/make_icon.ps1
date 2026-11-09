# Ярлык игры «В РИНГЕ»: рисуем PNG 256 и собираем многоразмерный .ico.
# Запуск из папки games\boxing3d:
#   powershell -NoProfile -ExecutionPolicy Bypass -Command "$c = Get-Content -Raw -Encoding UTF8 tools\make_icon.ps1; Invoke-Expression $c"
Add-Type -AssemblyName System.Drawing

$root = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
$sizes = @(256, 128, 64, 48, 32, 24, 16)
$big = 1024

function New-GloveBitmap([int]$S) {
    $bmp = New-Object System.Drawing.Bitmap($S, $S, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.Clear([System.Drawing.Color]::Transparent)
    $k = $S / 1024.0
    $g.ScaleTransform($k, $k)

    # фон: тёмный зал, скруглённый квадрат
    $rr = 190.0
    $bgPath = New-Object System.Drawing.Drawing2D.GraphicsPath
    $bgPath.AddArc(0, 0, 2*$rr, 2*$rr, 180, 90)
    $bgPath.AddArc(1024 - 2*$rr, 0, 2*$rr, 2*$rr, 270, 90)
    $bgPath.AddArc(1024 - 2*$rr, 1024 - 2*$rr, 2*$rr, 2*$rr, 0, 90)
    $bgPath.AddArc(0, 1024 - 2*$rr, 2*$rr, 2*$rr, 90, 90)
    $bgPath.CloseFigure()
    $g.FillPath((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 10, 15, 26))), $bgPath)
    $g.SetClip($bgPath)

    $bgGrad = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(0, 0)), (New-Object System.Drawing.Point(1024, 1024)),
        [System.Drawing.Color]::FromArgb(255, 24, 36, 60), [System.Drawing.Color]::FromArgb(255, 4, 6, 11))
    $g.FillRectangle($bgGrad, 0, 0, 1024, 1024)
    $bgGrad.Dispose()

    # канаты ринга: три полосы в глубине
    $ropeCols = @(
        [System.Drawing.Color]::FromArgb(150, 198, 42, 48),
        [System.Drawing.Color]::FromArgb(120, 232, 236, 246),
        [System.Drawing.Color]::FromArgb(150, 58, 96, 168))
    $ys = @(646, 710, 774)
    for ($i = 0; $i -lt 3; $i++) {
        $pen = New-Object System.Drawing.Pen($ropeCols[$i], 16)
        $g.DrawLine($pen, -60, $ys[$i], 1084, $ys[$i] + 26)
        $pen.Dispose()
    }

    $g.ResetClip()

    # рамка по краю
    $border = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(210, 242, 193, 75), 14)
    $g.DrawPath($border, $bgPath)
    $border.Dispose()

    # --- перчатка: наклоняем и рисуем в локальных координатах
    $state = $g.Save()
    $g.TranslateTransform(512, 470)
    $g.RotateTransform(-16)

    $redLight = [System.Drawing.Color]::FromArgb(255, 236, 92, 82)
    $redDark = [System.Drawing.Color]::FromArgb(255, 150, 30, 34)
    $cuffCol = [System.Drawing.Color]::FromArgb(255, 112, 24, 28)
    $lineCol = [System.Drawing.Color]::FromArgb(255, 66, 12, 14)

    # манжета и полоса липучки
    $cuff = New-Object System.Drawing.Drawing2D.GraphicsPath
    $cuff.AddArc(-176, 176, 352, 120, 180, 180)
    $cuff.AddArc(-176, 322, 352, 150, 0, 180)
    $cuff.CloseFigure()
    $g.FillPath((New-Object System.Drawing.SolidBrush($cuffCol)), $cuff)
    $cuffBand = New-Object System.Drawing.Drawing2D.GraphicsPath
    $cuffBand.AddArc(-176, 196, 352, 100, 180, 180)
    $cuffBand.AddArc(-176, 250, 352, 110, 0, 180)
    $cuffBand.CloseFigure()
    $g.FillPath((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 196, 46, 46))), $cuffBand)

    # кулак и большой палец одним силуэтом
    $fist = New-Object System.Drawing.Drawing2D.GraphicsPath
    $fist.AddEllipse(-232, -226, 464, 428)
    $thumb = New-Object System.Drawing.Drawing2D.GraphicsPath
    $thumb.AddEllipse(-306, 6, 186, 226)
    $silhouette = New-Object System.Drawing.Drawing2D.GraphicsPath
    $silhouette.AddEllipse(-232, -226, 464, 428)
    $silhouette.AddEllipse(-306, 6, 186, 226)
    $g.FillPath((New-Object System.Drawing.SolidBrush($redDark)), $silhouette)

    # мягкий объём: свет сверху-слева
    $shade = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(-232, -226)), (New-Object System.Drawing.Point(232, 264)),
        $redLight, $redDark)
    $g.FillPath($shade, $silhouette)
    $shade.Dispose()

    # шов между пальцем и кулаком
    $seam = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150, 60, 10, 12), 9)
    $g.DrawArc($seam, -150, -20, 330, 300, 150, 70)
    $seam.Dispose()

    # блик
    $hl = New-Object System.Drawing.Drawing2D.GraphicsPath
    $hl.AddEllipse(-150, -170, 230, 118)
    $hlBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.Point(-150, -170)), (New-Object System.Drawing.Point(80, -52)),
        [System.Drawing.Color]::FromArgb(165, 255, 238, 232), [System.Drawing.Color]::FromArgb(0, 255, 238, 232))
    $g.FillPath($hlBrush, $hl)
    $hlBrush.Dispose()

    # обводка силуэта
    $outline = New-Object System.Drawing.Pen($lineCol, 16)
    $g.DrawPath($outline, $silhouette)
    $outline.Dispose()

    $g.Restore($state)
    $g.Dispose()
    return $bmp
}

$tmp = [System.IO.Path]::GetTempPath() + "ring_icon_1024.png"
$master = New-GloveBitmap $big
$master.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
$master.Dispose()

$img = [System.Drawing.Image]::FromFile($tmp)

# PNG для окна игры
$iconPng = Join-Path $root "icon.png"
$b = New-Object System.Drawing.Bitmap(256, 256)
$gb = [System.Drawing.Graphics]::FromImage($b)
$gb.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gb.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$gb.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$gb.Clear([System.Drawing.Color]::Transparent)
$gb.DrawImage($img, 0, 0, 256, 256)
$gb.Dispose()
$b.Save($iconPng, [System.Drawing.Imaging.ImageFormat]::Png)
$b.Dispose()

# ICO: заголовок + PNG-кадры каждого размера
$frames = @()
foreach ($s in $sizes) {
    $bb = New-Object System.Drawing.Bitmap($s, $s)
    $gg = [System.Drawing.Graphics]::FromImage($bb)
    $gg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $gg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $gg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $gg.Clear([System.Drawing.Color]::Transparent)
    $gg.DrawImage($img, 0, 0, $s, $s)
    $gg.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bb.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $frames += ,@($s, $ms.ToArray())
    $ms.Dispose()
    $bb.Dispose()
}
$img.Dispose()

$icoPath = Join-Path $root "icon.ico"
$fs = [System.IO.File]::Create($icoPath)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([UInt16]0)
$bw.Write([UInt16]1)
$bw.Write([UInt16]$frames.Count)
$offset = 6 + 16 * $frames.Count
foreach ($f in $frames) {
    $s = [int]$f[0]
    $data = [byte[]]$f[1]
    $dim = if ($s -ge 256) { 0 } else { $s }
    $bw.Write([byte]$dim)
    $bw.Write([byte]$dim)
    $bw.Write([byte]0)
    $bw.Write([byte]0)
    $bw.Write([UInt16]1)
    $bw.Write([UInt16]32)
    $bw.Write([UInt32]$data.Length)
    $bw.Write([UInt32]$offset)
    $offset += $data.Length
}
foreach ($f in $frames) { $bw.Write([byte[]]$f[1]) }
$bw.Flush(); $bw.Dispose(); $fs.Dispose()

Remove-Item $tmp -ErrorAction SilentlyContinue
"PNG: $iconPng"
"ICO: $icoPath (кадры: $($sizes -join ', '))"
