const char Human = 'X';
const char Computer = 'O';
const char Empty = ' ';

int[][] lines =
[
    [0, 1, 2], [3, 4, 5], [6, 7, 8],
    [0, 3, 6], [1, 4, 7], [2, 5, 8],
    [0, 4, 8], [2, 4, 6],
];

var rng = new Random();

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

void PlayGame()
{
    var board = new char[9];
    Array.Fill(board, Empty);

    bool humanFirst = rng.Next(2) == 0;
    Console.WriteLine(humanFirst ? "\nYou go first." : "\nComputer goes first.");
    if (humanFirst) Render(board);

    char turn = humanFirst ? Human : Computer;
    while (true)
    {
        if (turn == Human)
        {
            board[AskHumanMove(board)] = Human;
        }
        else
        {
            int move = ComputerMove(board);
            board[move] = Computer;
            Console.WriteLine($"\nComputer plays {move + 1}.");
        }
        Render(board);

        char w = Winner(board);
        if (w != Empty)
        {
            Console.WriteLine(w == Human ? "You win!" : "Computer wins!");
            return;
        }
        if (IsFull(board))
        {
            Console.WriteLine("It's a draw.");
            return;
        }
        turn = turn == Human ? Computer : Human;
    }
}

int AskHumanMove(char[] board)
{
    while (true)
    {
        Console.Write("Your move (1-9): ");
        string? input = Console.ReadLine();
        if (input is null) Environment.Exit(0); // stdin closed
        if (int.TryParse(input.Trim(), out int n) && n is >= 1 and <= 9 && board[n - 1] == Empty)
            return n - 1;
        Console.WriteLine("Pick an empty square numbered 1-9.");
    }
}

char Winner(char[] board)
{
    foreach (var l in lines)
    {
        char c = board[l[0]];
        if (c != Empty && c == board[l[1]] && c == board[l[2]]) return c;
    }
    return Empty;
}

bool IsFull(char[] board) => !board.Contains(Empty);

void Render(char[] board)
{
    char Cell(int i) => board[i] == Empty ? (char)('1' + i) : board[i];
    string Row(int r) => $" {Cell(r)} | {Cell(r + 1)} | {Cell(r + 2)} ";
    Console.WriteLine($"\n{Row(0)}\n---+---+---\n{Row(3)}\n---+---+---\n{Row(6)}\n");
}

// Minimax with alpha-beta pruning; a full window at the root keeps every move's score exact.
// Positive score favours the computer.
int Minimax(char[] board, char player, int depth, int alpha, int beta)
{
    char w = Winner(board);
    if (w == Computer) return 10 - depth;
    if (w == Human) return depth - 10;
    if (IsFull(board)) return 0;

    bool maximizing = player == Computer;
    int best = maximizing ? int.MinValue : int.MaxValue;
    for (int i = 0; i < 9; i++)
    {
        if (board[i] != Empty) continue;
        board[i] = player;
        int score = Minimax(board, maximizing ? Human : Computer, depth + 1, alpha, beta);
        board[i] = Empty;
        if (maximizing)
        {
            best = Math.Max(best, score);
            alpha = Math.Max(alpha, best);
        }
        else
        {
            best = Math.Min(best, score);
            beta = Math.Min(beta, best);
        }
        if (alpha >= beta) break;
    }
    return best;
}

// The computer replies to each of the nine possible human openings, many times over.
// csharp-memoized/TicTacToeFast.cs runs the same workload.
void Bench()
{
    const int Reps = 200;
    long sink = 0;
    long coldTicks = 0, warmTicks = 0;
    var board = new char[9];
    for (int rep = 0; rep < Reps; rep++)
    {
        long t = System.Diagnostics.Stopwatch.GetTimestamp();
        for (int i = 0; i < 9; i++)
        {
            Array.Fill(board, Empty);
            board[i] = Human;
            sink += ComputerMove(board);
        }
        long elapsed = System.Diagnostics.Stopwatch.GetTimestamp() - t;
        if (rep == 0) coldTicks = elapsed; else warmTicks += elapsed;
    }
    double usPerTick = 1e6 / System.Diagnostics.Stopwatch.Frequency;
    Console.WriteLine($"first pass : {coldTicks * usPerTick / 9:F1} us/move");
    Console.WriteLine($"later passes: {warmTicks * usPerTick / (9 * (Reps - 1)):F2} us/move");
}

int ComputerMove(char[] board)
{
    // Every opening move draws against perfect play, so skip the search.
    if (board.All(c => c == Empty)) return rng.Next(9);

    int best = int.MinValue;
    var moves = new List<int>();
    for (int i = 0; i < 9; i++)
    {
        if (board[i] != Empty) continue;
        board[i] = Computer;
        int score = Minimax(board, Human, 1, int.MinValue, int.MaxValue);
        board[i] = Empty;
        if (score > best)
        {
            best = score;
            moves.Clear();
            moves.Add(i);
        }
        else if (score == best)
        {
            moves.Add(i);
        }
    }
    return moves[rng.Next(moves.Count)];
}
