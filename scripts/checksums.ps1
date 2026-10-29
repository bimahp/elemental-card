# checksums.ps1: one line per src/ script, "<Studio path> <class> <enabled> <bytes> <fnv1a32>",
# the same format scripts/studio/studio-checksums.luau prints in Studio.
# With -StudioFile (that script's saved result), compares the two and lists every difference.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/checksums.ps1 [-StudioFile <saved result>]
param([string]$StudioFile = '')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$srcRoot = Join-Path $repo 'src'

$repoLines = Get-ChildItem -Path $srcRoot -Recurse -File -Filter '*.luau' | Sort-Object FullName | ForEach-Object {
	$relative = $_.FullName.Substring($srcRoot.Length + 1) -replace '\\', '/'
	$enabled = 'true'
	if ($relative -match '\.disabled\.') { $enabled = 'false'; $relative = $relative -replace '\.disabled\.', '.' }
	$class = 'ModuleScript'
	if ($relative -match '\.server\.luau$') { $class = 'Script' }
	elseif ($relative -match '\.client\.luau$') { $class = 'LocalScript' }
	$relative = $relative -replace '\.(server|client)\.luau$', '' -replace '\.luau$', ''
	$bytes = [System.IO.File]::ReadAllBytes($_.FullName)
	[uint64]$hash = 2166136261
	foreach ($b in $bytes) {
		$hash = $hash -bxor $b
		$hash = ($hash * 16777619) % 4294967296
	}
	'{0} {1} {2} {3} {4}' -f ($relative -replace '/', '.'), $class, $enabled, $bytes.Length, $hash
}

if ($StudioFile -eq '') { $repoLines; return }

$raw = [System.IO.File]::ReadAllText($StudioFile, [System.Text.Encoding]::UTF8)
if ($raw.TrimStart().StartsWith('[')) {
	$raw = ((ConvertFrom-Json $raw) | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join ''
}
$studioLines = $raw -split "`n" | Where-Object { $_ -match '^\S+ \S+ (true|false) \d+ \d+$' }
$s = @{}; foreach ($l in $studioLines) { $p = $l.Split(' ', 2); $s[$p[0]] = $p[1] }
$r = @{}; foreach ($l in $repoLines) { $p = $l.Split(' ', 2); $r[$p[0]] = $p[1] }
"studio $($s.Count) repo $($r.Count)"
$diff = 0
foreach ($k in ($r.Keys | Sort-Object)) {
	if (-not $s.ContainsKey($k)) { "MISSING in Studio: $k"; $diff++ }
	elseif ($s[$k] -ne $r[$k]) { "DIFF: $k repo=[$($r[$k])] studio=[$($s[$k])]"; $diff++ }
}
foreach ($k in ($s.Keys | Sort-Object)) { if (-not $r.ContainsKey($k)) { "Studio only: $k"; $diff++ } }
"differences: $diff"
