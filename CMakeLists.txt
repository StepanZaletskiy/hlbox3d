# Builds box3d.hdll: the shim plus Box3D, statically linked into one
# HashLink native module.
#
#   cmake -S . -B build && cmake --build build --config Release
#   cmake --build build --config Release --target check      Box3D's tests through the binding
#
# Box3D is fetched on the first configure, pinned by commit, into
# build/_deps/box3d-src; nothing has to be cloned by hand. As a
# subdirectory rather than the top-level project it builds only its
# library: its samples, benchmarks and unit tests are all behind
# PROJECT_IS_TOP_LEVEL. A checkout on disk can stand in for the fetch:
#
#   -DFETCHCONTENT_SOURCE_DIR_BOX3D=<checkout>
#
# HashLink is fetched too when nothing points at one: on Windows the 1.16
# release archive, which has hl.h, libhl.lib and hl.exe; elsewhere the
# sources at the same tag, from which libhl and hl are built with make as
# part of the build; that needs a C compiler and make, on Debian
# `apt install build-essential cmake git`. Or point at one:
#
#   -DHL_ROOT=<built checkout>          hl.h in src/, libhl next to it
#   -DHL_INCLUDE=<dir> -DHL_LIB=<file>  an unpacked release archive
#
# Another build of the same module, into a directory of its own:
#
#   -DHLBOX3D_LARGE_WORLD=ON    positions as doubles, for worlds in kilometres
#
# And Box3D's assertions, for catching a misuse, are a configuration
# rather than an option, as they are for Box3D itself: Release drops them,
# RelWithDebInfo and Debug keep them.
#
#   cmake --build build --config RelWithDebInfo        Visual Studio
#   cmake -S . -B build-checked -DCMAKE_BUILD_TYPE=RelWithDebInfo   Ninja, make
#
# And the web: the same shim as box3d.js and box3d.wasm for Haxe compiled
# to JavaScript, with the Emscripten SDK on PATH. No HashLink is fetched;
# the checks then run under node.
#
#   emcmake cmake -S . -B build-web && cmake --build build-web

cmake_minimum_required(VERSION 3.22)

# Lets CMAKE_MSVC_RUNTIME_LIBRARY below mean anything. Must come before
# project().
cmake_policy(SET CMP0091 NEW)

project(hlbox3d C)

set(CMAKE_C_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

include(FetchContent)
if(POLICY CMP0169)
	cmake_policy(SET CMP0169 OLD)
endif()

# --- HashLink ---------------------------------------------------------------

set(HL_RUNTIME_TARGET "")

if(EMSCRIPTEN)
	# No HashLink on the web: the shim becomes a wasm module of its own, below.
elseif(DEFINED HL_ROOT)
	set(HL_INCLUDE "${HL_ROOT}/src")
	set(HL_LIB "")
	find_program(HL_EXE NAMES hl PATHS "${HL_ROOT}" NO_DEFAULT_PATH)
elseif(DEFINED HL_INCLUDE AND DEFINED HL_LIB)
	get_filename_component(HL_LIB_DIR "${HL_LIB}" DIRECTORY)
	find_program(HL_EXE NAMES hl PATHS "${HL_LIB_DIR}" "${HL_BIN}")
elseif(WIN32)
	FetchContent_Declare(hashlink
		URL https://github.com/HaxeFoundation/hashlink/releases/download/1.16/hashlink-1.16.0-win.zip)
	FetchContent_Populate(hashlink)
	set(HL_INCLUDE "${hashlink_SOURCE_DIR}/include")
	set(HL_LIB "${hashlink_SOURCE_DIR}/libhl.lib")
	set(HL_EXE "${hashlink_SOURCE_DIR}/hl.exe")
else()
	FetchContent_Declare(hashlink
		GIT_REPOSITORY https://github.com/HaxeFoundation/hashlink.git
		GIT_TAG 1.16)
	FetchContent_Populate(hashlink)
	set(HL_ROOT "${hashlink_SOURCE_DIR}")
	set(HL_INCLUDE "${HL_ROOT}/src")
	set(HL_LIB "")
	set(HL_EXE "${HL_ROOT}/hl")
	# libhl.so and hl, from the sources, by HashLink's own Makefile.
	add_custom_command(OUTPUT "${HL_ROOT}/libhl.so" "${HL_ROOT}/hl"
		COMMAND make -C "${HL_ROOT}" libhl.so hl
		COMMENT "Building libhl and hl from the HashLink sources")
	add_custom_target(hashlink_runtime DEPENDS "${HL_ROOT}/libhl.so" "${HL_ROOT}/hl")
	set(HL_RUNTIME_TARGET hashlink_runtime)
endif()

# Everything ends up inside one .hdll; there is no second file to ship
# next to it.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

# --- Box3D ------------------------------------------------------------------

# Box3D's own switches. SIMD is the whole point of it, so it stays on.
# Double precision positions are for worlds measured in kilometres and
# cost speed and memory everywhere else, so they are a second build of
# the same module rather than the default. The Haxe side is the same for
# both, since it already passes positions as doubles; which one runs is
# which box3d.hdll sits next to hl.
option(HLBOX3D_LARGE_WORLD "Build with double precision positions" OFF)
set(BOX3D_DISABLE_SIMD OFF CACHE BOOL "" FORCE)
set(BOX3D_DOUBLE_PRECISION ${HLBOX3D_LARGE_WORLD} CACHE BOOL "" FORCE)

if(MSVC)
	# libhl is built against the DLL runtime (/MD), and a module that mixes
	# in objects built against the static one (/MT) does not link: the
	# linker refuses the mismatch outright.
	set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDLL" CACHE STRING "" FORCE)

	# The same sources give the same file. Without this the linker stamps
	# the build time into the header, and a .hdll committed to LFS would be
	# a new object on every run that changed nothing.
	# Release only: with the /Zi of RelWithDebInfo it leaves the debug
	# information the linker then refuses as corrupt.
	add_compile_options($<$<CONFIG:Release>:/Brepro>)
	add_link_options($<$<CONFIG:Release>:/Brepro>)
endif()

# Pinned by commit rather than tag: Box3D is in alpha and the binding is
# checked against this one, test for test.
FetchContent_Declare(box3d
	GIT_REPOSITORY https://github.com/erincatto/box3d.git
	GIT_TAG 47d7f7cc7e091142c08d11dc7d2e493c5d34f536)
FetchContent_MakeAvailable(box3d)

# Box3D sets CMAKE_MSVC_RUNTIME_LIBRARY to the static CRT in its own
# CMakeLists, which shadows the cache entry above inside its directory.
# A module that mixes the two CRTs links with a warning and then has two
# heaps in it, so the target is put back on the DLL runtime by hand.
if(MSVC)
	set_property(TARGET box3d PROPERTY MSVC_RUNTIME_LIBRARY "MultiThreadedDLL")
endif()

# --- the module -------------------------------------------------------------

if(EMSCRIPTEN)

# The same shim as box3d.js and box3d.wasm: every primitive is an export,
# _box3d_<name>, called by name from the Haxe side compiled to JavaScript.
# MODULARIZE makes box3d.js a factory, Box3D(), that resolves to the
# module once the wasm is in; a script tag defines it as a global and
# node gets it from require. The heap and the string helpers are what
# `box3d.Wasm` reads and writes through; FS is for the checks, which
# write files. SIMD flags match the ones Box3D sets for its own sources,
# since its headers carry the SSE2 path the shim compiles too.
add_executable(box3d_web src/box3d_hl.c)
set_target_properties(box3d_web PROPERTIES
	OUTPUT_NAME "box3d"
	SUFFIX ".js"
	RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")
target_link_libraries(box3d_web PRIVATE box3d)
if(NOT BOX3D_DISABLE_SIMD)
	target_compile_options(box3d_web PRIVATE -msimd128 -msse2)
endif()
target_link_options(box3d_web PRIVATE
	--no-entry
	-sMODULARIZE=1
	-sEXPORT_NAME=Box3D
	-sALLOW_MEMORY_GROWTH=1
	-sEXPORTED_FUNCTIONS=_malloc,_free
	-sEXPORTED_RUNTIME_METHODS=HEAPU8,UTF8ToString,stringToUTF8,lengthBytesUTF8,FS)

else()

add_library(box3d_hl MODULE src/box3d_hl.c)

# A .hdll is loaded by name, so no lib prefix and a fixed suffix. And the
# file lands in the build directory itself on every generator - the Visual
# Studio one would otherwise put it a Release/ deeper.
set_target_properties(box3d_hl PROPERTIES
	OUTPUT_NAME "box3d"
	PREFIX ""
	SUFFIX ".hdll"
	LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
	LIBRARY_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}"
	LIBRARY_OUTPUT_DIRECTORY_DEBUG "${CMAKE_BINARY_DIR}"
	LIBRARY_OUTPUT_DIRECTORY_RELWITHDEBINFO "${CMAKE_BINARY_DIR}"
	LIBRARY_OUTPUT_DIRECTORY_MINSIZEREL "${CMAKE_BINARY_DIR}")

target_include_directories(box3d_hl PRIVATE "${HL_INCLUDE}")

if(HL_LIB STREQUAL "")
	target_link_directories(box3d_hl PRIVATE "${HL_ROOT}")
	target_link_libraries(box3d_hl PRIVATE box3d hl)
else()
	target_link_libraries(box3d_hl PRIVATE box3d "${HL_LIB}")
endif()

if(HL_RUNTIME_TARGET)
	add_dependencies(box3d_hl ${HL_RUNTIME_TARGET})
endif()

endif()

# --- the checks -------------------------------------------------------------

# Box3D's own unit tests through the binding: test/Main.hxml compiled by
# haxe into build/check.hl beside the module, then run by hl. Needs haxe
# on PATH at configure time. A failure is the exit code, so this fails
# the build. On Linux hl finds a .hdll through the loader path, not the
# working directory, so the build directory goes on LD_LIBRARY_PATH.
find_program(HAXE_EXE NAMES haxe)
if(EMSCRIPTEN)
	# The same checks compiled to JavaScript and run by node, which the
	# Emscripten SDK carries: EMSDK_NODE names it.
	find_program(NODE_EXE NAMES node)
	if(DEFINED ENV{EMSDK_NODE})
		set(NODE_EXE "$ENV{EMSDK_NODE}")
	endif()
	if(HAXE_EXE AND NODE_EXE)
		set(CHECK_JS "${CMAKE_SOURCE_DIR}/build/check.js")
		add_custom_target(check
			COMMAND "${HAXE_EXE}" test/Web.hxml
			COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${CHECK_JS}" "${CMAKE_BINARY_DIR}/check.js"
			COMMAND "${CMAKE_COMMAND}" -E chdir "${CMAKE_BINARY_DIR}" "${NODE_EXE}" check.js
			WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
			DEPENDS box3d_web
			USES_TERMINAL)
	else()
		add_custom_target(check
			COMMAND "${CMAKE_COMMAND}" -E echo "check: haxe or node not found")
	endif()
elseif(HAXE_EXE AND HL_EXE)
	set(CHECK_HL "${CMAKE_SOURCE_DIR}/build/check.hl")
	add_custom_target(check
		COMMAND "${HAXE_EXE}" test/Main.hxml
		COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${CHECK_HL}" "${CMAKE_BINARY_DIR}/check.hl"
		COMMAND "${CMAKE_COMMAND}" -E chdir "${CMAKE_BINARY_DIR}"
			"${CMAKE_COMMAND}" -E env "LD_LIBRARY_PATH=${HL_ROOT}:${CMAKE_BINARY_DIR}" "${HL_EXE}" check.hl
		WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
		DEPENDS box3d_hl
		USES_TERMINAL)
else()
	add_custom_target(check
		COMMAND "${CMAKE_COMMAND}" -E echo "check: haxe or hl not found; put haxe on PATH and point at HashLink")
endif()
