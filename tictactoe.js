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
function minimax(board, player, depth) {
  const w = winner(board);
  if (w === COMPUTER) return 10 - depth;
  if (w === HUMAN) return depth - 10;
  if (isFull(board)) return 0;

  const scores = [];
  for (let i = 0; i < 9; i++) {
    if (board[i]) continue;
    board[i] = player;
    scores.push(minimax(board, player === COMPUTER ? HUMAN : COMPUTER, depth + 1));
    board[i] = null;
  }
  return player === COMPUTER ? Math.max(...scores) : Math.min(...scores);
}

function computerMove(board) {
  let best = -Infinity;
  let moves = [];
  for (let i = 0; i < 9; i++) {
    if (board[i]) continue;
    board[i] = COMPUTER;
    const score = minimax(board, HUMAN, 1);
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

main();
