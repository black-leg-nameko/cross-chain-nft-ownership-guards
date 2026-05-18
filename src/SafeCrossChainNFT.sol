// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./MinimalERC721.sol";

/// @notice State-aware cross-chain NFT proposal for the FIT2026 PoC.
/// The contract rejects ownership-dependent operations while a token is in
/// a pending bridge state.
contract SafeCrossChainNFT is MinimalERC721 {
    enum TokenBridgeState {
        ACTIVE,
        PENDING_OUT,
        PENDING_IN
    }

    error HazardousOperationWhilePending(uint256 tokenId, TokenBridgeState state);
    error OperatorApprovalWhileOwnerHasPendingTokens(address owner);
    error MessageAlreadyFinalized(bytes32 messageId);
    error TokenAlreadyPending(uint256 tokenId);

    mapping(uint256 => TokenBridgeState) public bridgeState;
    mapping(bytes32 => bool) public finalizedMessages;
    mapping(uint256 => bool) public listed;
    mapping(address => uint256) public pendingTokenCount;

    event BridgeOut(uint256 indexed tokenId, uint256 indexed dstChainId, address indexed owner);
    event PendingIn(uint256 indexed tokenId, uint256 indexed srcChainId, bytes32 indexed messageId);
    event FinalizeIn(uint256 indexed tokenId, uint256 indexed srcChainId, bytes32 indexed messageId, address owner);
    event Listed(uint256 indexed tokenId, address indexed owner);

    modifier whenActive(uint256 tokenId) {
        TokenBridgeState state = bridgeState[tokenId];
        if (state != TokenBridgeState.ACTIVE) {
            revert HazardousOperationWhilePending(tokenId, state);
        }
        _;
    }

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
        bridgeState[tokenId] = TokenBridgeState.ACTIVE;
    }

    function bridgeOut(uint256 tokenId, uint256 dstChainId) external whenActive(tokenId) {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotOwnerOrApproved();
        bridgeState[tokenId] = TokenBridgeState.PENDING_OUT;
        pendingTokenCount[ownerOf(tokenId)] += 1;
        emit BridgeOut(tokenId, dstChainId, ownerOf(tokenId));
    }

    function markPendingIn(uint256 tokenId, uint256 srcChainId, bytes32 messageId) external {
        if (finalizedMessages[messageId]) revert MessageAlreadyFinalized(messageId);
        if (bridgeState[tokenId] != TokenBridgeState.ACTIVE) revert TokenAlreadyPending(tokenId);
        bridgeState[tokenId] = TokenBridgeState.PENDING_IN;
        pendingTokenCount[ownerOf(tokenId)] += 1;
        emit PendingIn(tokenId, srcChainId, messageId);
    }

    function finalizeIn(uint256 tokenId, address newOwner, uint256 srcChainId, bytes32 messageId) external {
        if (finalizedMessages[messageId]) revert MessageAlreadyFinalized(messageId);
        finalizedMessages[messageId] = true;

        address oldOwner = _owners[tokenId];
        if (oldOwner != address(0) && bridgeState[tokenId] != TokenBridgeState.ACTIVE) {
            pendingTokenCount[oldOwner] -= 1;
        }

        _forceOwner(newOwner, tokenId);
        bridgeState[tokenId] = TokenBridgeState.ACTIVE;
        emit FinalizeIn(tokenId, srcChainId, messageId, newOwner);
    }

    function canList(uint256 tokenId) external view returns (bool) {
        return bridgeState[tokenId] == TokenBridgeState.ACTIVE;
    }

    function list(uint256 tokenId) external whenActive(tokenId) {
        if (!_isApprovedOrOwner(msg.sender, tokenId)) revert NotOwnerOrApproved();
        listed[tokenId] = true;
        emit Listed(tokenId, ownerOf(tokenId));
    }

    function approve(address to, uint256 tokenId) public override whenActive(tokenId) {
        super.approve(to, tokenId);
    }

    function setApprovalForAll(address operator, bool approved) public override {
        if (pendingTokenCount[msg.sender] != 0) {
            revert OperatorApprovalWhileOwnerHasPendingTokens(msg.sender);
        }
        super.setApprovalForAll(operator, approved);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override whenActive(tokenId) {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public override whenActive(tokenId) {
        super.safeTransferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) public override whenActive(tokenId) {
        super.safeTransferFrom(from, to, tokenId, data);
    }

}
