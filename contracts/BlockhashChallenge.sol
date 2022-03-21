//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "/interfaces/IHistoricalBlockhashes.sol";
import ".//libraries/RLPReader.sol";

contract BlockhashChallenge {
    using RLPReader for bytes;
    using RLPReader for uint;
    using RLPReader for RLPReader.RLPItem;
    using RLPReader for RLPReader.Iterator;

    address challenger; //party challenging the claim
    uint256 initBlock; //block in which challenge was started
    IHistoricalBlockhashes hb;
    Challenge public challenge;
    //probably can pack this
    struct Challenge {
        uint256 fromBlockNumber; //start of challenged interval
        uint256 toBlockNumber; //end of challenged interval
        bytes32 lastAgreedBlockHash;
        bytes32 firstHash; //claimed hash at fromBlockNumber
        bytes32 secondHash; //claimed hash at floor((fromBlockNumber + toBlockNumber)/2)
        uint256 lastTurn;
        uint8 turn; //0: claimer turn, 1: challenger turn
    }


    constructor(
        bytes32 _claimId,
        address _challenger, 
        address _hb,
        uint256 fromBlockNumber,
        uint256 toBlockNumber,
        bytes32 initBlockHash,
        bytes32 firstHash,
        bytes32 secondHash,
        
    ) {
        claimId = _claimId;
        initBlock = _initBlock;
        challenger = _challenger;
        hb = IHistricalBlockhashes(_hb);
        challenge = Challenge(
            fromBlockNumber, 
            toBlockNumber,
            _initBlockHash,
            firstHash,
            secondHash,
            0
        )
    }

    function respondToChallengeOneStep(bool half, bytes32 parentHash, bytes calldata rlpHeader) external {
        uint256 toBlockNumber = challenge.toBlockNumber;
        uint256 fromBlockNumber = challenge.fromBlockNumber;
        uint256 currentIntervalDiff = toBlockNumber - fromBlockNumber;
        uint256 diff;
        uint256 turn = challenge.turn;
        require(turn == 0 && msg.sender == hb.getClaimer(claimId) || turn == 1 && msg.sender == challenger, 
            "It is not time for interact proof or it is not your turn");
        //if difference is odd number 2n + 1, let first half be n blocks and second half be n + 1 blocks
        //if difference is even number 2n, let both halves be n blocks long
        if(half) {
            //challenging first half
            diff = currentIntervalDiff/2 + currentIntervalDiff % 2;
            require(currentIntervalDiff - diff == 1, "You must do an interactive proof now");
            require(parentHash != challenge.firstHash, "Cannot claim same hashes and other party");
            //both parties agreed upon the lastAgreedBlockHash, so they can both provide a header for it
            //secondHash is the lastAgreedBlockHash, since challenging first half, just reference to challenge.secondHash
            //to avoid an SSTORE
            //party is challenging first half, so they agree with what the other claimed about the second half,
            //so they agree upon an earlier blockhash
            //IF YOU DISAGREE WITH BOTH HALVES, CHALLENGE THE LATER ONE
            require(keccak256(rlpHeader) == challenge.secondHash, "Header does not hash to agreed hash");
        } else {
            //challenging second half
            diff = currentIntervalDiff/2;
            require(currentIntervalDiff - diff == 1, "You must do an interactive proof now");
            require(parentHash != challenge.secondHash, "Cannot claim same hashes and other party");
            //both parties agreed upon the lastAgreedBlockHash, so they can both provide a header for it
            require(keccak256(rlpHeader) == challenge.lastAgreedBlockHash, "Header does not hash to agreed hash");
        }
        //end challenge with challenger or claimer winning based off turn
        if(rlpBlockHeaderToParentHash(rlpHeader) == parentHash) {
            //the header encodes the claimed parentHash
            endChallenge(turn == 2)
        } else {
            //the header doesnt encode the claimed parentHash, why would you call this?
            endChallenge(turn == 0);
        }
    }

    function respondToChallengeInteractive(bool half, bytes32 firstHash, bytes32 secondHash) external {
        uint256 currentIntervalDiff = challenge.toBlockNumber - challenge.fromBlockNumber;
        require(block.number < challenge.lastTurn + hb.getFraudProofPeriod(claimId), "It is past the fraud proof period");
        require(currentIntervalDiff == 1, "You must do a interactive proof now, the one step section is later");
        uint256 turn = challenge.turn;
        require(turn == 0 && msg.sender == hb.getClaimer(claimId) || turn == 1 && msg.sender == challenger, 
            "It is not time for interact proof or it is not your turn");
        //if difference is odd number 2n + 1, let first half be n blocks and second half be n + 1 blocks
        //if difference is even number 2n, let both halves be n blocks long
        if(half) {
            //challenging first half
            if(currentIntervalDiff % 2 == 1) {
                diff = (currentIntervalDiff + 1)/2;
            }else {
                diff = currentIntervalDiff/2;
            }
            //party is challenging first half, so they agree with what the other claimed about the second half,
            //so they agree upon an earlier blockhash
            //IF YOU DISAGREE WITH BOTH HALVES, CHALLENGE THE LATER ONE
            //set the new interval to the current interval minus the second half
            challenge.lastAgreedBlockHash = challenge.secondHash;
            toBlockNumber -= diff; 
            challenge.toBlockNumber = toBlockNumber;
            require(firstHash != challenge.firstHash, "Cannot claim same hashes and other party");
        } else {
            //challenging second half
            diff = currentIntervalDiff/2;
            //set the new interval to the current interval minus the second half
            fromBlockNumber += diff;
            challenge.fromBlockNumber = fromBlockNumber;
            require(firstHash != challenge.secondHash, "Cannot claim same hashes and other party");
        }
        
        //if interval is of length 1, revert, because a onestep proof must be done
        require(currentIntervalDiff - diff != 1, "You must do a one step proof now")
        // switch to interactive for other party
        challenge.turn = turn == 0 ? 1 : 0;
        challenge.firstHash = firstHash;
        challenge.secondHash = secondHash;
        challenge.lastTurn = block.number;
    }

    function rlpBlockHeaderToParentHash(bytes calldata rlpHeader) public pure returns (bytes32) {
        RLPReader.Iterator memory it = rlpHeader.toRlpItem().iterator();
        return bytes32(it.next().toUint());
    }

    function timeout() external {
        require(block.number > challenge.lastTurn + hb.getFraudProofPeriod(claimId), "It is not past the fraud proof period");
        //end challenge with challenger or claimer winning based off turn
        endChallenge(challenge.turn == 0);
    }

    function endChallenge(bool challengeSuccessful) internal {
        hb.resolveChallenge(claimId, challengeSuccessful ? challenger : address(0));
        selfdestruct()
    }

}
