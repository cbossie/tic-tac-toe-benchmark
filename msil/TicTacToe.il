// Hand-written MSIL port of csharp-memoized/TicTacToeFast.cs: bitboards, a win lookup table and a memoised
// solver. buildil.ps1 assembles it; by hand:
//
//   ilasm /exe /output=TicTacToeIL.dll TicTacToe.il
//   dotnet TicTacToeIL.dll            (needs TicTacToeIL.runtimeconfig.json next to it)

.assembly extern System.Runtime
{
  .publickeytoken = (B0 3F 5F 7F 11 D5 0A 3A)
  .ver 10:0:0:0
}
.assembly extern System.Console
{
  .publickeytoken = (B0 3F 5F 7F 11 D5 0A 3A)
  .ver 10:0:0:0
}
.assembly TicTacToeIL { }
.module TicTacToeIL.dll

.class private auto ansi abstract sealed beforefieldinit Program
{
  // Wins[mask] is true when the squares in mask contain a line.
  .field private static bool[] Wins
  // Memo of exact position values indexed by (mover | other << 9); 0 = unknown, else value + 11.
  .field private static uint8[] Cache
  .field private static class [System.Runtime]System.Random Rng

  .method private hidebysig static void Main(string[] args) cil managed
  {
    .entrypoint
    .maxstack 3
    .locals init (int32 k)

    call void Program::Init()

    // if any argument is "--bench", run the benchmark instead
    ldc.i4.0
    stloc k
  ARGS:
    ldloc k
    ldarg.0
    ldlen
    conv.i4
    bge.s NOARG
    ldarg.0
    ldloc k
    ldelem.ref
    ldstr "--bench"
    call bool [System.Runtime]System.String::op_Equality(string, string)
    brfalse.s NEXTARG
    call void Program::Bench()
    ret
  NEXTARG:
    ldloc k
    ldc.i4.1
    add
    stloc k
    br.s ARGS
  NOARG:

    ldstr "Tic-Tac-Toe: you are X, computer is O."
    call void [System.Console]System.Console::WriteLine(string)
  AGAIN:
    call void Program::PlayGame()
    ldstr "\nPlay again? (y/n): "
    call void [System.Console]System.Console::Write(string)
    call string [System.Console]System.Console::ReadLine()
    dup
    brtrue.s HAVE
    pop
    ldstr ""
  HAVE:
    callvirt instance string [System.Runtime]System.String::Trim()
    ldstr "y"
    ldc.i4.5                       // StringComparison.OrdinalIgnoreCase
    callvirt instance bool [System.Runtime]System.String::StartsWith(string, valuetype [System.Runtime]System.StringComparison)
    brtrue.s AGAIN
    ret
  }

  .method private hidebysig static void Init() cil managed
  {
    .maxstack 4
    .locals init (int32[] lines, int32 mask, int32 j)

    ldc.i4.8
    newarr [System.Runtime]System.Int32
    stloc lines
    ldloc lines  ldc.i4.0  ldc.i4 7    stelem.i4   // rows
    ldloc lines  ldc.i4.1  ldc.i4 56   stelem.i4
    ldloc lines  ldc.i4.2  ldc.i4 448  stelem.i4
    ldloc lines  ldc.i4.3  ldc.i4 73   stelem.i4   // columns
    ldloc lines  ldc.i4.4  ldc.i4 146  stelem.i4
    ldloc lines  ldc.i4.5  ldc.i4 292  stelem.i4
    ldloc lines  ldc.i4.6  ldc.i4 273  stelem.i4   // diagonals
    ldloc lines  ldc.i4.7  ldc.i4 84   stelem.i4

    ldc.i4 512
    newarr [System.Runtime]System.Boolean
    stsfld bool[] Program::Wins
    ldc.i4 262144
    newarr [System.Runtime]System.Byte
    stsfld uint8[] Program::Cache
    newobj instance void [System.Runtime]System.Random::.ctor()
    stsfld class [System.Runtime]System.Random Program::Rng

    ldc.i4.0
    stloc mask
  MASKLOOP:
    ldloc mask
    ldc.i4 512
    bge.s DONE
    ldc.i4.0
    stloc j
  LINELOOP:
    ldloc j
    ldc.i4.8
    bge.s NEXTMASK
    ldloc mask
    ldloc lines
    ldloc j
    ldelem.i4
    and
    ldloc lines
    ldloc j
    ldelem.i4
    bne.un.s NEXTLINE
    ldsfld bool[] Program::Wins
    ldloc mask
    ldc.i4.1
    stelem.i1
  NEXTLINE:
    ldloc j
    ldc.i4.1
    add
    stloc j
    br.s LINELOOP
  NEXTMASK:
    ldloc mask
    ldc.i4.1
    add
    stloc mask
    br.s MASKLOOP
  DONE:
    ret
  }

  // One ply further from the end: moves a score a step closer to zero.
  .method private hidebysig static int32 Toward(int32 score) cil managed
  {
    .maxstack 2
    ldarg.0
    ldc.i4.0
    ble.s NOTPOSITIVE
    ldarg.0
    ldc.i4.1
    sub
    ret
  NOTPOSITIVE:
    ldarg.0
    ldc.i4.0
    bge.s ZERO
    ldarg.0
    ldc.i4.1
    add
    ret
  ZERO:
    ldc.i4.0
    ret
  }

  // Value of the position for the side to move (mover); other just moved. A win k plies away
  // is 10 - k, so the scores match the other versions.
  .method private hidebysig static int32 Value(int32 mover, int32 other) cil managed
  {
    .maxstack 4
    .locals init (int32 occ, int32 key, int32 cached, int32 best, int32 free, int32 bit)

    ldsfld bool[] Program::Wins
    ldarg.1
    ldelem.u1
    brfalse.s NOTLOST
    ldc.i4 -10
    ret
  NOTLOST:
    ldarg.0
    ldarg.1
    or
    stloc occ
    ldloc occ
    ldc.i4 511
    bne.un.s NOTFULL
    ldc.i4.0
    ret
  NOTFULL:
    ldarg.0
    ldarg.1
    ldc.i4.s 9
    shl
    or
    stloc key
    ldsfld uint8[] Program::Cache
    ldloc key
    ldelem.u1
    stloc cached
    ldloc cached
    brfalse.s COMPUTE
    ldloc cached
    ldc.i4.s 11
    sub
    ret
  COMPUTE:
    ldc.i4.s -11
    stloc best
    ldloc occ
    not
    ldc.i4 511
    and
    stloc free
  MOVELOOP:
    ldloc free
    brfalse.s STORE
    ldloc free                     // bit = free & -free (lowest set bit)
    ldloc free
    neg
    and
    stloc bit
    ldloc free
    ldloc bit
    xor
    stloc free
    ldarg.1                        // score = Toward(-Value(other, mover | bit))
    ldarg.0
    ldloc bit
    or
    call int32 Program::Value(int32, int32)
    neg
    call int32 Program::Toward(int32)
    dup
    ldloc best
    ble.s DISCARD
    stloc best
    br.s MOVELOOP
  DISCARD:
    pop
    br.s MOVELOOP
  STORE:
    ldsfld uint8[] Program::Cache
    ldloc key
    ldloc best
    ldc.i4.s 11
    add
    stelem.i1
    ldloc best
    ret
  }

  .method private hidebysig static int32 ComputerMove(int32 human, int32 computer) cil managed
  {
    .maxstack 4
    .locals init (int32 occ, int32 best, int32 bestMoves, int32 free, int32 bit, int32 score, int32 pick)

    ldarg.0
    ldarg.1
    or
    stloc occ
    ldloc occ
    brtrue.s SEARCH
    // Every opening move draws against perfect play, so skip the search.
    ldsfld class [System.Runtime]System.Random Program::Rng
    ldc.i4.s 9
    callvirt instance int32 [System.Runtime]System.Random::Next(int32)
    ret
  SEARCH:
    ldc.i4 -2147483648
    stloc best
    ldc.i4.0
    stloc bestMoves
    ldloc occ
    not
    ldc.i4 511
    and
    stloc free
  MOVELOOP:
    ldloc free
    brfalse.s PICK
    ldloc free
    ldloc free
    neg
    and
    stloc bit
    ldloc free
    ldloc bit
    xor
    stloc free
    ldarg.0                        // score = Toward(-Value(human, computer | bit))
    ldarg.1
    ldloc bit
    or
    call int32 Program::Value(int32, int32)
    neg
    call int32 Program::Toward(int32)
    stloc score
    ldloc score
    ldloc best
    ble.s NOTBETTER
    ldloc score
    stloc best
    ldloc bit
    stloc bestMoves
    br.s MOVELOOP
  NOTBETTER:
    ldloc score
    ldloc best
    bne.un.s MOVELOOP
    ldloc bestMoves
    ldloc bit
    or
    stloc bestMoves
    br.s MOVELOOP
  PICK:
    // pick uniformly among the best moves: drop `pick` low bits, answer the lowest one left
    ldsfld class [System.Runtime]System.Random Program::Rng
    ldloc bestMoves
    call int32 [System.Runtime]System.Numerics.BitOperations::PopCount(uint32)
    callvirt instance int32 [System.Runtime]System.Random::Next(int32)
    stloc pick
  DROP:
    ldloc pick
    ldc.i4.0
    ble.s DONE
    ldloc bestMoves
    ldloc bestMoves
    ldc.i4.1
    sub
    and
    stloc bestMoves
    ldloc pick
    ldc.i4.1
    sub
    stloc pick
    br.s DROP
  DONE:
    ldloc bestMoves
    call int32 [System.Runtime]System.Numerics.BitOperations::TrailingZeroCount(int32)
    ret
  }

  // 'X', 'O' or the square's number.
  .method private hidebysig static char Sq(int32 human, int32 computer, int32 i) cil managed
  {
    .maxstack 3
    ldarg.0
    ldarg.2
    shr
    ldc.i4.1
    and
    brfalse.s NOTX
    ldc.i4.s 88                    // 'X'
    ret
  NOTX:
    ldarg.1
    ldarg.2
    shr
    ldc.i4.1
    and
    brfalse.s NOTO
    ldc.i4.s 79                    // 'O'
    ret
  NOTO:
    ldc.i4.s 49                    // '1' + i
    ldarg.2
    add
    ret
  }

  .method private hidebysig static void Render(int32 human, int32 computer) cil managed
  {
    .maxstack 4
    .locals init (int32 r)

    ldstr "\n"
    call void [System.Console]System.Console::Write(string)
    ldc.i4.0
    stloc r
  ROW:
    ldloc r
    ldc.i4.3
    bge END
    ldloc r
    brfalse.s NOSEP
    ldstr "---+---+---\n"
    call void [System.Console]System.Console::Write(string)
  NOSEP:
    ldstr " "
    call void [System.Console]System.Console::Write(string)
    ldarg.0
    ldarg.1
    ldloc r
    ldc.i4.3
    mul
    call char Program::Sq(int32, int32, int32)
    call void [System.Console]System.Console::Write(char)
    ldstr " | "
    call void [System.Console]System.Console::Write(string)
    ldarg.0
    ldarg.1
    ldloc r
    ldc.i4.3
    mul
    ldc.i4.1
    add
    call char Program::Sq(int32, int32, int32)
    call void [System.Console]System.Console::Write(char)
    ldstr " | "
    call void [System.Console]System.Console::Write(string)
    ldarg.0
    ldarg.1
    ldloc r
    ldc.i4.3
    mul
    ldc.i4.2
    add
    call char Program::Sq(int32, int32, int32)
    call void [System.Console]System.Console::Write(char)
    ldstr " \n"
    call void [System.Console]System.Console::Write(string)
    ldloc r
    ldc.i4.1
    add
    stloc r
    br ROW
  END:
    ldstr "\n"
    call void [System.Console]System.Console::Write(string)
    ret
  }

  .method private hidebysig static int32 AskHumanMove(int32 occupied) cil managed
  {
    .maxstack 3
    .locals init (string input, int32 n)
  ASK:
    ldstr "Your move (1-9): "
    call void [System.Console]System.Console::Write(string)
    call string [System.Console]System.Console::ReadLine()
    stloc input
    ldloc input
    brtrue.s HAVE
    ldc.i4.0                       // stdin closed
    call void [System.Runtime]System.Environment::Exit(int32)
  HAVE:
    ldloc input
    callvirt instance string [System.Runtime]System.String::Trim()
    ldloca n
    call bool [System.Runtime]System.Int32::TryParse(string, [out] int32&)
    brfalse.s BAD
    ldloc n
    ldc.i4.1
    blt.s BAD
    ldloc n
    ldc.i4.s 9
    bgt.s BAD
    ldarg.0
    ldloc n
    ldc.i4.1
    sub
    shr
    ldc.i4.1
    and
    brtrue.s BAD
    ldloc n
    ldc.i4.1
    sub
    ret
  BAD:
    ldstr "Pick an empty square numbered 1-9."
    call void [System.Console]System.Console::WriteLine(string)
    br.s ASK
  }

  .method private hidebysig static void PlayGame() cil managed
  {
    .maxstack 4
    .locals init (int32 human, int32 comp, bool humanFirst, bool humansTurn, int32 move)

    ldsfld class [System.Runtime]System.Random Program::Rng
    ldc.i4.2
    callvirt instance int32 [System.Runtime]System.Random::Next(int32)
    ldc.i4.0
    ceq
    stloc humanFirst
    ldloc humanFirst
    brfalse.s COMPFIRST
    ldstr "\nYou go first."
    call void [System.Console]System.Console::WriteLine(string)
    ldc.i4.0
    ldc.i4.0
    call void Program::Render(int32, int32)
    br.s START
  COMPFIRST:
    ldstr "\nComputer goes first."
    call void [System.Console]System.Console::WriteLine(string)
  START:
    ldloc humanFirst
    stloc humansTurn
  TURN:
    ldloc humansTurn
    brfalse.s COMPUTERTURN
    ldloc human
    ldc.i4.1
    ldloc human
    ldloc comp
    or
    call int32 Program::AskHumanMove(int32)
    shl
    or
    stloc human
    br.s SHOWBOARD
  COMPUTERTURN:
    ldloc human
    ldloc comp
    call int32 Program::ComputerMove(int32, int32)
    stloc move
    ldloc comp
    ldc.i4.1
    ldloc move
    shl
    or
    stloc comp
    ldstr "\nComputer plays "
    call void [System.Console]System.Console::Write(string)
    ldloc move
    ldc.i4.1
    add
    call void [System.Console]System.Console::Write(int32)
    ldstr "."
    call void [System.Console]System.Console::WriteLine(string)
  SHOWBOARD:
    ldloc human
    ldloc comp
    call void Program::Render(int32, int32)

    ldsfld bool[] Program::Wins
    ldloc human
    ldelem.u1
    brfalse.s HUMANNOTWON
    ldstr "You win!"
    call void [System.Console]System.Console::WriteLine(string)
    ret
  HUMANNOTWON:
    ldsfld bool[] Program::Wins
    ldloc comp
    ldelem.u1
    brfalse.s COMPNOTWON
    ldstr "Computer wins!"
    call void [System.Console]System.Console::WriteLine(string)
    ret
  COMPNOTWON:
    ldloc human
    ldloc comp
    or
    ldc.i4 511
    bne.un.s NEXTTURN
    ldstr "It's a draw."
    call void [System.Console]System.Console::WriteLine(string)
    ret
  NEXTTURN:
    ldloc humansTurn
    ldc.i4.0
    ceq
    stloc humansTurn
    br TURN
  }

  // Same workload as the --bench flag in the C# versions.
  .method private hidebysig static void Bench() cil managed
  {
    .maxstack 4
    .locals init (int32 rep, int32 i, int64 t, int64 cold, int64 warm, float64 usPerTick)

    ldc.i4.0
    stloc rep
  REPLOOP:
    ldloc rep
    ldc.i4 200
    bge.s REPORT
    call int64 [System.Runtime]System.Diagnostics.Stopwatch::GetTimestamp()
    stloc t
    ldc.i4.0
    stloc i
  OPENINGLOOP:
    ldloc i
    ldc.i4.s 9
    bge.s OPENINGSDONE
    ldc.i4.1
    ldloc i
    shl
    ldc.i4.0
    call int32 Program::ComputerMove(int32, int32)
    pop
    ldloc i
    ldc.i4.1
    add
    stloc i
    br.s OPENINGLOOP
  OPENINGSDONE:
    call int64 [System.Runtime]System.Diagnostics.Stopwatch::GetTimestamp()
    ldloc t
    sub
    stloc t                        // elapsed
    ldloc rep
    brtrue.s WARM
    ldloc t
    stloc cold
    br.s NEXTREP
  WARM:
    ldloc warm
    ldloc t
    add
    stloc warm
  NEXTREP:
    ldloc rep
    ldc.i4.1
    add
    stloc rep
    br.s REPLOOP
  REPORT:
    ldc.r8 1000000.0
    ldsfld int64 [System.Runtime]System.Diagnostics.Stopwatch::Frequency
    conv.r8
    div
    stloc usPerTick
    ldstr "first pass : "
    call void [System.Console]System.Console::Write(string)
    ldloc cold
    conv.r8
    ldloc usPerTick
    mul
    ldc.r8 9.0
    div
    ldc.i4.1
    call float64 [System.Runtime]System.Math::Round(float64, int32)
    call void [System.Console]System.Console::Write(float64)
    ldstr " us/move"
    call void [System.Console]System.Console::WriteLine(string)
    ldstr "later passes: "
    call void [System.Console]System.Console::Write(string)
    ldloc warm
    conv.r8
    ldloc usPerTick
    mul
    ldc.r8 1791.0                  // 9 * 199
    div
    ldc.i4.2
    call float64 [System.Runtime]System.Math::Round(float64, int32)
    call void [System.Console]System.Console::Write(float64)
    ldstr " us/move"
    call void [System.Console]System.Console::WriteLine(string)
    ret
  }
}
