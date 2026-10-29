# split-export.ps1: splits a saved ui-json.luau export into ui/<Root>.json files.
# The MCP saves a large execute_luau result either as plain text or as a JSON
# array of {type, text} blocks; both are handled.
#
#   powershell -File scripts/studio/split-export.ps1 <saved result file> [-Only Name1,Name2]
param(
	[Parameter(Mandatory = $true)][string]$Path,
	[string[]]$Only = @(),
	[string]$OutDir = ""
)
# Windows PowerShell 5.1 has no $PSScriptRoot inside param defaults.
if ($OutDir -eq "") { $OutDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "..\..\ui" }

$raw = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
if ($raw.TrimStart().StartsWith("[")) {
	$raw = ((ConvertFrom-Json $raw) | Where-Object { $_.type -eq "text" } | ForEach-Object { $_.text }) -join ""
}
if ($raw.StartsWith("#chunk")) {
	throw "This is one chunk of a longer export. Join all chunks (without their #chunk lines) before splitting."
}

$utf8 = New-Object System.Text.UTF8Encoding($false)
$sections = [regex]::Split($raw, "(?m)^=== ") | Where-Object { $_ -ne "" }
foreach ($section in $sections) {
	$newline = $section.IndexOf("`n")
	$rootPath = $section.Substring(0, $newline).Trim()
	$name = $rootPath.Split(".")[-1]
	if ($Only.Count -gt 0 -and $Only -notcontains $name) { continue }
	$json = $section.Substring($newline + 1)
	$null = ConvertFrom-Json $json  # fails loudly on a truncated export
	$file = Join-Path $OutDir "$name.json"
	[System.IO.File]::WriteAllText($file, $json, $utf8)
	"wrote $file ($($utf8.GetByteCount($json)) bytes)"
}
