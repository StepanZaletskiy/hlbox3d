# Box3D's own test run against ours, subtest for subtest.
#
#   .github/parity.ps1 -Theirs build/theirs.txt -Ours build/check.log
#   .github/parity.ps1 -List        every subtest of Box3D's, with a mark
#
# The README claims a number - two hundred and twenty-three of Box3D's
# two hundred and fifty-six subtests ported - and a claim nobody can check
# rots. This is the check. Both runners print the same lines, "test
# passed: X" and "  subtest passed: Y", so the two outputs are read the
# same way and compared name for name. It fails when Box3D has a subtest
# ours has not and it is not one of the excused, when ours has one Box3D
# has not (test/ is ports and nothing else), when an excused one turns
# out to be ported after all, when either side failed anything, or when
# the README's number is off.

param(
	# The output of Box3D's test binary.
	[string]$Theirs = 'build/theirs.txt',
	# The output of the check target, ours.
	[string]$Ours = 'build/check.log',
	# Print every subtest of Box3D's and whether ours has it.
	[switch]$List
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8

$root = Split-Path -Parent $PSScriptRoot

# Whole tests with nothing public to reach: the data structures behind
# private headers. Listed by the name their runner prints.
$excusedTests = [ordered]@{
	'AllocatorTest'      = 'test_allocator.c: the block allocator is internal'
	'BitTest'            = 'test_bitset.c: the bit set is internal'
	'ContainerTest'      = 'test_container.c: the array container is internal'
	'IdTest'             = 'test_id.c: id packing is internal'
	'TableTest'          = 'test_table.c: the hash table is internal'
	'SeparatingAxisTest' = 'test_sat.c: the SAT routines are internal'
}

# Single subtests of ported tests that read internal state or call
# internal functions. Each test file says the same at its top; this is
# where the claim is checked. Adding a name here should take an argument.
$excusedSubtests = [ordered]@{
	'BodyTest/DeferredMassExtents'             = 'reads the dirty mass flag and minExtent off the body struct'
	'CollisionTest/TestRayAABBIntersection'    = 'b3RayCastAABB is internal'
	'HashTest/HashWordFamily'                  = 'b3Hash64NonZero is internal'
	'HashTest/HashBitSweep'                    = 'b3Hash64NonZero is internal'
	'HashTest/HashZeroLengths'                 = 'b3Hash64NonZero is internal'
	'HashTest/HashFloatSigns'                  = 'b3Hash64NonZero is internal'
	'HashTest/HashFloatUlp'                    = 'b3Hash64NonZero is internal'
	'HashTest/HashVoxelHullDatabase'           = 'b3HullMap is internal'
	'HeightFieldTest/HeightFieldTriangleIndex' = 'needs the vertex indices of a height field triangle, which the API does not give'
	'HeightFieldTest/HeightFieldWinding'       = 'needs the vertex indices of a height field triangle, which the API does not give'
	'HeightFieldTest/RayCastBruteForce'        = 'needs the vertex indices of a height field triangle, which the API does not give'
	'NameCacheTest/CacheUnit'                  = 'b3CreateNameCache, b3AddName, b3FindName are in name_cache.h'
	'RecordingTest/GeometryHashCollision'      = 'b3GeometryRegistry internals'
}

# Read a runner's output: which tests it ran, which subtests each had, and
# how many of either failed. Subtests print before the line of the test
# that ran them, so they are gathered until that line closes them. Leading
# space is ignored, since cmake indents what the check target prints.
function Read-Run( [string]$path ) {
	if (-not (Test-Path $path)) { throw "no $path" }
	$tests = [ordered]@{}
	$pending = @()
	$failed = 0
	foreach ($line in Get-Content $path) {
		if ($line -match '^\s*subtest (passed|failed): (\S+)') {
			$pending += $Matches[2]
			if ($Matches[1] -eq 'failed') { $failed++ }
		} elseif ($line -match '^\s*test (passed|failed): (\S+)') {
			$tests[$Matches[2]] = $pending
			$pending = @()
			if ($Matches[1] -eq 'failed') { $failed++ }
		}
	}
	return @{ tests = $tests; failed = $failed }
}

$their = Read-Run (Join-Path $root $Theirs)
$our = Read-Run (Join-Path $root $Ours)

$theirPairs = @()
foreach ($t in $their.tests.Keys) { foreach ($s in $their.tests[$t]) { $theirPairs += "$t/$s" } }
$ourPairs = @{}
foreach ($t in $our.tests.Keys) { foreach ($s in $our.tests[$t]) { $ourPairs["$t/$s"] = $true } }

$problems = 0
$ported = 0
$excused = 0

if ($List) {
	foreach ($pair in $theirPairs) {
		$test = $pair.Split('/')[0]
		$mark = if ($ourPairs.ContainsKey($pair)) { 'ported ' }
			elseif ($excusedSubtests.Contains($pair) -or $excusedTests.Contains($test)) { 'excused' }
			else { 'MISSING' }
		"{0}  {1}" -f $mark, $pair
	}
	Write-Host ''
}

# Theirs that ours has not, and is not excused.
foreach ($pair in $theirPairs) {
	$test = $pair.Split('/')[0]
	if ($ourPairs.ContainsKey($pair)) { $ported++ }
	elseif ($excusedSubtests.Contains($pair) -or $excusedTests.Contains($test)) { $excused++ }
	else { Write-Host "Box3D has it and ours does not: $pair" -ForegroundColor Red; $problems++ }
}
foreach ($test in $their.tests.Keys) {
	if (-not $our.tests.Contains($test) -and -not $excusedTests.Contains($test)) {
		Write-Host "Box3D has the test and ours does not: $test" -ForegroundColor Red; $problems++
	}
}

# Ours that theirs has not: test/ is ports only.
foreach ($pair in $ourPairs.Keys) {
	if ($theirPairs -notcontains $pair) { Write-Host "ours has it and Box3D does not: $pair" -ForegroundColor Red; $problems++ }
}
foreach ($test in $our.tests.Keys) {
	if (-not $their.tests.Contains($test)) { Write-Host "ours has the test and Box3D does not: $test" -ForegroundColor Red; $problems++ }
}

# Excuses that no longer hold.
foreach ($pair in $excusedSubtests.Keys) {
	if ($ourPairs.ContainsKey($pair)) { Write-Host "no longer needs excusing, it is ported now: $pair" -ForegroundColor Yellow; $problems++ }
}
foreach ($test in $excusedTests.Keys) {
	if ($our.tests.Contains($test)) { Write-Host "no longer needs excusing, it is ported now: $test" -ForegroundColor Yellow; $problems++ }
}

# Failures on either side.
if ($their.failed -gt 0) { Write-Host "Box3D's own run failed $($their.failed)" -ForegroundColor Red; $problems++ }
if ($our.failed -gt 0) { Write-Host "ours failed $($our.failed)" -ForegroundColor Red; $problems++ }

# The README's badge must say what was just measured.
$readme = Get-Content (Join-Path $root 'README.md') -Raw
if ($readme -match 'Box3D%20tests-(\d+)%20of%20(\d+)%20ported') {
	$claimed = [int]$Matches[1]; $claimedTotal = [int]$Matches[2]
	if ($claimed -ne $ported -or $claimedTotal -ne $theirPairs.Count) {
		Write-Host ("the README badge says {0} of {1}; it is {2} of {3}" -f $claimed, $claimedTotal, $ported, $theirPairs.Count) -ForegroundColor Red
		$problems++
	}
} else {
	Write-Host 'the README has no Box3D tests badge' -ForegroundColor Red; $problems++
}

Write-Host ("Box3D: {0} subtests in {1} tests. Ported: {2} in {3}. Excused: {4}." -f
	$theirPairs.Count, $their.tests.Count, $ported, $our.tests.Count, $excused)

exit $problems
