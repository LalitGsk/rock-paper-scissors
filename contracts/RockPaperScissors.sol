pragma solidity ^0.4.17;

import "zeppelin-solidity/contracts/math/SafeMath.sol";
import "./Mortal.sol";

contract RockPaperScissors is Mortal {
  using SafeMath for uint;

  struct Game {
    address player1;
    address player2;
    bytes32 player1EncryptedMove;
    uint8 player2Move;
    uint8 winner;
    mapping(address => uint) bets;
    GameStatus status;
    uint256 joinDate;
  }

  // Status of a game
  enum GameStatus { Created, Joined, Revealed, Rescinded }

  // Number of games created. Also used for sequential identifiers
  uint public totalGames;

  // Mapping game id => game info
  mapping (uint256 => Game) public games;

  uint8[3][3] winnerLookup;

  uint constant REVEAL_PERIOD = 1440;

  // Modifiers
  modifier isValidMove(uint8 move) {
    require(move >= 0 && move < 3);
    _;
  }

  // Events
  event LogCreate(uint indexed gameId, uint amount, bytes32 indexed encryptedMove, address indexed player1);
  event LogJoin(uint indexed gameId, uint amount, uint8 indexed move, address indexed player2);
  event LogReveal(uint indexed gameId, uint8 indexed move, bytes32 secret, uint8 winner, address indexed player1);
  event LogWithdraw(uint indexed gameId, uint amount, address indexed recipient);
  event LogClaim(uint indexed gameId, uint amount, address indexed player2);
  event LogRescind(uint indexed gameId, uint amount, address indexed player1);
  
  // uint rock = 0;
  // uint paper = 1;
  // uint scissors = 2;
  function RockPaperScissors () public {
    winnerLookup[0][0] = 0; // tie
    winnerLookup[1][1] = 0; // tie
    winnerLookup[2][2] = 0; // tie
    winnerLookup[1][0] = 1; // player 1 wins (paper beats rock)
    winnerLookup[0][1] = 2; // player 2 wins (paper beats rock)
    winnerLookup[2][1] = 1; // player 1 wins (scissors beats paper)
    winnerLookup[1][2] = 2; // player 2 wins (scissors beats paper)
    winnerLookup[0][2] = 1; // player 1 wins (rock beats scissors)
    winnerLookup[2][0] = 2; // player 2 wins (rock beats scissors)
  }

  function createGame(bytes32 encryptedMove) public payable {
    Game storage game = games[totalGames];
    games[totalGames] = game;
    game.player1 = msg.sender;
    game.bets[msg.sender] = msg.value;
    game.player1EncryptedMove = encryptedMove;

    // Increment number of created games
    totalGames = totalGames.add(1);
    game.status = GameStatus.Created;
    
    LogCreate(totalGames, msg.value, encryptedMove, msg.sender);
  }

  function joinGame(uint8 player2Move, uint gameId) public payable isValidMove(player2Move) {
    Game storage game = games[gameId];

    // Can only join if game is in a 'Created' state
    require(game.status == GameStatus.Created);
    // ensure no one else has joined yet
    require(game.player2 == address(0));
    // ensure player 2 matches the bet  
    require(msg.value == game.bets[game.player1]);

    game.player2Move = player2Move;
    game.player2 = msg.sender;
    game.joinDate = block.timestamp;
    game.bets[msg.sender] = msg.value;
    game.status = GameStatus.Joined;
    
    LogJoin(gameId, msg.value, player2Move, msg.sender);
  }

  function reveal(uint gameId, uint8 player1Move, bytes32 secret) public isValidMove(player1Move) {
    Game storage game = games[gameId];
    
    address player1 = game.player1;
    address player2 = game.player2;
    uint bet;
    
    // make sure it's a valid move
    bytes32 player1EncryptedMove = keccak256(player1Move, secret);
    require(game.player1EncryptedMove == player1EncryptedMove);
    
    game.winner = getWinner(player1Move, game.player2Move);
    game.status = GameStatus.Revealed;
    
    if (game.winner == 1) {
      // transfer player 2's bet to player 1
      bet = game.bets[player2];
      game.bets[player2] = 0;
      game.bets[player1] = game.bets[player1].add(bet);
    } else if(game.winner == 2) {
      // transfer player 1's bet to player 2
      bet = game.bets[player1];
      game.bets[player1] = 0;
      game.bets[player2] = game.bets[player2].add(bet);
    }

    LogReveal(gameId, player1Move, secret, game.winner, msg.sender);
  }

  function withdraw(uint gameId) public {
    Game storage game = games[gameId];
    
    // players can only withdraw if in revealed state
    require(game.status == GameStatus.Revealed);
    require(game.bets[msg.sender] > 0);
    
    uint winnings = game.bets[msg.sender];
    game.bets[msg.sender] = 0;

    LogWithdraw(gameId, winnings, msg.sender);
    msg.sender.transfer(winnings);
  }

  function claim(uint gameId) public {
    Game storage game = games[gameId];
    
    require(block.timestamp >= game.joinDate + REVEAL_PERIOD);
    require(game.player2 == msg.sender);
    require(game.status == GameStatus.Joined);
    require(game.bets[game.player1] > 0 && game.bets[game.player2] > 0);
    
    // transfer player 1's bet to player 2
    uint winnings = game.bets[game.player1].add(game.bets[game.player2]);
    game.bets[game.player1] = 0;
    game.bets[game.player2] = 0;
        
    LogClaim(gameId, winnings, msg.sender);
    msg.sender.transfer(winnings);
  }

  function rescindGame(uint gameId) public {
    Game storage game = games[gameId];
    // player one can only rescind a game if still in 'Created' state
    require(game.status == GameStatus.Created);
    // only player one can rescind a game
    require(game.player1 == msg.sender);

    game.status = GameStatus.Rescinded;

    uint bet = game.bets[game.player1];
    game.bets[game.player1] = 0;
    
    LogRescind(gameId, bet, msg.sender);
    msg.sender.transfer(bet);
  }

  function encryptMove(uint8 move, bytes32 secret) public pure returns (bytes32 encryptedMove) {
    return keccak256(move, secret);
  }

  function getBet(uint gameId, address player) public view returns(uint) {
    Game storage game = games[gameId];
    return game.bets[player];
  }

  function getWinner(uint8 player1Move, uint8 player2Move) public view returns(uint8 winner) {
    return winnerLookup[player1Move][player2Move];
  }

  // Fallback function
  function() public {
    revert();
  }
}
