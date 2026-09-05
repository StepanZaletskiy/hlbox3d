<#
	Builds box3d.hdll on Windows and, given -Bench, runs the pyramid.

	Until now the module was only ever built by CI, which meant a push and
	a wait for every one-line change to the shim. Everything here is what
	that workflow does, done locally instead: the same HashLink release the
	Windows job downloads, the same CMake arguments, the same Release
	configuration.

	Nothing needs to be on PATH. CMake is found where Visual Studio and the
	standalone installer put it, and the HashLink release is unpacked into
	the build directory the first time and reused after that.

		tools/build.ps1              build the module
		tools/build.ps1 -Check       build it and run the self-test
		tools/build.ps1 -Bench       build it and run the pyramid
		tools/build.ps1 -Bench -Layers 36 -Substeps 4

	The self-test is the one to run after every change to the shim: it
	states what each primitive should do and says so when it does not,
	and its exit code is the number of failures.

	The bench and the self-test need a Haxe compiler on PATH. The module
	does not.
#>
[CmdletBinding()]
param(
	[switch]$Bench,
	[switch]$Check,
	[int]$Layers = 15,
	[int]$Substeps = 0,
	# The release the Windows CI job takes, and what the game runs next to.
	[string]$HashLink = "1.16"
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$build = Join-Path $root "build"

function Find-CMake {
	$cmd = Get-Command cmake -ErrorAction SilentlyContinue
	if ($cmd) { return $cmd.Source }
	$known = @(
		"$env:ProgramFiles\CMake\bin\cmake.exe",
		"${env:ProgramFiles(x86)}\CMake\bin\cmake.exe"
	)
	foreach ($p in $known) { if (Test-Path $p) { return $p } }
	$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
	if (Test-Path $vswhere) {
		$vs = & $vswhere -latest -property installationPath
		$p = Join-Path $vs "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
		if (Test-Path $p) { return $p }
	}
	throw "cmake not found. Install it, or install the C++ CMake tools with Visual Studio."
}

# The release archive carries hl.h, libhl.lib and hl.exe together, which is
# the whole reason to take it rather than build the runtime from source.
function Get-HashLink {
	$dir = Join-Path $build "hashlink-$HashLink"
	if (-not (Test-Path $dir)) {
		$zip = Join-Path $build "hashlink.zip"
		New-Item -ItemType Directory -Force -Path $build | Out-Null
		$url = "https://github.com/HaxeFoundation/hashlink/releases/download/$HashLink/hashlink-$HashLink.0-win.zip"
		Write-Host "Getting HashLink $HashLink"
		$old = $ProgressPreference; $ProgressPreference = 'SilentlyContinue'
		Invoke-WebRequest $url -OutFile $zip
		$ProgressPreference = $old
		Expand-Archive $zip -DestinationPath $dir -Force
		Remove-Item $zip
	}
	$inc = Get-ChildItem $dir -Recurse -Filter hl.h -File | Select-Object -First 1
	$lib = Get-ChildItem $dir -Recurse -Filter libhl.lib -File | Select-Object -First 1
	$exe = Get-ChildItem $dir -Recurse -Filter hl.exe -File | Select-Object -First 1
	if (-not $inc -or -not $lib -or -not $exe) { throw "the archive lacks hl.h, libhl.lib or hl.exe" }
	return @{ Include = $inc.DirectoryName; Lib = $lib.FullName; Exe = $exe.FullName }
}

# Box3D is a submodule; without it CMake fails deep inside vendor/ with
# nothing to say about why.
if (-not (Test-Path (Join-Path $root "vendor/box3d/CMakeLists.txt"))) {
	throw "missing vendor/box3d - run: git submodule update --init"
}

$cmake = Find-CMake
$hl = Get-HashLink

& $cmake -S $root -B $build -A x64 -DHL_INCLUDE="$($hl.Include)" -DHL_LIB="$($hl.Lib)"
if ($LASTEXITCODE -ne 0) { throw "configure failed" }
& $cmake --build $build --config Release
if ($LASTEXITCODE -ne 0) { throw "build failed" }
Write-Host "built $build\box3d.hdll"

if (-not $Bench -and -not $Check) { return }

# HashLink looks for native modules next to the bytecode, and libhl.dll
# next to hl.exe is not enough when hl.exe is run from elsewhere.
Copy-Item (Join-Path (Split-Path $hl.Exe -Parent) "libhl.dll") $build -Force
# The hxml files say -cp src and -cp test, which are relative to the
# repository, so haxe is run from there. hl is run from the build
# directory instead, because that is where the module is and HashLink
# looks for one next to the bytecode.
function Build-Hxml($name) {
	Push-Location $root
	try {
		haxe "test\$name.hxml"
		if ($LASTEXITCODE -ne 0) { throw "haxe failed on $name.hxml" }
	} finally { Pop-Location }
}

if ($Check) {
	Build-Hxml "check"
	Push-Location $build
	try {
		& $hl.Exe "check.hl"
		if ($LASTEXITCODE -ne 0) { throw "$LASTEXITCODE checks failed" }
	} finally { Pop-Location }
}

if ($Bench) {
	Build-Hxml "bench"
	Push-Location $build
	try {
		# Not $args: that name is PowerShell's own and cannot be assigned.
		$run = @("bench.hl", "$Layers")
		if ($Substeps -gt 0) { $run += "$Substeps" }
		& $hl.Exe @run
	} finally { Pop-Location }
}
