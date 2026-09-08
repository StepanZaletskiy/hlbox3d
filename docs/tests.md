<sub>[hlbox3d](../README.md) › [Documentation](overview.md)</sub>

# Unit Tests

These are ports of the Box3D unit tests in its `test` directory, one Haxe file
per C file, run through the binding. Each test uses the same scenes, the same
numbers, and the same assertions as the original. `Main.hx` is the runner and
prints what `main.c` prints.

## Running

```
haxe test/Main.hxml
cd build && hl check.hl
```

`cmake --build build --config Release --target check` builds the module
and does both. The exit code is the number of failed assertions. A failure
prints the expression, the file, and the line.

On the web `test/Web.hxml` compiles the same tests to JavaScript and node
runs them against `box3d.js`; `cmake --build build-web --target check`
does that. `Single` there is `F32.hx`, a float kept by `Math.fround`.

## Comparing with Box3D

Build the Box3D tests from the fetched sources, run both sides, and let
`.github/parity.ps1` compare the outputs subtest for subtest:

```
cmake -S build/_deps/box3d-src -B build/box3d-test -DBOX3D_UNIT_TESTS=ON -DBOX3D_SAMPLES=OFF
cmake --build build/box3d-test --config Release --target test
build/box3d-test/bin/Release/test.exe > build/theirs.txt
cmake --build build --config Release --target check > build/check.log
pwsh .github/parity.ps1
```

Both runners print the same lines, so the script reads them the same
way. It ends with one line, `Box3D: 256 subtests in 25 tests. Ported:
223 in 19. Excused: 33.`, and fails on anything else: a subtest of
Box3D's that ours has not and that is not excused, one of ours that
Box3D has not, an excuse that no longer holds, a failure on either side,
or a README badge that says another number. `-List` prints every
subtest with its mark. CI runs this on Linux on every push, so the
number on the README badge is measured, not remembered.

## Not Ported

The excused list in `parity.ps1` is the record, one reason per name:

- `test_allocator.c`, `test_bitset.c`, `test_container.c`, `test_id.c`,
  `test_table.c`, `test_sat.c`: internal data structures behind private headers.
- Subtests that read internal state or use internal functions. Each file lists
  its own at the top as well.

## Determinism

`TestDeterminism.hx` builds the four scenes from `shared/determinism.c` and
`shared/human.c` and must reach the recorded hash on the recorded sleep step,
on the float, the double and the web build. When Box3D updates the constants
in `test_determinism.c`, copy them here.

---

<sub>← [Large worlds](large_worlds.md) · [Documentation](overview.md) · [Reference](reference.md) →</sub>
