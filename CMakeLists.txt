# Builds box3d.hdll: the shim plus Box3D, statically linked into one
# HashLink native module.
#
# Simpler than the Jolt one, and for one reason: Box3D is C with a C API,
# so there is nothing between the shim and the library. The Jolt build
# needs joltc in the middle to turn C++ into something a HashLink module
# can call, and four times over that middle layer turned out to be missing
# the call we wanted.
#
# Box3D is a submodule pinned by commit. As a subdirectory rather than the
# top-level project it builds only its library: its samples, benchmarks
# and unit tests are all behind PROJECT_IS_TOP_LEVEL.
#
# HashLink can be pointed at in two ways:
#
#   -DHL_ROOT=<built checkout>          hl.h in src/, libhl next to it
#   -DHL_INCLUDE=<dir> -DHL_LIB=<file>  an unpacked release archive
#
# The first is what a Linux build does after `make libhl.so`; the second is
# what the game's Windows CI has, since it takes the runtime as an archive
# and never builds it.

cmake_minimum_required(VERSION 3.22)

# Lets CMAKE_MSVC_RUNTIME_LIBRARY below mean anything. Must come before
# project().
cmake_policy(SET CMP0091 NEW)

project(hlbox3d C)

set(CMAKE_C_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(DEFINED HL_ROOT)
	set(HL_INCLUDE "${HL_ROOT}/src")
	set(HL_LIB "")
elseif(NOT DEFINED HL_INCLUDE OR NOT DEFINED HL_LIB)
	message(FATAL_ERROR "Point at HashLink: either HL_ROOT, or HL_INCLUDE and HL_LIB")
endif()

# Everything ends up inside one .hdll; there is no second file to ship
# next to it.
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

# Box3D's own switches. SIMD is the whole point of it, so it stays on;
# double precision is for worlds measured in kilometres and costs speed
# and memory everywhere else.
set(BOX3D_DISABLE_SIMD OFF CACHE BOOL "" FORCE)
set(BOX3D_DOUBLE_PRECISION OFF CACHE BOOL "" FORCE)

if(MSVC)
	# libhl is built against the DLL runtime (/MD), and a module that mixes
	# in objects built against the static one (/MT) does not link: the
	# linker refuses the mismatch outright.
	set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreadedDLL" CACHE STRING "" FORCE)

	# The same sources give the same file. Without this the linker stamps
	# the build time into the header, and a .hdll committed to LFS would be
	# a new object on every run that changed nothing.
	add_compile_options(/Brepro)
	add_link_options(/Brepro)
endif()

add_subdirectory(vendor/box3d)

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
