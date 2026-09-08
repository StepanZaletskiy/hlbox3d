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

Build the Box3D tests and diff the two outputs:

```
cmake -S build/_deps/box3d-src -B build/box3d-test -DBOX3D_UNIT_TESTS=ON
cmake --build build/box3d-test --config Release --target test
build/box3d-test/bin/Release/test.exe > theirs.txt
diff <(grep passed theirs.txt) <(grep passed ours.txt)
```

Only lines with `<` should appear. They are the tests that are not ported.

## Not Ported

- `test_allocator.c`, `test_bitset.c`, `test_container.c`, `test_id.c`,
  `test_table.c`, `test_sat.c`: internal data structures behind private headers.
- Subtests that read internal state or use internal functions. Each file lists
  its own at the top.

## Determinism

`TestDeterminism.hx` builds the four scenes from `shared/determinism.c` and
`shared/human.c` and must reach the recorded hash on the recorded sleep step,
on the float, the double and the web build. When Box3D updates the constants
in `test_determinism.c`, copy them here.

---

<sub>← [Large worlds](large_worlds.md) · [Documentation](overview.md) · [Reference](reference.md) →</sub>
