# Tic-Tac-Toe, eight ways

A command-line game of tic-tac-toe against the computer, written several ways to compare how they
run. You are **X**, the computer is **O**, and the board is redrawn after every move. Type a square
number (1-9) to play. Who goes first is random, and the computer never loses, so the best you can do
is draw.

Every version plays the same game. They differ in how the computer picks its move and in how the
program is built:

| Directory | What it is | Run with |
|---|---|---|
| [`javascript/`](javascript) | Minimax with alpha-beta pruning, in Node.js | `node tictactoe.js` |
| [`csharp-minimax/`](csharp-minimax) | The same minimax, in C# | `dotnet run TicTacToe.cs` |
| [`csharp-memoized/`](csharp-memoized) | Bitboards plus a memoized solver, in C# | `dotnet run TicTacToeFast.cs` |
| [`csharp-lookup-table/`](csharp-lookup-table) | No solving at all: moves come from a precomputed table | `dotnet run TicTacToeTable.cs` |
| [`msil/`](msil) | The memoized solver written by hand in MSIL | `.\buildil.ps1`, then `dotnet TicTacToeIL.dll` |
| [`assembly-x64-memoized/`](assembly-x64-memoized) | The memoized solver written by hand in x64 assembly | `.\buildasm.ps1`, then `.\TicTacToeAsm.exe` |
| [`assembly-x64-lookup-table/`](assembly-x64-lookup-table) | The lookup table written by hand in x64 assembly | `.\buildasm.ps1`, then `.\TicTacToeAsmTable.exe` |
| [`assembly-x64-state-machine/`](assembly-x64-state-machine) | The game as a precomputed state machine, in x64 assembly: no search, no board lookup | `.\buildasm.ps1`, then `.\TicTacToeAsmStates.exe` |

See [benchmark.md](benchmark.md) for how they compare.

## What you need

| To run | You need |
|---|---|
| `javascript/` | [Node.js](https://nodejs.org) (tested on 20) |
| `csharp-*` with `dotnet run` | the [.NET 10 SDK](https://dotnet.microsoft.com/download) (single-file `dotnet run File.cs` needs 10 or later) |
| `msil/` | the .NET 10 runtime, plus an internet connection the first time (it downloads Microsoft's IL assembler, about 450 KB, from nuget.org) |
| Native AOT builds and `assembly-x64-*/` | Visual Studio with the **Desktop development with C++** workload (for the compiler and linker). Windows x64 only |
| Regenerating a lookup table | the .NET 10 SDK (the generator is a C# file) |

Everything is Windows-oriented. The JavaScript and `dotnet run` versions also work elsewhere, but
`msil/` and `assembly-x64-*/` are Windows scripts.

## Running each version

Run every command from inside that version's directory.

### JavaScript

```powershell
cd javascript
node tictactoe.js
```

### C# (minimax, memoized, lookup table)

```powershell
cd csharp-minimax
dotnet run TicTacToe.cs
```

```powershell
cd csharp-memoized
dotnet run TicTacToeFast.cs
```

```powershell
cd csharp-lookup-table
dotnet run TicTacToeTable.cs
```

The first run compiles the file, so it starts a little slower. Later runs are cached.

#### Building a native executable (Native AOT)

`dotnet publish` compiles a C# file to a standalone `.exe` that needs no .NET installed and starts
much faster:

```powershell
cd csharp-memoized
dotnet publish TicTacToeFast.cs -o out
.\out\TicTacToeFast.exe
```

This needs the C++ workload above. If the publish fails with a message about `vswhere.exe`, add
Visual Studio's installer folder to your `PATH` for that terminal and retry:

```powershell
$env:PATH += ";${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer"
```

`csharp-minimax` publishes as native too. For an ordinary (JIT) build of any of them, add
`-p:PublishAot=false`.

#### Regenerating the lookup table

`csharp-lookup-table/TicTacToeTable.cs` already contains its table. To rebuild it from scratch (the
result should be identical):

```powershell
cd csharp-lookup-table
dotnet run GenTable.cs
```

The same generator writes the assembly version's table. It picks C# or assembler output from the
file's extension:

```powershell
cd csharp-lookup-table
dotnet run GenTable.cs ../assembly-x64-lookup-table/TicTacToeTable.asm
```

and the state machine's tables, with `--state-machine`:

```powershell
cd csharp-lookup-table
dotnet run GenTable.cs ../assembly-x64-state-machine/TicTacToeStates.asm --state-machine
```

### MSIL

```powershell
cd msil
.\buildil.ps1
dotnet TicTacToeIL.dll
```

`buildil.ps1` assembles `TicTacToe.il` into `TicTacToeIL.dll`. The first run downloads the IL
assembler into `msil\.ilasm\`; set `$env:ILASM` to use your own `ilasm.exe` instead.

### x64 assembly (memoized, lookup table and state machine)

```powershell
cd assembly-x64-memoized
.\buildasm.ps1
.\TicTacToeAsm.exe
```

```powershell
cd assembly-x64-lookup-table
.\buildasm.ps1
.\TicTacToeAsmTable.exe
```

```powershell
cd assembly-x64-state-machine
.\buildasm.ps1
.\TicTacToeAsmStates.exe
```

Each `buildasm.ps1` finds Visual Studio, then assembles that directory's `.asm` file with `ml64` and
links it. The results are standalone executables that use no C runtime and no .NET: 4.5 KB for the
memoized version, 16 KB for the lookup table (which carries its 3,052-position table) and 91 KB for
the state machine (which carries about 89 KB of state tables).

The state machine never looks at the board to choose a move. It carries a state number: on its
turn it reads that state's set of best moves, picks one at random and steps to the next state, and
after your reply it steps again through a table. The board is kept only to draw it and to detect
a win.

If PowerShell refuses to run the scripts, start them with
`powershell -ExecutionPolicy Bypass -File .\buildil.ps1` (or `buildasm.ps1`).

## Benchmarking

Every version accepts `--bench`, which runs the computer's reply to each of the nine possible
opening moves 200 times and prints the time per move. For example:

```powershell
node tictactoe.js --bench
dotnet run TicTacToeFast.cs --bench
.\TicTacToeAsm.exe --bench
```

The two lines it prints are the first pass (cold) and the average of the remaining passes (warm).
The assembly version prints nanoseconds; the others print microseconds.

## Layout

```
javascript/            tictactoe.js
csharp-minimax/        TicTacToe.cs
csharp-memoized/       TicTacToeFast.cs
csharp-lookup-table/   TicTacToeTable.cs, GenTable.cs
msil/                  TicTacToe.il, buildil.ps1
assembly-x64-memoized/      TicTacToe.asm, buildasm.ps1
assembly-x64-lookup-table/  TicTacToeTable.asm, buildasm.ps1
assembly-x64-state-machine/ TicTacToeStates.asm, buildasm.ps1
README.md, benchmark.md
```
