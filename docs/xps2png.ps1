param(
    [Parameter(Mandatory=$true)][string]$Xps,
    [Parameter(Mandatory=$true)][string]$OutDir,
    [int]$MaxPages = 4,
    [int]$Dpi = 120
)
# Render XPS pages to PNG through the document paginator.
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName ReachFramework

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$path = (Resolve-Path $Xps).Path
$doc = New-Object System.Windows.Xps.Packaging.XpsDocument($path, [System.IO.FileAccess]::Read)
$seq = $doc.GetFixedDocumentSequence()
$pag = $seq.DocumentPaginator
$size = $pag.PageSize
Write-Output ("pages={0}  pagesize={1}x{2}" -f $pag.PageCount, $size.Width, $size.Height)

$scale = $Dpi / 96.0
$n = [Math]::Min($MaxPages, $pag.PageCount)
for ($i = 0; $i -lt $n; $i++) {
    $page = $pag.GetPage($i)
    $vis = $page.Visual
    if ($null -eq $vis) {
        Write-Output ("page {0}: visual is null, skipped" -f ($i + 1))
        continue
    }
    $w = [int]($size.Width * $scale)
    $h = [int]($size.Height * $scale)
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($w, $h, $Dpi, $Dpi, [System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($vis)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $file = Join-Path $OutDir ("p{0:D2}.png" -f ($i + 1))
    $fs = [System.IO.File]::Create($file)
    $enc.Save($fs)
    $fs.Close()
    Write-Output ("wrote {0}  ({1}x{2})" -f $file, $w, $h)
}
$doc.Close()
