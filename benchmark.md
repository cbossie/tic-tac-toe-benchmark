# Benchmark

How fast each version of the game runs. Measured on 2026-10-18.

**Machine:** Intel Core i7-8550U (4 cores / 8 threads, 1.8 GHz laptop CPU), 16 GB RAM,
Windows 11 Pro 10.0.26300. **Tools:** Node 20.14.0, .NET SDK 10.0.402, MSVC 14.51 (ml64 and link).

## Results

Time is per computer move. "Cold" is the first nine moves of a fresh process, so it includes JIT
compilation and first-touch costs. "Warm" is the average over the next 1,791 moves. Startup is the
time for the whole process to launch, draw the first board, find stdin closed and exit.

| Version | Cold move | Warm move | Startup | Size |
|---|---:|---:|---:|---:|
| JavaScript (Node) | 4,237 µs | 2,137 µs | 96 ms | 4 KB script |
| C# minimax (JIT) | 3,072 µs | 673 µs | 114 ms | 9 KB dll |
| C# minimax (Native AOT) | 625 µs | 645 µs | 24 ms | 1,133 KB exe |
| C# memoized (JIT) | 352 µs | 0.28 µs | 109 ms | 8 KB dll |
| C# memoized (Native AOT) | 70 µs | 0.07 µs | 24 ms | 950 KB exe |
| C# lookup table (JIT) | 266 µs | 0.23 µs | 110 ms | 20 KB dll |
| C# lookup table (Native AOT) | 29 µs | 0.04 µs | 24 ms | 962 KB exe |
| MSIL (JIT) | 132 µs | 0.28 µs | 108 ms | 5 KB dll |
| x64 assembly, memoized | 37 µs | 0.063 µs | 10 ms | 4.5 KB exe |
| x64 assembly, lookup table | **0.46 µs** | **0.025 µs** | 10 ms | 16 KB exe |

For scale, an empty `cmd /c exit` takes 24 ms to launch and exit on this machine. The JIT builds
also need the .NET runtime installed (the C# ones ship a 158 KB launcher `.exe` next to the
`.dll`), and the MSIL build needs a 115-byte `runtimeconfig.json`.

## What the numbers say

- **Nobody will notice the move time.** Even the slowest version, JavaScript's minimax, answers in
  about 2 ms. What you feel when you launch the game is startup.
- **Startup is mostly the runtime, not the code.** Every JIT build and Node take 96 to 114 ms,
  whatever the algorithm. Native AOT cuts that to about 24 ms, and the assembly versions, which
  have no runtime at all, to 10 ms.
- **The algorithm matters more than the language, until it stops mattering.**
  - Minimax searches the game on every move: about 650 µs warm in C# and about 2,100 µs in
    JavaScript.
  - Memoizing the search, or looking moves up in a table, brings a warm move to a fraction of a
    microsecond, thousands of times faster than minimax.
  - JIT compilation is why minimax is about 4.5 times slower cold than warm in C# but the same
    cold and warm under Native AOT: AOT code has no warm-up.
- **Hand-written MSIL is no faster than C# once warm.** Both give 0.28 µs, because the C# compiler
  already emits nearly the same IL and the JIT does the rest. The MSIL build's cold move is
  quicker, probably because the hand-written program is smaller and leaves the JIT less to
  compile, but I did not test that.
- **Hand-written assembly is only about as fast as the best compiled code once warm.** The
  memoized assembly build does 0.063 µs against 0.07 µs for memoized Native AOT, and the table
  versions are faster than both: 0.025 µs in assembly, 0.04 µs in Native AOT. Assembly's lasting
  advantages are size and startup.
- **A lookup table removes the cold cost.** Solving is the expensive part of the first moves: the
  memoized assembly build needs 37 µs per move at first because it is filling its cache. The
  assembly lookup table answers its very first moves in 0.46 µs, about 80 times faster, because
  there is nothing to solve. It pays for that with a bigger file (16 KB instead of 4.5 KB) and a
  separate generation step.
- **The C# cold figures are not just search time.** The C# lookup-table build shows 29 µs cold
  against 0.46 µs for the same idea in assembly. The timed region of the C# programs probably
  includes one-time setup (for example the random-number generator) that the assembly program
  does before its timer starts, but I did not separate it out.

## How it was measured

Every version runs the same workload through its `--bench` flag. The computer replies to each of
the nine possible human opening moves, and the whole set is repeated 200 times. The first pass is
reported as cold and the other 199 as warm. `--bench` is described in the [README](README.md).

- **Move figures** are the median of 7 separate process runs per version.
- **Startup** is the median of 40 launches per version, with stdin closed so the game exits at its
  first prompt. Launches were interleaved (one of each version per round) so that background noise
  affects every version equally, and two warm-up rounds were discarded. Timing is from process start
  to exit, measured from outside with a stopwatch.
- **Builds:** the JIT rows were published with `-p:PublishAot=false` and run through the generated
  `.exe` launcher. The Native AOT rows are plain `dotnet publish`. The MSIL row is
  `dotnet TicTacToeIL.dll`. The assembly rows are the `.exe` files from each directory's
  `buildasm.ps1`. All were built from the sources in this repo with the commands in the README.

## Caveats

- One machine, one day, a laptop CPU. Treat the ratios as meaningful and the absolute numbers as
  approximate. Differences under about 10 to 20 percent are within run-to-run noise. Two runs on
  the same day gave slightly different figures, for example 0.13 µs and 0.07 µs for the warm
  memoized Native AOT move.
- The memoized and lookup-table versions keep their answers between moves, so their warm figures
  measure cached or stored lookups. Minimax recomputes everything each time, so its warm figure is
  a full search.
- Cold figures are dominated by one-time costs (JIT, page faults, cache fills) and vary the most
  between runs.
- Size is the shipped program: the script, the `.dll`, or the `.exe`. It does not count the
  runtime that JIT builds depend on.
