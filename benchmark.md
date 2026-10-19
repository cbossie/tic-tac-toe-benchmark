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
| JavaScript (Node) | 4,253 µs | 2,232 µs | 101 ms | 4 KB script |
| C# minimax (JIT) | 2,776 µs | 691 µs | 118 ms | 9 KB dll |
| C# minimax (Native AOT) | 618 µs | 631 µs | 24 ms | 1,133 KB exe |
| C# memoized (JIT) | 343 µs | 0.28 µs | 114 ms | 8 KB dll |
| C# memoized (Native AOT) | 74 µs | 0.07 µs | 25 ms | 950 KB exe |
| C# lookup table (JIT) | 240 µs | 0.22 µs | 116 ms | 20 KB dll |
| C# lookup table (Native AOT) | 26 µs | 0.03 µs | 25 ms | 962 KB exe |
| MSIL (JIT) | 132 µs | 0.27 µs | 114 ms | 5 KB dll |
| x64 assembly, memoized | 38 µs | 0.056 µs | 10 ms | 4.5 KB exe |
| x64 assembly, lookup table | 0.40 µs | 0.024 µs | 11 ms | 16 KB exe |
| x64 assembly, state machine | **~0.04 µs** | **0.012 µs** | 11 ms | 91 KB exe |

For scale, an empty `cmd /c exit` takes 25 ms to launch and exit on this machine. The JIT builds
also need the .NET runtime installed (the C# ones ship a 158 KB launcher `.exe` next to the
`.dll`), and the MSIL build needs a 115-byte `runtimeconfig.json`.

The state machine's cold figure is at the limit of the timer: nine moves take about 0.4 µs in
total, and the clock ticks every 0.1 µs. Read it as "tens of nanoseconds", not as 0.04 exactly.

## The startup floor

To see how much of the startup time is the game and how much is just Windows starting a process,
I timed a program that does nothing: a 2 KB assembly exe whose whole body is a call to
`ExitProcess`.

```asm
extern ExitProcess:proc
.code
main proc
    sub     rsp, 40
    xor     ecx, ecx
    call    ExitProcess
main endp
end
```

| Program | Median | Min | 90th percentile |
|---|---:|---:|---:|
| Do-nothing assembly exe | 9.72 ms | 7.80 ms | 12.06 ms |
| x64 assembly, state machine | 9.68 ms | 7.98 ms | 13.00 ms |
| x64 assembly, lookup table | 9.74 ms | 7.93 ms | 12.72 ms |
| x64 assembly, memoized | 9.60 ms | 7.98 ms | 12.76 ms |
| `cmd /c exit` | 23.19 ms | 19.43 ms | 27.68 ms |

The three assembly games start in the same time as a program that does nothing, so their 10 to
11 ms startup in the main table is entirely the cost of creating and ending a process. Each row is
the median of 150 launches, interleaved, with stdin closed, timed from outside as above.

This means the game's own work is too small to measure here, not that it is zero. In that test the
game makes at most one computer move (about 12 ns), draws a board and prints a prompt, which is
tens of microseconds, mostly console writes. The spread between launches is 1 to 3 ms, so
differences that small are about a hundred times below the noise. A whole game adds well under a
microsecond of computer thinking, so it takes the same time as the do-nothing program plus however
long the human takes to type. Resolving the difference would need an instrument inside the
process, such as a cycle counter, rather than timing from outside.

## What the numbers say

- **Nobody will notice the move time.** Even the slowest version, JavaScript's minimax, answers in
  about 2 ms. What you feel when you launch the game is startup.
- **Startup is mostly the runtime, not the code.** Every JIT build and Node take 100 to 118 ms,
  whatever the algorithm. Native AOT cuts that to about 25 ms, and the assembly versions, which
  have no runtime at all, to 10 or 11 ms. That is the floor: a program that does nothing takes
  the same time (see [the startup floor](#the-startup-floor)). Even the 91 KB state machine starts
  as fast as the 4.5 KB build: the extra size costs no measurable startup.
- **The algorithm matters more than the language, until it stops mattering.**
  - Minimax searches the game on every move: about 630 to 690 µs warm in C# and about 2,200 µs in
    JavaScript.
  - Memoizing the search, or looking moves up in a table, brings a warm move to a fraction of a
    microsecond, thousands of times faster than minimax.
  - JIT compilation is why minimax is about 4 times slower cold than warm in C# but the same cold
    and warm under Native AOT: AOT code has no warm-up.
- **Hand-written MSIL is no faster than C# once warm.** Both give about 0.27 µs, because the C#
  compiler already emits nearly the same IL and the JIT does the rest. The MSIL build's cold move
  is quicker, probably because the hand-written program is smaller and leaves the JIT less to
  compile, but I did not test that.
- **Hand-written assembly is only about as fast as the best compiled code once warm, until the
  design changes.** The memoized assembly build does 0.056 µs against 0.07 µs for memoized Native
  AOT. The two table versions are faster: 0.024 µs in assembly, 0.03 µs in Native AOT.
- **A lookup table removes the cold cost.** Solving is the expensive part of the first moves: the
  memoized assembly build needs 38 µs per move at first because it is filling its cache. The
  assembly lookup table answers its first moves in 0.40 µs, about 95 times faster, because there
  is nothing to solve. It pays for that with a bigger file (16 KB instead of 4.5 KB) and a
  separate generation step.
- **A state machine is about twice as fast as the table again.** The table version still has to
  turn the board into a key and binary search 3,052 positions, about a dozen probes, on every
  move. The state machine carries a state number instead, so a move is a couple of loads, a random
  pick among the stored best moves, and a step through a table: 0.012 µs warm against 0.024 µs,
  and about 5 times faster than the memoized assembly build. The cost is size. It needs 3,052
  states plus 4,264 rows of nine replies, about 89 KB of tables, so the exe is 91 KB.
- **The C# cold figures are not just search time.** The C# lookup-table build shows 26 µs cold
  against 0.40 µs for the same idea in assembly. The timed region of the C# programs probably
  includes one-time setup (for example the random-number generator) that the assembly programs
  do before their timer starts, but I did not separate it out.

## How it was measured

Every version runs the same workload through its `--bench` flag. The computer replies to each of
the nine possible human opening moves, and the whole set is repeated 200 times. The first pass is
reported as cold and the other 199 as warm. `--bench` is described in the [README](README.md). In
the state machine the workload also includes finding the state for each opening (two table loads),
since that is how it learns the human's move.

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
  approximate. Differences under about 10 to 20 percent are within run-to-run noise. Three runs on
  the same day gave slightly different figures, for example 0.13 µs, 0.07 µs and 0.07 µs for the
  warm memoized Native AOT move.
- The memoized, lookup-table and state-machine versions keep their answers between moves, so their
  warm figures measure cached or stored lookups. Minimax recomputes everything each time, so its
  warm figure is a full search.
- Cold figures are dominated by one-time costs (JIT, page faults, cache fills) and vary the most
  between runs.
- Size is the shipped program: the script, the `.dll`, or the `.exe`. It does not count the
  runtime that JIT builds depend on.
