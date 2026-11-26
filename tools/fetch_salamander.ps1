# Downloads the Salamander Grand Piano (CC-BY 3.0, Alexander Holm, https://github.com/sfzinstruments/SalamanderGrandPiano)
# FLAC takes for four of its sixteen velocity layers (v2, v6, v10, v14) into assets/samples/salamander_grand/.
# Then run tools/fetch_salamander.py to decode them to WAV and merge the instrument into data/instruments/sampled.json.
param([string]$Project = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = "Stop"
$repo = "sfzinstruments/SalamanderGrandPiano"
$keep = @(2, 6, 10, 14)
$dest = Join-Path $Project "assets/samples/salamander_grand"
New-Item -ItemType Directory -Force $dest | Out-Null

$branch = (Invoke-RestMethod "https://api.github.com/repos/$repo").default_branch
$tree = Invoke-RestMethod "https://api.github.com/repos/$repo/git/trees/${branch}?recursive=1"
$takes = $tree.tree | Where-Object { $_.type -eq "blob" -and $_.path -like "Samples/*.flac" }
$n = 0
foreach ($t in $takes) {
    $name = $t.path.Split("/")[-1]
    if ($name -notmatch "v(\d+)\.flac$") { continue }
    if ($keep -notcontains [int]$Matches[1]) { continue }
    $n++
    $name = $name -replace "#", "s"  # D#1 -> Ds1: keeps '#' out of res:// paths
    $out = Join-Path $dest $name
    $wav = Join-Path $dest (($name -replace "\.flac$", "") + ".wav")
    if (-not (Test-Path $wav) -and -not (Test-Path $out)) {
        # '#' in names like D#1v2.flac must be percent-encoded or it is read as a URL fragment
        $url = "https://raw.githubusercontent.com/$repo/$branch/" + (($t.path.Split("/") | ForEach-Object { [uri]::EscapeDataString($_) }) -join "/")
        try { Invoke-WebRequest -Uri $url -OutFile $out -UseBasicParsing }
        catch { Write-Host "  failed: $name ($($_.Exception.Message))"; if (Test-Path $out) { Remove-Item $out } }
    }
}
Write-Host "Salamander takes available: $n"
