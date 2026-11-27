# Fetches VSCO 2 Community Edition (CC0 1.0 - public domain dedication,
# https://github.com/sgossner/VSCO-2-CE) into assets/samples/ and writes data/instruments/sampled.json.
# Every recorded pitch is kept, and every velocity layer (v1 soft, v2 loud; the upright piano's mf / f).
# Usage:  powershell -File tools/fetch_samples.ps1 -Project C:\path\to\Surtaal
param([string]$Project = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = "Stop"
$raw = "https://raw.githubusercontent.com/sgossner/VSCO-2-CE/master/"
$tree = Invoke-RestMethod "https://api.github.com/repos/sgossner/VSCO-2-CE/git/trees/master?recursive=1"
$files = $tree.tree | Where-Object { $_.type -eq "blob" -and $_.path -like "*.wav" }

$noteIndex = @{ C=0; "C#"=1; D=2; "D#"=3; E=4; F=5; "F#"=6; G=7; "G#"=8; A=9; "A#"=10; B=11 }
function Get-Midi([string]$name) {
    foreach ($tok in ($name -replace "\.wav$","").Split("_")) {
        if ($tok -match "^([A-G]#?)(\d)$") { return 12 * ([int]$Matches[2] + 1) + $noteIndex[$Matches[1]] }
    }
    if ($name -match "_(\d{2,3})\.wav$") { return [int]$Matches[1] }
    return -1
}

# id, display name, folder, family, colour, sustained(loop)?, release, description.
# dyn: the upright piano's dynamics, mapped to velocity layers (mf = soft layer, f = loud layer).
$pitched = @(
    @{ id="violins"; name="Violin Section"; dir="Strings/Violin Section/susVib"; family="String section"; color="#9AA8FF"; release=0.7; desc="Recorded violin section, sustained with vibrato." },
    @{ id="cellos";  name="Cello Section";  dir="Strings/Cello Section/susvib";  family="String section"; color="#7C8CF0"; release=0.7; desc="Recorded cello section, sustained with vibrato." },
    @{ id="horn";    name="French Horn";    dir="Brass/F Horn/sus";              family="Brass";          color="#E8B04A"; release=0.45; desc="Recorded French horn, sustained." },
    @{ id="trumpet"; name="Trumpet";        dir="Brass/Trumpet/susvib";          family="Brass";          color="#F2C75C"; release=0.35; desc="Recorded trumpet, sustained with vibrato." },
    @{ id="tuba";    name="Tuba";           dir="Brass/Tuba/sus";                family="Brass";          color="#D9902F"; release=0.45; desc="Recorded tuba: the deep foundation of a brass section." },
    @{ id="flute";   name="Flute";          dir="Woodwinds/Flute/susvib";        family="Woodwind";       color="#7FD1C7"; release=0.3;  desc="Recorded concert flute, sustained with vibrato." },
    @{ id="grand_piano"; name="Acoustic Piano"; dir="Keys/Upright Nr1"; family="Piano"; color="#D8D2C4"; release=0.5; loop=$false; cat="Keys"; dyn=@{ mf=0; f=1 }; desc="Recorded upright piano, two dynamics." },
    @{ id="harp_real"; name="Concert Harp"; dir="Strings/Harp"; family="Plucked string"; color="#E8C9F0"; release=0.8; loop=$false; desc="Recorded concert harp." },
    @{ id="solo_violin"; name="Solo Violin"; dir="Strings/Solo Violin/Arco Vib"; family="Solo string"; color="#B8C4FF"; release=0.5; desc="Recorded solo violin, arco with vibrato." },
    @{ id="violas"; name="Viola Section"; dir="Strings/Viola Section/susvib"; family="String section"; color="#8C9CF5"; release=0.7; desc="Recorded viola section, sustained with vibrato." },
    @{ id="contrabass"; name="Solo Double Bass"; dir="Strings/Solo Contrabass/SusVib"; family="Solo string"; color="#6C78D8"; release=0.6; desc="Recorded solo double bass, sustained." },
    @{ id="trombone"; name="Tenor Trombone"; dir="Brass/Tenor Trombone/sus"; family="Brass"; color="#E6A23C"; release=0.4; desc="Recorded tenor trombone, sustained." },
    @{ id="oboe"; name="Oboe"; dir="Woodwinds/Oboe/Vib"; family="Woodwind"; color="#79C9A8"; release=0.3; desc="Recorded oboe with vibrato." },
    @{ id="clarinet"; name="Clarinet"; dir="Woodwinds/Clarinet/susLong"; family="Woodwind"; color="#6FBFB0"; release=0.3; desc="Recorded clarinet, long sustain." },
    @{ id="bassoon"; name="Bassoon"; dir="Woodwinds/Bassoon/vib"; family="Woodwind"; color="#5FAF9A"; release=0.35; desc="Recorded bassoon with vibrato." },
    @{ id="marimba"; name="Marimba"; dir="Percussion/Marimba"; family="Tuned percussion"; color="#E58B5A"; release=0.4; loop=$false; desc="Recorded marimba." },
    @{ id="glockenspiel"; name="Glockenspiel"; dir="Percussion/Glock"; family="Tuned percussion"; color="#BFE3FF"; release=0.6; loop=$false; desc="Recorded glockenspiel." },
    @{ id="xylophone"; name="Xylophone"; dir="Percussion/Xylo"; family="Tuned percussion"; color="#F0B27A"; release=0.3; loop=$false; desc="Recorded xylophone." }
)
$oneshots = @(
    @{ id="bassdrum"; name="Bass Drum";  file="Percussion/BDrumNewhit_v5_rr1_Sum.wav"; color="#FF5A5F"; desc="Concert bass drum hit." },
    @{ id="snare_real"; name="Snare (orchestral)"; file="Percussion/Snare2-HitSN_v5_rr1_Sum.wav"; color="#FFD93D"; desc="Orchestral snare hit." },
    @{ id="gong";    name="Gong";        file="Percussion/gongHit_mf.wav"; color="#C9A24A"; desc="Large gong, mf." },
    @{ id="cymbal";  name="Crash Cymbal"; file="Percussion/cymbal-crash1_mf_rr1.wav"; color="#BFC9D4"; desc="Orchestral crash cymbal." },
    @{ id="conga";   name="Conga";       file="Percussion/Conga-HitN_v2_rr1_Sum.wav"; color="#FF9266"; desc="Open conga hit." }
)

function Download([string]$path, [string]$destDir) {
    New-Item -ItemType Directory -Force $destDir | Out-Null
    $dest = Join-Path $destDir ($path.Split("/")[-1])
    if (-not (Test-Path $dest)) {
        $url = $raw + (($path.Split("/") | ForEach-Object { [uri]::EscapeDataString($_) }) -join "/")
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    }
    return $dest
}

$instruments = @()
foreach ($inst in $pitched) {
    # every wav in the folder with a readable pitch; the velocity layer comes from _v1 / _v2 or the dynamic
    $cands = @()
    foreach ($f in ($files | Where-Object { $_.path.StartsWith($inst.dir + "/") } | Sort-Object path)) {
        $name = $f.path.Split("/")[-1]
        $midi = Get-Midi $name
        if ($midi -lt 0) { continue }
        # round robins: keep take 1 only (the others are the same note played again)
        if ($name -match "(?i)rr(\d+)" -and $Matches[1] -ne "1") { continue }
        $layer = 0
        if ($name -match "_v(\d+)") { $layer = [int]$Matches[1] - 1 }
        elseif ($inst.dyn -and ($name -match "_(mf|f)_")) { $layer = [int]$inst.dyn[$Matches[1]] }
        $cands += [pscustomobject]@{ path=$f.path; name=$name; midi=$midi; layer=$layer }
    }
    # one take per (layer, pitch)
    $picked = $cands | Group-Object layer, midi | ForEach-Object { $_.Group | Select-Object -First 1 } | Sort-Object layer, midi
    if (-not $picked) { Write-Host "  no files for $($inst.id) in $($inst.dir)"; continue }
    # renumber the layers the folder actually has to 0..n-1 (a gap would leave a velocity range silent)
    $map = @{}; $n = 0
    foreach ($l in ($picked | ForEach-Object { $_.layer } | Sort-Object -Unique)) { $map[$l] = $n; $n++ }
    foreach ($s in $picked) { $s.layer = $map[$s.layer] }
    $dir = "assets/samples/" + $inst.id
    $zones = @()
    foreach ($s in $picked) {
        Write-Host ("  {0}: {1} (layer {2})" -f $inst.id, $s.name, $s.layer)
        Download $s.path (Join-Path $Project $dir) | Out-Null
        $zones += [ordered]@{ midi = $s.midi; vel = $s.layer; file = "res://$dir/" + $s.name }
    }
    $midis = @($zones | ForEach-Object { [int]$_.midi } | Sort-Object)
    $instruments += [ordered]@{
        id = $inst.id; name = $inst.name; category = $(if ($inst.cat) { $inst.cat } else { "Orchestra" }); family = $inst.family; synth = "sampler"; color = $inst.color
        start_midi = $midis[[math]::Floor($midis.Count / 2)]; range = @(($midis[0] - 4), ($midis[-1] + 6))
        description = $inst.desc + " Real recording (VSCO 2 CE, CC0)."
        params = [ordered]@{ samples = $zones; loop = $(if ($inst.ContainsKey("loop")) { $inst.loop } else { $true }); release = $inst.release }
    }
}

foreach ($inst in $oneshots) {
    if (-not ($files | Where-Object { $_.path -eq $inst.file })) { Write-Host "  missing: $($inst.file)"; continue }
    $dir = "assets/samples/" + $inst.id
    Write-Host ("  {0}: {1}" -f $inst.id, $inst.file.Split("/")[-1])
    Download $inst.file (Join-Path $Project $dir) | Out-Null
    $instruments += [ordered]@{
        id = $inst.id; name = $inst.name; category = "Orchestra"; family = "Percussion"; synth = "sampler"; color = $inst.color
        start_midi = 48; range = @(36, 60); description = $inst.desc + " Real recording (VSCO 2 CE, CC0)."
        params = [ordered]@{ samples = @([ordered]@{ midi = 48; vel = 0; file = "res://$dir/" + $inst.file.Split("/")[-1] }); loop = $false; fixed = $true }
    }
}
$out = [ordered]@{ version = 1; license_note = "Recorded samples from VSCO 2 Community Edition by Sam Gossner, released under CC0 1.0 (public domain dedication). https://github.com/sgossner/VSCO-2-CE"; instruments = $instruments }
$json = $out | ConvertTo-Json -Depth 8
# UTF-8 without a byte-order mark (Godot's JSON parser rejects a BOM)
[System.IO.File]::WriteAllText((Join-Path $Project "data/instruments/sampled.json"), $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "Wrote sampled.json with $($instruments.Count) instruments."
