# pull-sources.ps1: writes Studio's scripts into src/ from saved pull-sources.luau results.
# Pass every chunk's saved result file, in order. See scripts/README.md.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/pull-sources.ps1 <chunk1> <chunk2> ...
param([Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)][string[]]$Files)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$srcRoot = Join-Path $repo 'src'
$utf8 = New-Object System.Text.UTF8Encoding($false)

# The MCP saves a large result as plain text or as a JSON array of {type, text} blocks.
function Read-Result([string]$path) {
	$raw = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
	if ($raw.TrimStart().StartsWith('[')) {
		$raw = ((ConvertFrom-Json $raw) | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join ''
	}
	return $raw
}

$text = New-Object System.Text.StringBuilder
$expected = 1
$total = -1
foreach ($file in $Files) {
	$raw = Read-Result $file
	$m = [regex]::Match($raw, '^#chunk (\d+) (\d+) (\d+) scripts=(\d+)( chunks=\d+)?\n')
	if (-not $m.Success) { throw "$file is not a pull-sources chunk" }
	$from = [int]$m.Groups[1].Value; $to = [int]$m.Groups[2].Value; $total = [int]$m.Groups[3].Value
	if ($from -ne $expected) { throw "$file starts at byte $from, expected $expected" }
	$body = $raw.Substring($m.Length)
	$end = $body.IndexOf("`n#end`n")
	if ($end -lt 0) { throw "$file has no #end marker (truncated)" }
	$body = $body.Substring(0, $end)
	if ($utf8.GetByteCount($body) -ne ($to - $from + 1)) { throw "$file holds $($utf8.GetByteCount($body)) bytes, header says $($to - $from + 1)" }
	[void]$text.Append($body)
	$expected = $to + 1
}
if ($expected -ne $total + 1) { throw "chunks end at byte $($expected - 1) of $total; pull the rest" }

$bytes = $utf8.GetBytes($text.ToString())
$pos = 0
$written = @{}
while ($pos -lt $bytes.Length) {
	$nl = [Array]::IndexOf($bytes, [byte]10, $pos)
	$header = $utf8.GetString($bytes, $pos, $nl - $pos)
	$m = [regex]::Match($header, '^=== (\S+) (\S+) (true|false) (\d+)$')
	if (-not $m.Success) { throw "bad header at byte ${pos}: $header" }
	$path = $m.Groups[1].Value; $class = $m.Groups[2].Value; $enabled = $m.Groups[3].Value; $length = [int]$m.Groups[4].Value
	$start = $nl + 1
	if ($bytes[$start + $length] -ne 10) { throw "source of $path does not end where its length says" }

	$suffix = switch ($class) {
		'Script' { '.server.luau' }
		'LocalScript' { '.client.luau' }
		'ModuleScript' { '.luau' }
		default { throw "unsupported script class $class at $path" }
	}
	if ($enabled -eq 'false') { $suffix = '.disabled' + $suffix }
	$parts = $path.Split('.')
	$dir = Join-Path $srcRoot (($parts[0..($parts.Length - 2)]) -join '\')
	$file = Join-Path $dir ($parts[-1] + $suffix)
	[void](New-Item -ItemType Directory -Force -Path $dir)
	$source = New-Object byte[] $length
	[Array]::Copy($bytes, $start, $source, 0, $length)
	[System.IO.File]::WriteAllBytes($file, $source)
	$written[(Resolve-Path $file).Path] = $true
	$pos = $start + $length + 1
}

"wrote $($written.Count) scripts into src/"
Get-ChildItem -Path $srcRoot -Recurse -File -Filter '*.luau' | Where-Object { -not $written.ContainsKey($_.FullName) } | ForEach-Object {
	"repo only (not in Studio): $($_.FullName.Substring($srcRoot.Length + 1))"
}
