// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/SafeCrossChainNFT.sol";
import "../src/MockMarketplace.sol";

contract PendingGuardHandler {
    SafeCrossChainNFT public immutable nft;
    MockMarketplace public immutable market;

    uint256 public constant TOKEN_COUNT = 8;
    uint256 public constant DST_CHAIN = 100;
    address public constant OPERATOR = address(0xC0DE);

    uint256 public pendingHazardousSuccesses;
    uint256 public finalizeNonce;

    constructor(SafeCrossChainNFT nft_, MockMarketplace market_) {
        nft = nft_;
        market = market_;
    }

    function bridgeOut(uint256 seed) external {
        uint256 tokenId = _token(seed);
        _bridgeOut(tokenId);
    }

    function bridgeOutExact(uint256 tokenId) external {
        _bridgeOut(tokenId);
    }

    function _bridgeOut(uint256 tokenId) internal {
        if (nft.bridgeState(tokenId) != SafeCrossChainNFT.TokenBridgeState.ACTIVE) return;
        try nft.bridgeOut(tokenId, DST_CHAIN) {} catch {}
    }

    function markPendingIn(uint256 seed) external {
        uint256 tokenId = _token(seed);
        if (nft.bridgeState(tokenId) != SafeCrossChainNFT.TokenBridgeState.ACTIVE) return;
        bytes32 messageId = keccak256(abi.encodePacked("pending-in", seed, tokenId));
        try nft.markPendingIn(tokenId, DST_CHAIN, messageId) {} catch {}
    }

    function finalize(uint256 seed) external {
        uint256 tokenId = _token(seed);
        if (nft.bridgeState(tokenId) == SafeCrossChainNFT.TokenBridgeState.ACTIVE) return;
        finalizeNonce += 1;
        bytes32 messageId = keccak256(abi.encodePacked("finalize", tokenId, finalizeNonce));
        try nft.finalizeIn(tokenId, address(this), DST_CHAIN, messageId) {} catch {}
    }

    function attemptHazardousOperation(uint256 seed, uint256 operation) external {
        uint256 tokenId = _token(seed);
        _attemptAndRecord(tokenId, operation);
    }

    function attemptExact(uint256 tokenId, uint256 operation) external returns (bool) {
        return _attemptAndRecord(tokenId, operation);
    }

    function _attemptAndRecord(uint256 tokenId, uint256 operation) internal returns (bool) {
        bool pendingBefore = nft.bridgeState(tokenId) != SafeCrossChainNFT.TokenBridgeState.ACTIVE;
        bool success = _attempt(tokenId, operation % 6);
        if (pendingBefore && success) {
            pendingHazardousSuccesses += 1;
        }
        return success;
    }

    function observedPendingTokenCount() external view returns (uint256 count) {
        for (uint256 i = 1; i <= TOKEN_COUNT; i += 1) {
            if (nft.bridgeState(i) != SafeCrossChainNFT.TokenBridgeState.ACTIVE) {
                count += 1;
            }
        }
    }

    function _attempt(uint256 tokenId, uint256 operation) internal returns (bool) {
        if (operation == 0) {
            try nft.transferFrom(address(this), address(this), tokenId) {
                return true;
            } catch {
                return false;
            }
        }
        if (operation == 1) {
            try nft.safeTransferFrom(address(this), address(this), tokenId) {
                return true;
            } catch {
                return false;
            }
        }
        if (operation == 2) {
            try nft.approve(OPERATOR, tokenId) {
                return true;
            } catch {
                return false;
            }
        }
        if (operation == 3) {
            try nft.setApprovalForAll(OPERATOR, true) {
                return true;
            } catch {
                return false;
            }
        }
        if (operation == 4) {
            try nft.list(tokenId) {
                return true;
            } catch {
                return false;
            }
        }
        try market.list(address(nft), tokenId) {
            return true;
        } catch {
            return false;
        }
    }

    function _token(uint256 seed) internal pure returns (uint256) {
        return (seed % TOKEN_COUNT) + 1;
    }
}

contract PendingGuardFuzzTest {
    uint256 internal constant DST_CHAIN = 100;

    function testFuzzStatefulPendingGuardInvariant(uint256 seed) public {
        SafeCrossChainNFT nft = new SafeCrossChainNFT();
        MockMarketplace market = new MockMarketplace();
        PendingGuardHandler handler = new PendingGuardHandler(nft, market);

        for (uint256 i = 1; i <= handler.TOKEN_COUNT(); i += 1) {
            nft.mint(address(handler), i);
        }

        for (uint256 step = 0; step < 32; step += 1) {
            uint256 draw = uint256(keccak256(abi.encodePacked(seed, step)));
            uint256 action = draw % 4;
            if (action == 0) {
                handler.bridgeOut(draw);
            } else if (action == 1) {
                handler.markPendingIn(draw);
            } else if (action == 2) {
                handler.finalize(draw);
            } else {
                handler.attemptHazardousOperation(draw, draw >> 8);
            }

            require(handler.pendingHazardousSuccesses() == 0, "pending hazardous operation succeeded");
            require(
                nft.pendingTokenCount(address(handler)) == handler.observedPendingTokenCount(),
                "pendingTokenCount drifted from token states"
            );
        }
    }

    function testFuzzProposalRejectsHazardousOperationsDuringPendingOut(uint256 seed, uint8 operation) public {
        (SafeCrossChainNFT nft, PendingGuardHandler owner, uint256 tokenId) = _pendingOut(seed);
        _expectHazardousOperationRejected(nft, owner, tokenId, operation);
        require(nft.bridgeState(tokenId) == SafeCrossChainNFT.TokenBridgeState.PENDING_OUT, "state changed");
    }

    function testFuzzProposalRejectsHazardousOperationsDuringPendingIn(uint256 seed, uint8 operation) public {
        (SafeCrossChainNFT nft, PendingGuardHandler owner, uint256 tokenId) = _pendingIn(seed);
        _expectHazardousOperationRejected(nft, owner, tokenId, operation);
        require(nft.bridgeState(tokenId) == SafeCrossChainNFT.TokenBridgeState.PENDING_IN, "state changed");
    }

    function testFuzzProposalRestoresAvailabilityAfterFinalization(uint256 seed, uint8 operation) public {
        (SafeCrossChainNFT nft, PendingGuardHandler owner, uint256 tokenId) = _pendingOut(seed);
        nft.finalizeIn(tokenId, address(owner), DST_CHAIN, _messageId("finalize", tokenId));
        require(nft.bridgeState(tokenId) == SafeCrossChainNFT.TokenBridgeState.ACTIVE, "not active");
        require(_attempt(nft, owner, tokenId, operation), "finalized operation rejected");
    }

    function testOperatorApprovalIsScopedPerOwnerAndRestored() public {
        SafeCrossChainNFT nft = new SafeCrossChainNFT();
        MockMarketplace market = new MockMarketplace();
        PendingGuardHandler alice = new PendingGuardHandler(nft, market);
        PendingGuardHandler bob = new PendingGuardHandler(nft, market);

        nft.mint(address(alice), 101);
        nft.mint(address(bob), 202);

        alice.bridgeOutExact(101);
        _expectOperatorApprovalRejected(alice, 101);

        require(_setOperatorApproval(bob, 202), "unrelated owner approval blocked");

        nft.finalizeIn(101, address(alice), DST_CHAIN, _messageId("restore", 101));
        require(_setOperatorApproval(alice, 101), "owner approval not restored");
    }

    function _pendingOut(uint256 seed)
        internal
        returns (SafeCrossChainNFT nft, PendingGuardHandler owner, uint256 tokenId)
    {
        MockMarketplace market = new MockMarketplace();
        nft = new SafeCrossChainNFT();
        owner = new PendingGuardHandler(nft, market);
        tokenId = _externalToken(seed);
        nft.mint(address(owner), tokenId);
        owner.bridgeOutExact(tokenId);
    }

    function _pendingIn(uint256 seed)
        internal
        returns (SafeCrossChainNFT nft, PendingGuardHandler owner, uint256 tokenId)
    {
        MockMarketplace market = new MockMarketplace();
        nft = new SafeCrossChainNFT();
        owner = new PendingGuardHandler(nft, market);
        tokenId = _externalToken(seed);
        nft.mint(address(owner), tokenId);
        nft.markPendingIn(tokenId, DST_CHAIN, _messageId("pending-in", tokenId));
    }

    function _expectHazardousOperationRejected(
        SafeCrossChainNFT nft,
        PendingGuardHandler owner,
        uint256 tokenId,
        uint8 operation
    ) internal {
        require(!_attempt(nft, owner, tokenId, operation), "pending operation accepted");
    }

    function _attempt(SafeCrossChainNFT, PendingGuardHandler owner, uint256 tokenId, uint8 operation)
        internal
        returns (bool)
    {
        try owner.attemptExact(tokenId, operation) returns (bool success) {
            return success;
        } catch {
            return false;
        }
    }

    function _setOperatorApproval(PendingGuardHandler owner, uint256 tokenId) internal returns (bool) {
        try owner.attemptExact(tokenId, 3) returns (bool success) {
            return success;
        } catch {
            return false;
        }
    }

    function _expectOperatorApprovalRejected(PendingGuardHandler owner, uint256 tokenId) internal {
        uint256 beforeCount = owner.pendingHazardousSuccesses();
        bool success = owner.attemptExact(tokenId, 3);
        require(!success, "operator approval accepted while pending");
        require(owner.pendingHazardousSuccesses() == beforeCount, "operator approval accepted while pending");
    }

    function _externalToken(uint256 seed) internal pure returns (uint256) {
        return 1000 + (seed % 1_000_000);
    }

    function _messageId(string memory domain, uint256 tokenId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(domain, tokenId));
    }
}
