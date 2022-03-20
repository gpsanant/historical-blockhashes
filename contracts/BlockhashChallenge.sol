//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "/interfaces/IHistoricalBlockhashes.sol";

contract BlockhashChallenge {
    address challenger; //party challenging the claim
    uint256 initBlock; //block in which challenge was started
    IHistoricalBlockhashes hb;
    Challenge public challenge;
    //probably can pack this
    struct Challenge {
        uint256 fromBlockNumber; //start of challenged interval
        uint256 toBlockNumber; //end of challenged interval
        uint256 agreedBlockNumber; //earliest blockNumber that is after first challenged blockNumber that both parties agree on the blockhash
        bytes32 agreedBlockHash; //hash of earliest blockNumber that is after first challenged blockNumber that both parties agree on the blockhash
        bytes32 firstHash; //claimed hash at fromBlockNumber
        bytes32 secondHash; //claimed hash at floor((fromBlockNumber + toBlockNumber)/2)
        uint256 lastTurn;
        uint8 turn; //0: claimer turn (interactive), 1: claimer turn (one step), 2: challenger turn (interactive), 3: challenger turn (one step)
    }


    constructor(
        bytes32 _claimId,
        uint256 _initBlock,
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
            _initBlock,
            _initBlockHash,
            firstHash,
            secondHash,
            0
        )
    }

    function respondToChallengeInteractive(bool half, bytes32 firstHash, bytes32 secondHash) external {
        uint256 toBlockNumber = challenge.toBlockNumber;
        uint256 fromBlockNumber = challenge.fromBlockNumber;
        uint256 currentIntervalDiff = toBlockNumber - fromBlockNumber;
        uint256 diff;
        require(currentIntervalDiff != 1, "You must do a one step proof now, the interactive section is over");
        uint256 turn = challenge.turn;
        require(turn == 0 && msg.sender == hb.getClaimer(claimId) || turn == 2 && msg.sender == challenger, 
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
            challenge.agreedBlockHash = challenge.secondHash;
            //set the new interval to the current interval minus the second half
            toBlockNumber -= diff; 
            challenge.agreedBlockNumber = toBlockNumber;
            challenge.toBlockNumber = toBlockNumber;
        } else {
            //challenging second half
            diff = currentIntervalDiff/2;
            //set the new interval to the current interval minus the second half
            fromBlockNumber += diff;
            challenge.fromBlockNumber = fromBlockNumber;
        }
        challenge.firstHash = firstHash;
        challenge.secondHash = secondHash;
        challenge.lastTurn = block.number;
        //if interval is of length 1, then switch to one step for other party
        if(currentIntervalDiff - diff == 1) {
            if(turn == 0) {
                challenge.turn = 3;
            } else {
                challenge.turn = 1;
            }
        } else {
            //else switch to interactive for other party
            challenge.turn = turn + 1;
        }
    }

    function timeout() external {
        require(block.number > challenge.lastTurn + hb.getFraudProofPeriod(claimId), "It is not past the fraud proof period");
        uint8 turn = challenge.turn;
        if(turn < 2) {
            //claimer timed out
            endChallenge(true);
        } else {
            //challenger timed out
            endChallenge(false);
        }
    }

    function endChallenge(bool challengeSuccessful) internal {
        hb.resolveChallenge(claimId, challengeSuccessful ? challenger : address(0));
        selfdestruct()
    }

}
