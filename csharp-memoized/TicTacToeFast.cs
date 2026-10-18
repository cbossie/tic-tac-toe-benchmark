// `dotnet run` works anywhere. `dotnet publish TicTacToeFast.cs` builds a native exe with no JIT
// and no .NET startup, but needs the "Desktop development with C++" Visual Studio workload.
#:property PublishAot=true
#:property InvariantGlobalization=true
#:property UseSystemResourceKeys=true

using System.Diagnostics;
using System.Numerics;

if (args.Contains("--bench"))
{
    Bench();
    return;
}

Console.WriteLine("Tic-Tac-Toe: you are X, computer is O.");
do
{
    PlayGame();
    Console.Write("\nPlay again? (y/n): ");
} while ((Console.ReadLine() ?? "").Trim().StartsWith("y", StringComparison.OrdinalIgnoreCase));

static void PlayGame()
{
    int human = 0, computer = 0; // bitboards, bit i = square i+1
    bool humanFirst = Random.Shared.Next(2) == 0;
    Console.WriteLine(humanFirst ? "\nYou go first." : "\nComputer goes first.");
    if (humanFirst) Console.Write(Solver.Render(human, computer));

    bool humansTurn = humanFirst;
    while (true)
    {
        if (humansTurn)
        {
            human |= 1 << AskHumanMove(human | computer);
        }
        else
        {
            int move = Solver.ComputerMove(human, computer);
            computer |= 1 << move;
            Console.WriteLine($"\nComputer plays {move + 1}.");
        }
        Console.Write(Solver.Render(human, computer));

        if (Solver.Wins[human])
        {
            Console.WriteLine("You win!");
            return;
        }
        if (Solver.Wins[computer])
        {
            Console.WriteLine("Computer wins!");
            return;
        }
        if ((human | computer) == Solver.Full)
        {
            Console.WriteLine("It's a draw.");
            return;
        }
        humansTurn = !humansTurn;
    }
}

static int AskHumanMove(int occupied)
{
    while (true)
    {
        Console.Write("Your move (1-9): ");
        string? input = Console.ReadLine();
        if (input is null) Environment.Exit(0); // stdin closed
        if (int.TryParse(input.Trim(), out int n) && n is >= 1 and <= 9 && (occupied & (1 << (n - 1))) == 0)
            return n - 1;
        Console.WriteLine("Pick an empty square numbered 1-9.");
    }
}

// Same workload as the --bench flag in ../csharp-minimax/TicTacToe.cs: the computer replies to each of the
// nine possible human openings, many times over.
static void Bench()
{
    const int Reps = 200;
    long sink = 0;
    long coldTicks = 0, warmTicks = 0;
    for (int rep = 0; rep < Reps; rep++)
    {
        long t = Stopwatch.GetTimestamp();
        for (int i = 0; i < 9; i++) sink += Solver.ComputerMove(1 << i, 0);
        long elapsed = Stopwatch.GetTimestamp() - t;
        if (rep == 0) coldTicks = elapsed; else warmTicks += elapsed;
    }
    double usPerTick = 1e6 / Stopwatch.Frequency;
    Console.WriteLine($"first pass : {coldTicks * usPerTick / 9:F1} us/move");
    Console.WriteLine($"later passes: {warmTicks * usPerTick / (9 * (Reps - 1)):F2} us/move  (checksum {sink})");
}

static class Solver
{
    public const int Full = 0x1FF;

    // Wins[mask] is true when the set of squares in mask contains a line.
    public static readonly bool[] Wins = BuildWins();

    // Memo of exact position values, indexed by (mover | other << 9); 0 = not computed yet,
    // otherwise value + 11. Positions never depend on how they were reached, so it is shared by
    // every move of every game.
    static readonly byte[] Cache = new byte[1 << 18];

    static bool[] BuildWins()
    {
        int[] lines = [0b000_000_111, 0b000_111_000, 0b111_000_000,
                       0b001_001_001, 0b010_010_010, 0b100_100_100,
                       0b100_010_001, 0b001_010_100];
        var wins = new bool[1 << 9];
        for (int mask = 0; mask < wins.Length; mask++)
            foreach (int line in lines)
                if ((mask & line) == line) wins[mask] = true;
        return wins;
    }

    // Value of the position for the side to move (`mover`); `other` just moved. Positive means
    // the mover wins, larger means sooner. Scores match the other versions: a win k plies away
    // is 10 - k.
    static int Value(int mover, int other)
    {
        if (Wins[other]) return -10;
        int occupied = mover | other;
        if (occupied == Full) return 0;

        int key = mover | (other << 9);
        int cached = Cache[key];
        if (cached != 0) return cached - 11;

        int best = -11;
        int free = ~occupied & Full;
        while (free != 0)
        {
            int bit = free & -free;
            free ^= bit;
            int score = Toward(-Value(other, mover | bit));
            if (score > best) best = score;
        }
        Cache[key] = (byte)(best + 11);
        return best;
    }

    // One ply further from the end: moves a score a step closer to zero.
    static int Toward(int score) => score > 0 ? score - 1 : score < 0 ? score + 1 : 0;

    public static int ComputerMove(int human, int computer)
    {
        int occupied = human | computer;
        // Every opening move draws against perfect play, so skip the search.
        if (occupied == 0) return Random.Shared.Next(9);

        int best = int.MinValue;
        int bestMoves = 0; // bitboard of the best moves so far
        int free = ~occupied & Full;
        while (free != 0)
        {
            int bit = free & -free;
            free ^= bit;
            int score = Toward(-Value(human, computer | bit));
            if (score > best)
            {
                best = score;
                bestMoves = bit;
            }
            else if (score == best)
            {
                bestMoves |= bit;
            }
        }

        // Pick uniformly among the best moves.
        int pick = Random.Shared.Next(BitOperations.PopCount((uint)bestMoves));
        for (; pick > 0; pick--) bestMoves &= bestMoves - 1;
        return BitOperations.TrailingZeroCount(bestMoves);
    }

    public static string Render(int human, int computer)
    {
        Span<char> sq = stackalloc char[9];
        for (int i = 0; i < 9; i++)
            sq[i] = (human >> i & 1) != 0 ? 'X' : (computer >> i & 1) != 0 ? 'O' : (char)('1' + i);
        return $"\n {sq[0]} | {sq[1]} | {sq[2]} \n---+---+---\n {sq[3]} | {sq[4]} | {sq[5]} \n---+---+---\n {sq[6]} | {sq[7]} | {sq[8]} \n\n";
    }
}
