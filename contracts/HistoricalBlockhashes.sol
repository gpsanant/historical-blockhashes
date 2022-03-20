//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./interfaces/IERC20.sol";
import "./BlockhashChallenge.sol";
import ".//interfaces/IHistoricalBlockhashes";

contract HistoricalBlockhashes is IHistoricalBlockhashes {
    IERC20 public paymentToken;
    mapping(bytes32 => BlockhashClaim) public blockhashClaims;
    struct BlockhashClaim {
        address claimer;
        uint256 blockNumber;
        bytes32 hash;
        uint8 status; //0: final, 1: commited, 2: rejected
        address challenge;
        uint256 initBlock;
        uint256 collateral;
        uint256 fraudProofPeriod;
    }


    constructor() {}

    function claim(bytes32 claimId, uint256 blockNumber, bytes32 hash, uint256 collateral, uint256 fraudProofPeriod) external {
        //hopfully blockhash is never 0
        require(blockhashClaims[claimId].hash == bytes32(0), "ClaimId already used");
        //get collateral for claim
        paymentToken.transferFrom(msg.sender, address(this), collateral);
        //init storage
        blockhashClaims[claimId].claimer = msg.sender;
        blockhashClaims[claimId].blockNumber = blockNumber;
        blockhashClaims[claimId].hash = hash;
        blockhashClaims[claimId].status = 1;
        blockhashClaims[claimId].initBlock = block.number;
        blockhashClaims[claimId].collateral = collateral;
        blockhashClaims[claimId].fraudProofPeriod = fraudProofPeriod;
    }

    function finalize(bytes32 claimId, uint256 blockNumber, bytes32 hash, uint256 collateral, uint256 fraudProofPeriod) external {
        require(blockhashClaims[claimId].hash != bytes32(0), "Claim doesn't exist");
        require(blockhashClaims[claimId].status == 1 && block.number > blockhashClaims[claimId].initBlock + blockhashClaims[claimId].fraudProofPeriod,
                "Claim is not past fraud proof period");
        //pay back collateral for claim
        paymentToken.transfer(msg.sender, blockhashClaims[claimId].collateral);
        //finalize status
        blockhashClaims[claimId].status = 0;
    }

    function challenge(bytes32 claimId, uint256 blockNumber, bytes32 firstHash, bytes32 secondHash) external {
        require(blockhashClaims[claimId].hash != bytes32(0), "Claim doesn't exist");
        require(blockhashClaims[claimId].status == 1 
                && block.number < blockhashClaims[claimId].initBlock + blockhashClaims[claimId].fraudProofPeriod 
                && blockhashClaims[claimId] == address(0),
                "Claim is past fraud proof period");
        address challenge = address(new BlockhashChallenge(
            claimId,
            block.number - 1,
            msg.sender,
            address(this)
            blockhashClaims[claimId].blockNumber,
            block.number - 1,
            block.number - 1,
            blockhash(block.number - 1),
            firstHash, //challenger claimed hash at blockhashClaims[claimId].blockNumber
            secondHash, //challenger claimed hash at (blockhashClaims[claimId].blockNumber + block.number - 1)/2
        ))
        blockhashClaims[claimId].challenge = challenge;
        //move challenger collateral
        paymentToken.transferFrom(msg.sender, address(this), blockhashClaims[claimId].collateral);
        //send claimer collateral (at this contracts address) to challenge contract
        paymentToken.transfer(challenge, blockhashClaims[claimId].collateral);
        //challenged status
        blockhashClaims[claimId].status = 1;
    }

    function resolveChallenge(bytes32 claimId, address winner) external {
        require(msg.sender == blockhashClaims[claimId].challenge && blockhashClaims[claimId].status == 1, 
            "Only challenge can call this or claim is either not challenged")
        if(winner != address(0)) {
            //challenge was successful, give challenger their collateral AND the claimers 
            paymentToken.transfer(winner, 2*blockhashClaims[claimId].collateral);
            blockhashClaims[claimId].status = 2;
        } else {
            //challenge was unsuccessful, give claimer their collateral and set back to commit phase
            paymentToken.transfer(winner, 2*blockhashClaims[claimId].collateral);
            blockhashClaims[claimId].status = 1;
            blockhashClaims[claimId].initBlock = block.number;
            blockhashClaims[claimId].challenge = address(0);
        }
    }

    function getClaimer(bytes32 claimId) public view returns(address) {
        return blockhashClaims[claimId].claimer;
    }

    function getFraudProofPeriod(bytes32 claimId) public view returns(address) {
        return blockhashClaims[claimId].fraudProofPeriod;
    }
}
