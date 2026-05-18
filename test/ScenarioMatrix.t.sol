// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/BaselineNFT.sol";
import "../src/SafeCrossChainNFT.sol";
import "../src/MockMarketplace.sol";

contract ScenarioMatrixTest {
    address internal constant BOB = address(0xB0B);
    address internal constant MALLORY = address(0xBAD);
    uint256 internal constant DST_CHAIN = 100;

    function testBaselineAllowsHazardousOperationsDuringPendingOut() public {
        BaselineNFT transferNft = _baselinePendingOut(1);
        transferNft.transferFrom(address(this), BOB, 1);
        require(transferNft.ownerOf(1) == BOB, "baseline transfer blocked");

        BaselineNFT safeTransferNft = _baselinePendingOut(2);
        safeTransferNft.safeTransferFrom(address(this), BOB, 2);
        require(safeTransferNft.ownerOf(2) == BOB, "baseline safe transfer blocked");

        BaselineNFT approveNft = _baselinePendingOut(3);
        approveNft.approve(MALLORY, 3);
        require(approveNft.getApproved(3) == MALLORY, "baseline approve blocked");

        BaselineNFT operatorNft = _baselinePendingOut(4);
        operatorNft.setApprovalForAll(MALLORY, true);
        require(operatorNft.isApprovedForAll(address(this), MALLORY), "baseline operator approval blocked");

        BaselineNFT listNft = _baselinePendingOut(5);
        listNft.list(5);
        require(listNft.listed(5), "baseline direct listing blocked");

        BaselineNFT marketNft = _baselinePendingOut(6);
        MockMarketplace market = new MockMarketplace();
        market.list(address(marketNft), 6);
        (, bool active) = market.listings(address(marketNft), 6);
        require(active, "baseline marketplace listing blocked");
    }

    function testProposalRejectsHazardousOperationsDuringPendingOut() public {
        _expectRevertTransfer(_proposalPendingOut(11), 11);
        _expectRevertSafeTransfer(_proposalPendingOut(12), 12);
        _expectRevertApprove(_proposalPendingOut(13), 13);
        _expectRevertOperatorApproval(_proposalPendingOut(14));
        _expectRevertList(_proposalPendingOut(15), 15);
        _expectRevertMarketplaceList(_proposalPendingOut(16), 16);
    }

    function testProposalRejectsHazardousOperationsDuringPendingIn() public {
        _expectRevertTransfer(_proposalPendingIn(21), 21);
        _expectRevertSafeTransfer(_proposalPendingIn(22), 22);
        _expectRevertApprove(_proposalPendingIn(23), 23);
        _expectRevertOperatorApproval(_proposalPendingIn(24));
        _expectRevertList(_proposalPendingIn(25), 25);
        _expectRevertMarketplaceList(_proposalPendingIn(26), 26);
    }

    function testProposalRestoresOperationsAfterFinalization() public {
        SafeCrossChainNFT transferNft = _proposalFinalized(31);
        transferNft.transferFrom(address(this), BOB, 31);
        require(transferNft.ownerOf(31) == BOB, "finalized transfer blocked");

        SafeCrossChainNFT safeTransferNft = _proposalFinalized(32);
        safeTransferNft.safeTransferFrom(address(this), BOB, 32);
        require(safeTransferNft.ownerOf(32) == BOB, "finalized safe transfer blocked");

        SafeCrossChainNFT approveNft = _proposalFinalized(33);
        approveNft.approve(MALLORY, 33);
        require(approveNft.getApproved(33) == MALLORY, "finalized approve blocked");

        SafeCrossChainNFT operatorNft = _proposalFinalized(34);
        operatorNft.setApprovalForAll(MALLORY, true);
        require(operatorNft.isApprovedForAll(address(this), MALLORY), "finalized operator approval blocked");

        SafeCrossChainNFT listNft = _proposalFinalized(35);
        listNft.list(35);
        require(listNft.listed(35), "finalized direct listing blocked");

        SafeCrossChainNFT marketNft = _proposalFinalized(36);
        MockMarketplace market = new MockMarketplace();
        market.list(address(marketNft), 36);
        (, bool active) = market.listings(address(marketNft), 36);
        require(active, "finalized marketplace listing blocked");
    }

    function testProposalRejectsReplayFinalization() public {
        SafeCrossChainNFT nft = _proposalFinalized(41);
        try nft.finalizeIn(41, address(this), DST_CHAIN, _messageId(41)) {
            revert("replay finalize accepted");
        } catch {}
    }

    function _baselinePendingOut(uint256 tokenId) internal returns (BaselineNFT nft) {
        nft = new BaselineNFT();
        nft.mint(address(this), tokenId);
        nft.bridgeOut(tokenId, DST_CHAIN);
    }

    function _proposalPendingOut(uint256 tokenId) internal returns (SafeCrossChainNFT nft) {
        nft = new SafeCrossChainNFT();
        nft.mint(address(this), tokenId);
        nft.bridgeOut(tokenId, DST_CHAIN);
    }

    function _proposalPendingIn(uint256 tokenId) internal returns (SafeCrossChainNFT nft) {
        nft = new SafeCrossChainNFT();
        nft.mint(address(this), tokenId);
        nft.markPendingIn(tokenId, DST_CHAIN, _messageId(tokenId));
    }

    function _proposalFinalized(uint256 tokenId) internal returns (SafeCrossChainNFT nft) {
        nft = _proposalPendingOut(tokenId);
        nft.finalizeIn(tokenId, address(this), DST_CHAIN, _messageId(tokenId));
    }

    function _messageId(uint256 tokenId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("message", tokenId));
    }

    function _expectRevertTransfer(SafeCrossChainNFT nft, uint256 tokenId) internal {
        try nft.transferFrom(address(this), BOB, tokenId) {
            revert("pending transfer accepted");
        } catch {}
    }

    function _expectRevertSafeTransfer(SafeCrossChainNFT nft, uint256 tokenId) internal {
        try nft.safeTransferFrom(address(this), BOB, tokenId) {
            revert("pending safe transfer accepted");
        } catch {}
    }

    function _expectRevertApprove(SafeCrossChainNFT nft, uint256 tokenId) internal {
        try nft.approve(MALLORY, tokenId) {
            revert("pending approve accepted");
        } catch {}
    }

    function _expectRevertOperatorApproval(SafeCrossChainNFT nft) internal {
        try nft.setApprovalForAll(MALLORY, true) {
            revert("pending operator approval accepted");
        } catch {}
    }

    function _expectRevertList(SafeCrossChainNFT nft, uint256 tokenId) internal {
        try nft.list(tokenId) {
            revert("pending direct listing accepted");
        } catch {}
    }

    function _expectRevertMarketplaceList(SafeCrossChainNFT nft, uint256 tokenId) internal {
        MockMarketplace market = new MockMarketplace();
        try market.list(address(nft), tokenId) {
            revert("pending marketplace listing accepted");
        } catch {}
    }
}
