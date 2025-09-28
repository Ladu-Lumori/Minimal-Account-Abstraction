// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAccount} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";
import {
    Transaction,
    MemoryTransactionHelper
} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {SystemContractsCaller} from
    "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/SystemContractsCaller.sol";
import {NONCE_HOLDER_SYSTEM_CONTRACT, BOOTLOADER_FORMAL_ADDRESS} from "lib/foundry-era-contracts/src/system-contracts/contracts/Constants.sol";
import {INonceHolder} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/INonceHolder.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessageUtils} from "@openzeppelin/contracts/utils/cryptography/MessageUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * Life cycle of a type-113 (0x71) transaction.
 * the msg.sender is the bootloader system contract.
 *
 * Phase 1 validation
 * 1. The user sends the transaction to the "zkSync API client" (sort of a "light node").
 * 2. The zkSync API client checks to see the nonce is unique by querying the NonceHolder system contract.
 * 3. The zkSync API calls validateTransaction, which MUST update the nonce.
 * 4. The zkSync API checks the nonce is updated.
 * 5. The zkSync API client calls payForTransaction, or prepareForMaster & validateAndPayForPaymasterTransaction.
 * 6. The zkSync API verifies that the bootloader gets paid.
 *
 * Phase 2 Execution
 * 7. The zkSync API client passes the validated transaction to main node / sequencer
 * 8. The main node calls the executeTransaction
 * 9. If a paymaster was used, the postTransaction is called
 *
 */
contract ZkMinimalAccount is IAccount, Ownable {
    using MemoryTransactionHelper for Transaction;

    // Errors
    error ZkMinimalAccount__NotEnoughBalance();
    error ZkMinimalAccount__NotFromBootLoader();

    // Modifiers
    modifier requireFromBootLoader {
        if(msg.sender != BOOTLOADER_FORMAL_ADDRESS){
            revert ZkMinimalAccount__NotFromBootLoader();
        }
        _;
    }

    // Functions
    constructor Ownable(msg.sender) {}

    // External Functions
    /**
     * @notice Must validate the transaction (check the owner validated the transaction)
     * @notice Must increase the nonce
     * @notice check if we have enough money in our account
     */
    function validateTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction memory _transaction)
        external
        payable
        requireFromBootLoader
        returns (bytes4 magic)
    {
        // call nonce holder
        // increase nonce by one
        SystemContractsCaller.systemCallWithPropagatedRevert(
            uint32(gasleft()),
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, (_transaction.nonce))
        );

        // check for fee to pay
        uint256 totalRequiredBalance = _transaction.totalRequiredBalance();
        if (totalRequiredBalance > address(this).balance) {
            revert ZkMinimalAccount__NotEnoughBalance();
        }

        // check for signature
        bytes32 txHash = _transaction.encodeHash(); // encode our transaction hash
        bytes32 convertedHash = MessageUtils.toEthSignedMessageHash(txHash); // convert hash to proper format
        address signer = ECDSA.recover(convertedHash, _transaction.signature); // check who signed the hash
        bool isValidSIgner = signer == address(owner())
        if (isValidSIgner) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }

        // return the magic number
        return magic;
    }

    function executeTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction memory _transaction)
        external
        payable
    {}

    function executeTransactionFromOutside(Transaction memory _transaction) external payable {}

    function payForTransaction(bytes32 _txHash, bytes32 _suggestedSignedHash, Transaction memory _transaction)
        external
        payable
    {}

    function prepareForPaymaster(bytes32 _txHash, bytes32 _possibleSignedHash, Transaction memory _transaction)
        external
        payable
    {}

    // Internal Functions
}
