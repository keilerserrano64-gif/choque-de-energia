# Lanza el importador de luchadores (tools/slice_sheet.gd) sin tener que escribir la
# ruta de Godot. Uso, desde la carpeta del proyecto:
#   tools\importar.bat --sheet hoja.png --fighter id
#   tools\importar.bat --sheet hoja.png --fighter id --map mapa.json --apply
#   tools\importar.bat --help
# Godot se busca en: variable GODOT, tools\godot_path.txt, y carpetas habituales
# (Escritorio, Descargas, Documentos, Archivos de programa, Temp). La ruta encontrada
# se guarda en tools\godot_path.txt; si es otra, edita ese archivo.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$saved = Join-Path $PSScriptRoot "godot_path.txt"

function Find-Godot {
    if ($env:GODOT -and (Test-Path $env:GODOT)) { return $env:GODOT }
    if (Test-Path $saved) {
        $line = (Get-Content $saved -TotalCount 1).Trim()
        if ($line -and (Test-Path $line)) { return $line }
    }
    $places = @(
        [Environment]::GetFolderPath("Desktop"),
        (Join-Path $env:USERPROFILE "Downloads"),
        [Environment]::GetFolderPath("MyDocuments"),
        (Join-Path $env:USERPROFILE "OneDrive"),
        $env:ProgramFiles, ${env:ProgramFiles(x86)}, "C:\Godot", $env:LOCALAPPDATA, $env:TEMP
    ) | Where-Object { $_ -and (Test-Path $_) }
    $found = @()
    foreach ($place in $places) {
        $found += Get-ChildItem -Path $place -Filter "Godot_v4*win64*.exe" -Recurse -Depth 3 -ErrorAction SilentlyContinue
    }
    if ($found.Count -eq 0) { return $null }
    # Preferir la versión _console (escribe en la terminal) y la más nueva.
    $best = $found | Sort-Object @{ Expression = { $_.Name -like "*_console.exe" }; Descending = $true }, @{ Expression = { $_.Name }; Descending = $true } | Select-Object -First 1
    return $best.FullName
}

$godot = Find-Godot
if (-not $godot) {
    Write-Host "No encuentro Godot 4. Pon su ruta en tools\godot_path.txt (una línea) o en la variable GODOT." -ForegroundColor Red
    exit 1
}
Set-Content -Path $saved -Value $godot -Encoding UTF8

# Sin argumentos (o con --ventana): abre el importador con ventana.
if ($args.Count -eq 0 -or $args[0] -eq "--ventana") {
    $rest = @($args | Select-Object -Skip 1)
    $winArgs = @("--path", "`"$root`"", "res://tools/importador/importador.tscn")
    if ($rest.Count -gt 0) { $winArgs += @("--") + ($rest | ForEach-Object { "`"$_`"" }) }
    Start-Process -FilePath $godot -ArgumentList $winArgs
    Write-Host "Abriendo el importador con ventana..."
    exit 0
}

function Quote([string]$s) { if ($s -match '[\s"]') { return '"' + ($s -replace '"', '\"') + '"' } return $s }
$argList = @("--headless", "--path", $root, "-s", "res://tools/slice_sheet.gd", "--") + @($args | ForEach-Object { "$_" })
# El Godot "con ventana" no escribe en la consola de PowerShell: se redirige a archivos.
$outFile = [System.IO.Path]::GetTempFileName()
$errFile = [System.IO.Path]::GetTempFileName()
$proc = Start-Process -FilePath $godot -ArgumentList (($argList | ForEach-Object { Quote $_ }) -join " ") `
    -NoNewWindow -Wait -PassThru -RedirectStandardOutput $outFile -RedirectStandardError $errFile
$code = $proc.ExitCode
$output = @(Get-Content -Encoding UTF8 $outFile) + @(Get-Content -Encoding UTF8 $errFile | Where-Object { $_ -notmatch "^\s+(at:|GDScript backtrace|\[\d+\])" })
Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
foreach ($line in $output) {
    $text = "$line"
    if ($text -match "^Godot Engine v") { continue }
    if ($text -match "ERROR|AVISO|No se|Falta") { Write-Host $text -ForegroundColor Yellow } else { Write-Host $text }
}
exit $code
