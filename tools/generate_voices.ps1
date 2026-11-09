# Genera las voces de los luchadores (assets/voices/<luchador>/<frase>_<n>.wav)
# con las voces en español de Windows (Microsoft Raul y Microsoft Sabina, es-MX).
# Uso (PowerShell, desde la carpeta del proyecto):
#   powershell -ExecutionPolicy Bypass -File tools\generate_voices.ps1
#   python tools\trim_voices.py
# Las frases, el tono y la velocidad de cada luchador están en tools\voice_lines.json.

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$data = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot "voice_lines.json") | ConvertFrom-Json
$outDir = Join-Path $root "assets\voices"

Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.DataReader, Windows.Storage.Streams, ContentType = WindowsRuntime]
$asTask = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq "AsTask" -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]

function Await($operation, [Type]$resultType) {
    $task = $asTask.MakeGenericMethod($resultType).Invoke($null, @($operation))
    $task.Wait(-1) | Out-Null
    return $task.Result
}

$synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
$voices = @{}
foreach ($v in [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices) {
    if ($v.Language -like "es-*") { $voices[$v.DisplayName -replace "^Microsoft ", ""] = $v }
}

$count = 0
foreach ($fighterProp in $data.fighters.PSObject.Properties) {
    $id = $fighterProp.Name
    $cfg = $fighterProp.Value
    $voiceName = [string]$cfg.voice
    if (-not $voices.ContainsKey($voiceName)) { throw "Falta la voz de Windows '$voiceName'." }
    $synth.Voice = $voices[$voiceName]
    $dir = Join-Path $outDir $id
    New-Item -ItemType Directory -Force $dir | Out-Null
    foreach ($lineProp in $cfg.lines.PSObject.Properties) {
        $i = 0
        foreach ($text in $lineProp.Value) {
            $safe = [System.Security.SecurityElement]::Escape([string]$text)
            $ssml = "<speak version=`"1.0`" xmlns=`"http://www.w3.org/2001/10/synthesis`" xml:lang=`"es-MX`">" +
                "<prosody pitch=`"$($cfg.pitch)`" rate=`"$($cfg.rate)`">$safe</prosody></speak>"
            $stream = Await ($synth.SynthesizeSsmlToStreamAsync($ssml)) ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream])
            $reader = New-Object Windows.Storage.Streams.DataReader($stream.GetInputStreamAt(0))
            $size = [uint32]$stream.Size
            $null = Await ($reader.LoadAsync($size)) ([uint32])
            $bytes = New-Object byte[] $size
            $reader.ReadBytes($bytes)
            $path = Join-Path $dir ("{0}_{1}.wav" -f $lineProp.Name, $i)
            [System.IO.File]::WriteAllBytes($path, $bytes)
            $reader.Dispose()
            $stream.Dispose()
            $i++
            $count++
        }
    }
}
Write-Output "Generadas $count frases en $outDir"
