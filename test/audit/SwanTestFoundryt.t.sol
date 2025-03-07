// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;


import {Test, console} from "forge-std/Test.sol";
import {SwanManager} from "../../src/swan/SwanManager.sol";
import {SwanAsset} from "../../src/swan/SwanAsset.sol";
import {Swan} from "../../src/swan/Swan.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {SwanAssetFactory} from "../../src/swan/SwanAsset.sol";
import {BuyerAgent} from "../../src/swan/BuyerAgent.sol";
import {BuyerAgentFactory} from "../../src/swan/BuyerAgent.sol";
import {SwanMarketParameters} from "../../src/swan/SwanManager.sol";
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

        // Deploy a buyer agent (buyerAgent will be used as the listing’s buyer)
        vm.prank(address(swan));
        BuyerAgent buyerAgent = buyerAgentFactory.deploy("TestBuyer", "desc", 10, 1000, buyerOwner);

        // Mint tokens for seller and buyerAgent so that transfers work:
        // (Assumes ERC20Mock has a mint function)
        token.mint(seller, 1000);
        token.mint(address(buyerAgent), 1000);

        // Seller must approve the Swan contract to spend tokens for royalty transfers.
        vm.prank(seller);
        token.approve(address(swan), 1000);

        // Seller lists an asset.
        // The list function checks that the buyer agent is in Sell phase.
        vm.prank(seller);
        swan.list("Asset", "AST", bytes("desc"), 100, address(buyerAgent));

        // Retrieve the asset address from the listing mapping.
        // Here we assume the asset was listed in round 0.
        address[] memory assets = swan.getListedAssets(address(buyerAgent), 0);
        require(assets.length > 0, "No assets listed");
        address assetAddress = assets[0];

        // The asset (an ERC721 token) must allow Swan to transfer it.
        SwanAsset asset = SwanAsset(assetAddress);
        vm.prank(seller);
        asset.setApprovalForAll(address(swan), true);

        // Buyer agent (the designated buyer) purchases the asset.
        // The purchase call will update the listing's status to Sold.
        vm.prank(address(buyerAgent));
        swan.purchase(assetAddress);

        // Now that the asset is sold, attempting to relist it should revert.
        // The relist function requires the listing status to be Listed.
        vm.prank(seller);
        vm.expectRevert();
        swan.relist(assetAddress, address(buyerAgent), 150);
}



}