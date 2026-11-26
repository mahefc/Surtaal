# Fetches real tabla strokes (CC0 1.0, recorded by dio-333 on Freesound, packaged in the
# "mercury" project: https://github.com/tmhglnd/mercury) into assets/samples/ and writes
# data/instruments/indian_real.json.
# Usage:  powershell -File tools/fetch_tabla.ps1 [-Project C:\path\to\Surtaal]
param([string]$Project = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = "Stop"
$raw = "https://raw.githubusercontent.com/tmhglnd/mercury/master/mercury_ide/media/samples/drums/tabla/"
$strokes = @(
    @{ id="tabla_na";   name="Tabla Na";   file="tabla_hi.wav";       color="#FF9F43"; desc="Tabla: Na, the sharp ring on the right drum." },
    @{ id="tabla_naop"; name="Tabla Na (open)"; file="tabla_hi_long.wav"; color="#FFB26B"; desc="Tabla: open Na, a longer ring." },
    @{ id="tabla_tun";  name="Tabla Tun";  file="tabla_mid_long.wav"; color="#FF7B54"; desc="Tabla: Tun, the deep pitched stroke on the right drum." },
    @{ id="tabla_te";   name="Tabla Te";   file="tabla_mid.wav";      color="#F08A5D"; desc="Tabla: Te, a dry tap." },
    @{ id="tabla_ghe";  name="Tabla Ghe";  file="tabla_lo_long.wav";  color="#E9967A"; desc="Tabla: Ghe, the bending bass on the left drum." },
    @{ id="tabla_ke";   name="Tabla Ke";   file="tabla_lo_short.wav"; color="#E07A5F"; desc="Tabla: Ke, a short slap on the left drum." }
)
$instruments = @()
foreach ($s in $strokes) {
    $dir = "assets/samples/" + $s.id
    New-Item -ItemType Directory -Force (Join-Path $Project $dir) | Out-Null
    $dest = Join-Path $Project ($dir + "/" + $s.file)
    if (-not (Test-Path $dest)) { Invoke-WebRequest -Uri ($raw + $s.file) -OutFile $dest -UseBasicParsing }
    Write-Host ("  {0}: {1}" -f $s.id, $s.file)
    $instruments += [ordered]@{
        id = $s.id; name = $s.name; category = "Indian"; family = "Hand drum"; synth = "sampler"; color = $s.color
        start_midi = 48; range = @(36, 60); description = $s.desc + " Real recording (CC0)."
        params = [ordered]@{ samples = @([ordered]@{ midi = 48; file = "res://$dir/" + $s.file }); loop = $false; fixed = $true }
    }
}
$out = [ordered]@{ version = 1; license_note = "Tabla strokes recorded by dio-333 (Freesound), released under CC0 1.0, as packaged in https://github.com/tmhglnd/mercury"; instruments = $instruments }
Set-Content -Path (Join-Path $Project "data/instruments/indian_real.json") -Value ($out | ConvertTo-Json -Depth 8) -Encoding UTF8
Write-Host "Wrote indian_real.json with $($instruments.Count) instruments."
