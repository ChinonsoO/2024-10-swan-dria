// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {SwanManager, SwanMarketParameters} from "../../src/swan/SwanManager.sol";
import {SwanAsset, SwanAssetFactory} from "../../src/swan/SwanAsset.sol";
import {Swan} from "../../src/swan/Swan.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {BuyerAgent, BuyerAgentFactory} from "../../src/swan/BuyerAgent.sol";
import {LLMOracleTaskParameters} from "../../src/llm/LLMOracleTask.sol";
import {LLMOracleCoordinator} from "../../src/llm/LLMOracleCoordinator.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SwanTestFoundry is Test {
    Swan public swan;
    SwanAsset public swanAsset;
    SwanAssetFactory public swanAssetFactory;
    BuyerAgentFactory public buyerAgentFactory;
    ERC20Mock public token;

    address owner = makeAddr("owner");
    address operator = makeAddr("operator");
    address buyerOwner = makeAddr("buyer");
    address seller = makeAddr("seller");

    LLMOracleCoordinator public coordinator;

    SwanMarketParameters MARKET_PARAMETERS;
    LLMOracleTaskParameters ORACLE_PARAMETERS;

    function setUp() public {
        MARKET_PARAMETERS = SwanMarketParameters({
            withdrawInterval: 100,
            sellInterval: 100,
            buyInterval: 100,
            platformFee: 5,
            maxAssetCount: 100,
            timestamp: block.timestamp
        });

        ORACLE_PARAMETERS = LLMOracleTaskParameters({ difficulty: 1, numGenerations: 1, numValidations: 1});
        coordinator = new LLMOracleCoordinator();

        swanAssetFactory = new SwanAssetFactory();
        buyerAgentFactory = new BuyerAgentFactory();

        token = new ERC20Mock();

        Swan swanImplementation = new Swan();
        bytes memory initData = abi.encodeWithSelector(
            Swan.initialize.selector,
            MARKET_PARAMETERS,
            ORACLE_PARAMETERS,
            address(coordinator),
            address(token),
            address(buyerAgentFactory),
            address(swanAssetFactory)
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(swanImplementation), initData);
        swan = Swan(address(proxy));
    }

    function testCannotRelistSoldListing() public {
        // Deploy a buyer agent for the listing.
        vm.prank(address(swan));
        BuyerAgent buyerAgent = buyerAgentFactory.deploy("TestBuyer", "desc", 10, 1000, buyerOwner);

        // Mint tokens for seller and buyerAgent so that transfers work.
        token.mint(seller, 1000);
        token.mint(address(buyerAgent), 1000);

        // Seller must approve the Swan contract to spend tokens for royalty transfers.
        vm.prank(seller);
        token.approve(address(swan), 1000);

        // Seller lists an asset.
        vm.prank(seller);
        swan.list("Asset", "AST", bytes("desc"), 100, address(buyerAgent));

        // Retrieve the asset address from the listing mapping (round 0).
        address[] memory assets = swan.getListedAssets(address(buyerAgent), 0);
        require(assets.length > 0, "No assets listed");
        address assetAddress = assets[0];

        // The asset (an ERC721 token) must allow Swan to transfer it.
        SwanAsset asset = SwanAsset(assetAddress);
        vm.prank(seller);
        asset.setApprovalForAll(address(swan), true);

        // Buyer agent purchases the asset, updating its status to Sold.
        vm.prank(address(buyerAgent));
        swan.purchase(assetAddress);

        // Now that the asset is sold, attempting to relist it should revert.
        vm.prank(seller);
        vm.expectRevert();
        swan.relist(assetAddress, address(buyerAgent), 150);
    }

    function testArbitraryBuyerAddressCanBePassedToList() public {
        // Deploy a FakeBuyer that satisfies the minimal buyer interface.
        FakeBuyer fakeBuyer = new FakeBuyer();

        // Mint tokens for seller and approve the Swan contract.
        token.mint(seller, 1000);
        vm.prank(seller);
        token.approve(address(swan), 1000);

        // Seller lists an asset using the FakeBuyer address.
        vm.prank(seller);
        swan.list("FakeAsset", "FA", bytes("fake asset description"), 100, address(fakeBuyer));

        // Retrieve the list of assets associated with FakeBuyer for round 0.
        address[] memory assets = swan.getListedAssets(address(fakeBuyer), 0);

        assertGt(assets.length, 0, "No assets were listed for FakeBuyer");
    }
}

// A minimal FakeBuyer contract to test that any address implementing the minimal interface can be used.
contract FakeBuyer {
    // Returns a dummy round (0), the required Sell phase, and a dummy time remaining.
    function getRoundPhase() external pure returns (uint256, BuyerAgent.Phase, uint256) {
        return (0, BuyerAgent.Phase.Sell, 100);
    }

    // Returns a fixed royalty fee.
    function royaltyFee() external pure returns (uint96) {
        return 10;
    }
}
