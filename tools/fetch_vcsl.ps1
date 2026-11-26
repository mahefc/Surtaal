# Fetches a curated subset of the Versilian Community Sample Library (VCSL, CC0 1.0 - public domain
# dedication, https://github.com/sgossner/VCSL) into assets/samples/ and writes data/instruments/world.json.
# These are real recordings of free instruments (the same kind of sound a free VST sample pack gives you),
# played back by the app's built-in sampler. Plug-in formats (VST/AU) cannot be loaded by Godot or on phones.
# Usage:  powershell -File tools/fetch_vcsl.ps1 [-Project C:\path\to\Surtaal]
param([string]$Project = (Split-Path -Parent $PSScriptRoot), [int]$MaxKB = 4500)

$ErrorActionPreference = "Stop"
$raw = "https://raw.githubusercontent.com/sgossner/VCSL/master/"
$tree = Invoke-RestMethod "https://api.github.com/repos/sgossner/VCSL/git/trees/master?recursive=1"
$files = $tree.tree | Where-Object { $_.type -eq "blob" -and $_.path -like "*.wav" }

$noteIndex = @{ C=0; "C#"=1; D=2; "D#"=3; E=4; F=5; "F#"=6; G=7; "G#"=8; A=9; "A#"=10; B=11 }
function Get-Midi([string]$name) {
    foreach ($tok in ($name -replace "\.wav$","").Split("_")) {
        if ($tok -match "^([A-G]#?)(\d)$") { return 12 * ([int]$Matches[2] + 1) + $noteIndex[$Matches[1]] }
    }
    return -1
}
function Download([string]$path, [string]$destDir) {
    New-Item -ItemType Directory -Force $destDir | Out-Null
    $dest = Join-Path $destDir ($path.Split("/")[-1])
    if (-not (Test-Path $dest)) {
        $url = $raw + (($path.Split("/") | ForEach-Object { [uri]::EscapeDataString($_) }) -join "/")
        Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
    }
    return $dest
}

$A = "Aerophones/"; $C = "Chordophones/"; $E = "Electrophones/"; $I = "Idiophones/"; $M = "Membranophones/Struck Membranophones/"
# id, name, dir, category, family, colour, sustained (loop)?, release, zones, optional: prefer (regex), filter (regex), minmidi
$pitched = @(
    @{ id="ocarina";   name="Ocarina";            dir=$A+"Edge-blown Aerophones/Ocarina, Typical/Sustains/Sus"; cat="World";   family="Whistle flute"; color="#8FD6A4"; loop=$true;  release=0.3;  zones=4; desc="Recorded ceramic ocarina." },
    @{ id="harmonica"; name="Harmonica";          dir=$A+"Free Aerophones/Harmonica-Hohner-Special20-C/Sustains/Normal"; cat="Western"; family="Free reed"; color="#C9CFD8"; loop=$true; release=0.25; zones=4; desc="Recorded Hohner Special 20 harmonica." },
    @{ id="pipe_organ"; name="Pipe Organ";        dir=$A+"Edge-blown Aerophones/Pipe Organ/Loud"; filter="Man3Open"; cat="Keys"; family="Organ"; color="#B8A27A"; loop=$true; release=0.5; zones=4; desc="Recorded pipe organ, open diapason." },
    @{ id="recorder";  name="Recorder";           dir=$A+"Edge-blown Aerophones/Baroque Soprano Recorder/Sustain"; cat="Western"; family="Woodwind"; color="#E6D3A3"; loop=$true; release=0.3; zones=4; desc="Recorded Baroque soprano recorder." },
    @{ id="tenor_sax"; name="Tenor Saxophone";    dir=$A+"Reed Aerophones/Tenor Saxophone/Non-Vibrato"; prefer="_vl2_"; minmidi=36; cat="Western"; family="Reed"; color="#E0A458"; loop=$true; release=0.3; zones=5; desc="Recorded tenor saxophone." },
    @{ id="dan_tranh"; name="Dan Tranh Zither";   dir=$C+"Zithers/Dan Tranh/Normal"; prefer="_f_"; cat="Chinese"; family="Zither"; color="#E58B8B"; loop=$false; release=0.6; zones=5; desc="Recorded Vietnamese zither (like a guzheng)." },
    @{ id="harpsichord"; name="Harpsichord";      dir=$C+"Zithers/Harpsichord, French/Sustains"; minmidi=36; cat="Keys"; family="Keyboard"; color="#C99A6B"; loop=$false; release=0.35; zones=5; desc="Recorded French harpsichord." },
    @{ id="folk_harp"; name="Folk Harp";          dir=$C+"Composite Chordophones/Folk Harp"; prefer="_v2_"; filter="_v2_"; cat="Western"; family="Plucked string"; color="#F0C9E0"; loop=$false; release=0.8; zones=5; desc="Recorded folk harp." },
    @{ id="fm_piano";  name="FM Electric Piano";  dir=$E+"TX81Z/FM Piano"; prefer="_vl2"; minmidi=36; cat="Keys"; family="Electric piano"; color="#A8D8F0"; loop=$false; release=0.5; zones=5; desc="Recorded Yamaha TX81Z FM piano." },
    @{ id="clavisynth"; name="Clavisynth";        dir=$E+"TX81Z/Clavisynth"; prefer="_vl2"; minmidi=36; cat="Keys"; family="Electric keys"; color="#9CE0C8"; loop=$false; release=0.3; zones=4; desc="Recorded Yamaha TX81Z clavinet-like synth." },
    @{ id="kalimba";   name="Kalimba";            dir=$I+"Plucked Idiophones/Kalimba, Kenya"; cat="World"; family="Thumb piano"; color="#E8C07A"; loop=$false; release=0.8; zones=5; desc="Recorded Kenyan kalimba (thumb piano)." },
    @{ id="balafon";   name="Balafon";            dir=$I+"Struck Idiophones/Balafon/Hard Mallet"; prefer="_vl2_"; cat="World"; family="Tuned percussion"; color="#D9A066"; loop=$false; release=0.4; zones=5; desc="Recorded West African wooden xylophone." },
    @{ id="vibraphone"; name="Vibraphone";        dir=$I+"Struck Idiophones/Vibraphone/Hard Mallets"; prefer="_v2_"; cat="Orchestra"; family="Tuned percussion"; color="#9FD3F0"; loop=$false; release=0.8; zones=4; desc="Recorded vibraphone, hard mallets." }
)
# one-shot percussion (a single recorded hit, played at fixed pitch)
$P = "Membranophones/Struck Membranophones/"; $S = "Idiophones/Struck Idiophones/"
$oneshots = @(
    @{ id="darbuka_dum"; name="Darbuka Dum";  file=$P+"Darbuka/Darbuka_1_hit_vl2_rr1.wav"; color="#E07A5F"; desc="Darbuka bass hit." },
    @{ id="darbuka_tek"; name="Darbuka Tek";  file=$P+"Darbuka/Darbuka_3_hit_vl2_rr1.wav"; color="#F2A65A"; desc="Darbuka rim hit." },
    @{ id="frame_drum";  name="Frame Drum";   file=$P+"Frame Drum/HDrumL_Hit_v3_rr1_Sum.wav"; color="#C98B5A"; desc="Large hand frame drum, open hit." },
    @{ id="cajon";       name="Cajon";        file=$S+"Cajon/Cajon_hit1_f_rr1.wav"; color="#D4A373"; desc="Cajon bass hit." },
    @{ id="cajon_slap";  name="Cajon Slap";   file=$S+"Cajon/Cajon_hit3_f_rr1.wav"; color="#E9C46A"; desc="Cajon slap." },
    @{ id="bongo_high";  name="Bongo High";   file=$P+"Bongos/BongoH_Hit1_v2_rr1_Mid.wav"; color="#F4A261"; desc="High bongo hit." },
    @{ id="bongo_low";   name="Bongo Low";    file=$P+"Bongos/BongoL_Hit1_v2_rr1_Mid.wav"; color="#E76F51"; desc="Low bongo hit." },
    @{ id="agogo_high";  name="Agogo High";   file=$S+"Agogo Bells/Agogo_High_v2_rr1_Mid.wav"; color="#F6D55C"; desc="High agogo bell." },
    @{ id="agogo_low";   name="Agogo Low";    file=$S+"Agogo Bells/Agogo_Low_v2_rr1_Mid.wav"; color="#E8B04A"; desc="Low agogo bell." },
    @{ id="woodblock";   name="Woodblock";    file=$S+"Woodblock/wood_click_f_rr1.wav"; color="#C08552"; desc="Woodblock click." },
    @{ id="tambourine";  name="Tambourine";   file=$S+"Tambourine 1/Tamb1_Hit_v2_rr1_Mid.wav"; color="#BFE3FF"; desc="Tambourine hit." },
    @{ id="finger_cymbals"; name="Finger Cymbals"; file=$S+"Finger Cymbals/Fing_Cymb.wav"; color="#D8E2EC"; desc="Finger cymbals ring." }
)

$instruments = @()
foreach ($inst in $pitched) {
    $min = if ($inst.minmidi) { [int]$inst.minmidi } else { 0 }
    $cands = $files | Where-Object { $_.path.StartsWith($inst.dir + "/") -and $_.size -le ($MaxKB * 1KB) -and (-not $inst.filter -or $_.path -match $inst.filter) } |
        ForEach-Object { [pscustomobject]@{ path=$_.path; midi=(Get-Midi $_.path.Split("/")[-1]); size=$_.size } } |
        Where-Object { $_.midi -ge $min } | Sort-Object midi
    if (-not $cands) { Write-Host "  no samples for $($inst.id) ($($inst.dir))"; continue }
    $byPitch = $cands | Group-Object midi | ForEach-Object {
        $g = $_.Group
        if ($inst.prefer) { $pref = $g | Where-Object { $_.path -match $inst.prefer }; if ($pref) { $g = $pref } }
        $g | Select-Object -First 1
    }
    $lo = ($byPitch | Select-Object -First 1).midi; $hi = ($byPitch | Select-Object -Last 1).midi
    $picked = @()
    for ($i = 0; $i -lt $inst.zones; $i++) {
        $target = $lo + ($hi - $lo) * ($i + 0.5) / $inst.zones
        $best = $byPitch | Sort-Object { [math]::Abs($_.midi - $target) } | Select-Object -First 1
        if ($picked.midi -notcontains $best.midi) { $picked += $best }
    }
    $picked = $picked | Sort-Object midi
    $dir = "assets/samples/" + $inst.id
    $zones = @()
    foreach ($s in $picked) {
        Write-Host ("  {0}: {1} ({2:N1} MB)" -f $inst.id, $s.path.Split("/")[-1], ($s.size / 1MB))
        Download $s.path (Join-Path $Project $dir) | Out-Null
        $zones += [ordered]@{ midi = $s.midi; file = "res://$dir/" + $s.path.Split("/")[-1] }
    }
    $instruments += [ordered]@{
        id = $inst.id; name = $inst.name; category = $inst.cat; family = $inst.family; synth = "sampler"; color = $inst.color
        start_midi = [int]($zones[[math]::Floor($zones.Count / 2)].midi); range = @(($zones[0].midi - 4), ($zones[-1].midi + 6))
        description = $inst.desc + " Real recording (VCSL, CC0)."
        params = [ordered]@{ samples = $zones; loop = $inst.loop; release = $inst.release }
    }
}
foreach ($inst in $oneshots) {
    if (-not ($files | Where-Object { $_.path -eq $inst.file })) { Write-Host "  missing: $($inst.file)"; continue }
    $dir = "assets/samples/" + $inst.id
    Write-Host ("  {0}: {1}" -f $inst.id, $inst.file.Split("/")[-1])
    Download $inst.file (Join-Path $Project $dir) | Out-Null
    $instruments += [ordered]@{
        id = $inst.id; name = $inst.name; category = "World"; family = "Percussion"; synth = "sampler"; color = $inst.color
        start_midi = 48; range = @(36, 60); description = $inst.desc + " Real recording (VCSL, CC0)."
        params = [ordered]@{ samples = @([ordered]@{ midi = 48; file = "res://$dir/" + $inst.file.Split("/")[-1] }); loop = $false; fixed = $true }
    }
}
$out = [ordered]@{ version = 1; license_note = "Recorded samples from the Versilian Community Sample Library (VCSL) by Versilian Studios, released under CC0 1.0 (public domain dedication). https://github.com/sgossner/VCSL"; instruments = $instruments }
$json = $out | ConvertTo-Json -Depth 8
Set-Content -Path (Join-Path $Project "data/instruments/world.json") -Value $json -Encoding UTF8
Write-Host "Wrote world.json with $($instruments.Count) instruments."
