const readline = require("readline");

const LINES = [
  [0, 1, 2], [3, 4, 5], [6, 7, 8],
  [0, 3, 6], [1, 4, 7], [2, 5, 8],
  [0, 4, 8], [2, 4, 6],
];

const HUMAN = "X";
const COMPUTER = "O";

function winner(board) {
  for (const [a, b, c] of LINES) {
    if (board[a] && board[a] === board[b] && board[a] === board[c]) return board[a];
  }
  return null;
}

function isFull(board) {
  return board.every((cell) => cell);
}

function render(board) {
  const cell = (i) => board[i] || String(i + 1);
  const row = (r) => ` ${cell(r)} | ${cell(r + 1)} | ${cell(r + 2)} `;
  const sep = "---+---+---";
  console.log(`\n${row(0)}\n${sep}\n${row(3)}\n${sep}\n${row(6)}\n`);
}

// Minimax: positive score favours the computer.
// Alpha-beta pruning; a full window at the root keeps every move's score exact.
function minimax(board, player, depth, alpha, beta) {
  const w = winner(board);
  if (w === COMPUTER) return 10 - depth;
  if (w === HUMAN) return depth - 10;
  if (isFull(board)) return 0;

  const maximizing = player === COMPUTER;
  let best = maximizing ? -Infinity : Infinity;
  for (let i = 0; i < 9; i++) {
    if (board[i]) continue;
    board[i] = player;
    const score = minimax(board, maximizing ? HUMAN : COMPUTER, depth + 1, alpha, beta);
    board[i] = null;
    if (maximizing) {
      if (score > best) best = score;
      if (best > alpha) alpha = best;
    } else {
      if (score < best) best = score;
      if (best < beta) beta = best;
    }
    if (alpha >= beta) break;
  }
  return best;
}

function computerMove(board) {
  // Every opening move draws against perfect play, so skip the search.
  if (board.every((cell) => !cell)) return Math.floor(Math.random() * 9);

  let best = -Infinity;
  let moves = [];
  for (let i = 0; i < 9; i++) {
    if (board[i]) continue;
    board[i] = COMPUTER;
    const score = minimax(board, HUMAN, 1, -Infinity, Infinity);
    board[i] = null;
    if (score > best) {
      best = score;
      moves = [i];
    } else if (score === best) {
      moves.push(i);
    }
  }
  return moves[Math.floor(Math.random() * moves.length)];
}

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
const ask = (q) => new Promise((resolve) => rl.question(q, resolve));

async function playGame() {
  const board = Array(9).fill(null);
  const humanFirst = Math.random() < 0.5;
  console.log(humanFirst ? "\nYou go first." : "\nComputer goes first.");

  let turn = humanFirst ? HUMAN : COMPUTER;
  if (humanFirst) render(board);

  while (true) {
    if (turn === HUMAN) {
      while (true) {
        const n = Number((await ask("Your move (1-9): ")).trim());
        if (Number.isInteger(n) && n >= 1 && n <= 9 && !board[n - 1]) {
          board[n - 1] = HUMAN;
          break;
        }
        console.log("Pick an empty square numbered 1-9.");
      }
    } else {
      const move = computerMove(board);
      board[move] = COMPUTER;
      console.log(`\nComputer plays ${move + 1}.`);
    }
    render(board);

    const w = winner(board);
    if (w) return console.log(w === HUMAN ? "You win!" : "Computer wins!");
    if (isFull(board)) return console.log("It's a draw.");
    turn = turn === HUMAN ? COMPUTER : HUMAN;
  }
}

async function main() {
  console.log("Tic-Tac-Toe: you are X, computer is O.");
  do {
    await playGame();
  } while ((await ask("\nPlay again? (y/n): ")).trim().toLowerCase().startsWith("y"));
  rl.close();
}

// The computer replies to each of the nine possible human openings, many times over.
// The other versions run the same workload with their own --bench flag.
function bench() {
  const reps = 200;
  let coldNs = 0n;
  let warmNs = 0n;
  for (let rep = 0; rep < reps; rep++) {
    const start = process.hrtime.bigint();
    for (let i = 0; i < 9; i++) {
      const board = Array(9).fill(null);
      board[i] = HUMAN;
      computerMove(board);
    }
    const elapsed = process.hrtime.bigint() - start;
    if (rep === 0) coldNs = elapsed;
    else warmNs += elapsed;
  }
  console.log(`first pass : ${(Number(coldNs) / 9 / 1000).toFixed(1)} us/move`);
  console.log(`later passes: ${(Number(warmNs) / (9 * (reps - 1)) / 1000).toFixed(2)} us/move`);
}

if (process.argv.includes("--bench")) {
  rl.close();
  bench();
} else {
  main();
}
