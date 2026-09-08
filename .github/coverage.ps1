# What Box3D exports against what the shim calls.
#
#   .github/coverage.ps1        the count, and anything unaccounted for
#   .github/coverage.ps1 -List  every function, with a mark against each
#
# The README claims a number - five hundred and eighty-five exported,
# fifteen of them deliberately not called - and a claim nobody can check
# rots. This is the check. It fails when something is exported and not
# called and is not one of the fifteen, which is what happens when Box3D
# is updated and grows a function nobody noticed.
#
# It reads the headers rather than the built module because that is where
# the promise is: B3_API is what Box3D says is public.

param(
	# Print every exported function and whether the shim calls it.
	[switch]$List
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$root = Split-Path -Parent $PSScriptRoot

# The six headers a game can reach. `id.h` has no functions of its own -
# it is the handle types - and everything under src/ is Box3D's inside.
$headers = @('box3d', 'collision', 'base', 'constants', 'math_functions', 'types')

# The ones that are exported and not called, each for a reason. This list
# is the point of the file: it is where "not bound" is distinguished from
# "forgotten". Adding a name here should take an argument.
$excused = [ordered]@{
	'b3Body_GetWorld'            = 'the Haxe object already holds the world'
	'b3Shape_GetWorld'           = 'the Haxe object already holds the world'
	'b3Joint_GetWorld'           = 'the Haxe object already holds the world'
	'b3World_SetUserData'        = 'the user data is the shim''s own id table'
	'b3World_GetUserData'        = 'the user data is the shim''s own id table'
	'b3Contact_GetData'          = 'contact ids are not handed out; manifolds come from a body'
	'b3Contact_IsValid'          = 'contact ids are not handed out; manifolds come from a body'
	'b3World_DumpShapeBounds'    = 'declared in the header and not implemented in Box3D'
	'b3SetAllocator'             = 'an allocator is C, and nothing of ours may run on Box3D''s threads'
	'b3InternalAssert'           = 'Box3D''s own way of reaching the assert handler; World.listen sets it'
	'b3GetMillisecondsAndReset'  = 'World.ticks is the same clock, and a Haxe variable holds the reading'
}

$exported = [ordered]@{}
foreach ($h in $headers) {
	$path = Join-Path $root "build/_deps/box3d-src/include/box3d/$h.h"
	if (-not (Test-Path $path)) { throw "no $path - configure first (tools/build.ps1 fetches Box3D into build/_deps)" }
	$text = Get-Content $path -Raw
	# A declaration may wrap, so the whole file is read at once rather than
	# line by line: `B3_API`, a return type, the name, an open bracket.
	foreach ($m in [regex]::Matches($text, 'B3_API\s+[^;{()]*?\b(b3[A-Za-z0-9_]+)\s*\(')) {
		$exported[$m.Groups[1].Value] = $h
	}
}

$shim = Get-Content (Join-Path $root 'src/box3d_hl.c') -Raw
$called = @{}
foreach ($m in [regex]::Matches($shim, '\bb3[A-Za-z0-9_]+\b')) { $called[$m.Value] = $true }

$missing = @()
foreach ($name in $exported.Keys) {
	if (-not $called.ContainsKey($name)) { $missing += $name }
}

if ($List) {
	foreach ($name in $exported.Keys) {
		$mark = if ($called.ContainsKey($name)) { 'called ' }
			elseif ($excused.Contains($name)) { 'excused' }
			else { 'MISSING' }
		"{0}  {1,-34} {2}" -f $mark, $name, $exported[$name]
	}
	Write-Host ''
}

$unexcused = $missing | Where-Object { -not $excused.Contains($_) }
$stale = $excused.Keys | Where-Object { $called.ContainsKey($_) }

Write-Host ("exported {0}, called {1}, excused {2}" -f
	$exported.Count, ($exported.Count - $missing.Count), $missing.Count)

foreach ($name in $stale) {
	Write-Host "no longer needs excusing, it is called now: $name" -ForegroundColor Yellow
}

if ($unexcused.Count -gt 0) {
	Write-Host ''
	Write-Host 'exported by Box3D and called by nothing:' -ForegroundColor Red
	foreach ($name in $unexcused) { Write-Host "  $name  ($($exported[$name]).h)" -ForegroundColor Red }
	Write-Host ''
	Write-Host 'Bind it, or put it in $excused above with the reason.'
	exit $unexcused.Count
}

if ($stale.Count -gt 0) { exit 1 }
exit 0
