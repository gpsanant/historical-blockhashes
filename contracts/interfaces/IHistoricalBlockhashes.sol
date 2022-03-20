//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

interface IHistoricalBlockhashes {
    function getClaimer(bytes32) external returns(address);
    function getFraudProofPeriod(bytes32) external returns(address);
    function resolveChallenge(bytes32, bool) external; 
}
