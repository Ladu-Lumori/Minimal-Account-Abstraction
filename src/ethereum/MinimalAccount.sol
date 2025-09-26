// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccount} from "lib/account-abstraction/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "lib/account-abstraction/contracts/core/Helpers.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";

contract MinimalAccount is IAccount, Ownable {
    // ERRORS
    error MinimalAccount__NotFromEntryPoint();
    error MinimalAccount__NotFromEntryPointOrOwner();
    error MinimalAccount__CallFailed(bytes);

    // STATE VARIABLES 
    IEntryPoint private immutable I_ENTRYPOINT;

    // MODIFIERS
    modifier requireFromEntryPoint () {
        if(msg.sender != address(I_ENTRYPOINT)){
            revert MinimalAccount__NotFromEntryPoint();
        }
        _;
    }

    modifier requireFromEntryPointOrOwner() {
        if(msg.sender != address(I_ENTRYPOINT)){
            revert MinimalAccount__NotFromEntryPointOrOwner();
        }
        _;
    }

    // FUNCTIONS
    constructor(address entryPoint) Ownable(msg.sender) {
        I_ENTRYPOINT = IEntryPoint(entryPoint);
    }

    receive() external payable {}

    // EXTERNAL FUNCTIONS
    function execute(address dest, uint256 value, bytes calldata functionData) external requireFromEntryPointOrOwner {
        (bool success, bytes memory result) = dest.call{value: value}(functionData);
        if(!success){
            revert MinimalAccount__CallFailed(result);
        }
    }

    // an account is valid if its the MinimalAccount owner
    function validateUserOp(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external requireFromEntryPoint returns (uint256 validationData) {
        validationData = _validateSignature(userOp, userOpHash);
        // _validateNonce()
        _payPrefund(missingAccountFunds);
    }

    // INTERNAL FUNCTIONS

    // EIP-191 version of the signed hash
    // Optionally signature aggregator for more customization
    function _validateSignature (PackedUserOperation calldata userOp, bytes32 userOpHash) internal view returns (uint256 validationData) {
        bytes32 ethSignedMessageHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        address signer = ECDSA.recover(ethSignedMessageHash, userOp.signature);
        if(signer != owner()){
            return SIG_VALIDATION_FAILED;
        }
        return SIG_VALIDATION_SUCCESS;
    }

    function _payPrefund(uint256 missingAccountFunds) internal {
        // entry point contract should validate but alas for the love of linter ;)
        if(missingAccountFunds != 0){
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds, gas: type(uint256).max}("");
            (success);
        }
    }

    // Getters
    function getEntryPoint() external view returns (address){
        return address(I_ENTRYPOINT);
    }
}