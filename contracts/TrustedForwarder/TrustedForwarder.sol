// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

contract TrustedForwarder is Ownable, EIP712 {
    using ECDSA for bytes32;

    struct ForwardRequest {
        address from;
        address to;
        uint256 value;
        uint256 gas;
        uint256 nonce;
        bytes data;
    }

    mapping(address => uint256) private _nonces;

    event MetaTransactionExecuted(address from, address to, bytes data);

    constructor() Ownable(msg.sender) EIP712("TrustedForwarder", "1") {}

    function getNonce(address from) public view returns (uint256) {
        return _nonces[from];
    }

    /// @notice Verifies a signature for a ForwardRequest
    /// @param req The ForwardRequest struct
    /// @param signature The signature of the ForwardRequest
    /// @return Whether the signature is valid
    function verify(
        ForwardRequest calldata req,
        bytes calldata signature
    ) public view returns (bool) {
        address signer = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256(
                        "ForwardRequest(address from,address to,uint256 value,uint256 gas,uint256 nonce,bytes data)"
                    ),
                    req.from,
                    req.to,
                    req.value,
                    req.gas,
                    req.nonce,
                    keccak256(req.data)
                )
            )
        ).recover(signature);

        return _nonces[req.from] == req.nonce && signer == req.from;
    }

    /// @notice Executes a meta-transaction
    /// @param req The ForwardRequest struct
    /// @param signature The signature of the ForwardRequest
    /// @return success Whether the transaction was successful
    /// @return returndata The return data from the transaction
    function execute(
        ForwardRequest calldata req,
        bytes calldata signature
    ) public payable returns (bool, bytes memory) {
        require(
            verify(req, signature),
            "TrustedForwarder: signature does not match request"
        );
        _nonces[req.from] = req.nonce + 1;

        (bool success, bytes memory returndata) = req.to.call{
            gas: req.gas,
            value: req.value
        }(abi.encodePacked(req.data, req.from));

        if (!success) {
            assembly {
                revert(add(returndata, 32), mload(returndata))
            }
        }

        emit MetaTransactionExecuted(req.from, req.to, req.data);
        return (success, returndata);
    }

    receive() external payable {}

    fallback() external payable {}
}
