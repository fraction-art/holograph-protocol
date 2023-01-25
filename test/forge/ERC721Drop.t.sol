// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {IERC721AUpgradeable} from "erc721a-upgradeable/IERC721AUpgradeable.sol";

import {DropInitializer} from "../../contracts/struct/DropInitializer.sol";

import {ERC721Drop} from "../../contracts/drops/ERC721Drop.sol";
import {HolographFeeManager} from "../../contracts/drops/HolographFeeManager.sol";
import {DummyMetadataRenderer} from "./utils/DummyMetadataRenderer.sol";
import {MockUser} from "./utils/MockUser.sol";
import {IOperatorFilterRegistry} from "../../contracts/drops/interfaces/IOperatorFilterRegistry.sol";
import {IMetadataRenderer} from "../../contracts/drops/interfaces/IMetadataRenderer.sol";
import {IERC721Drop} from "../../contracts/drops/interfaces/IERC721Drop.sol";
import {FactoryUpgradeGate} from "../../contracts/drops/FactoryUpgradeGate.sol";
import {ERC721DropProxy} from "../../contracts/drops/ERC721DropProxy.sol";
import {OperatorFilterRegistry} from "./filter/OperatorFilterRegistry.sol";
import {OperatorFilterRegistryErrorsAndEvents} from "./filter/OperatorFilterRegistryErrorsAndEvents.sol";
import {OwnedSubscriptionManager} from "../../contracts/drops/filter/OwnedSubscriptionManager.sol";

// contract TestEventEmitter {
//     function emitFundsWithdrawn(
//         address withdrawnBy,
//         address withdrawnTo,
//         uint256 amount,
//         address feeRecipient,
//         uint256 feeAmount
//     ) external {
//         emit FundsWithdrawn(
//             withdrawnBy,
//             withdrawnTo,
//             amount,
//             feeRecipient,
//             feeAmount
//         );
//     }
// }

contract ERC721DropTest is Test {
  /// @notice Event emitted when the funds are withdrawn from the minting contract
  /// @param withdrawnBy address that issued the withdraw
  /// @param withdrawnTo address that the funds were withdrawn to
  /// @param amount amount that was withdrawn
  /// @param feeRecipient user getting withdraw fee (if any)
  /// @param feeAmount amount of the fee getting sent (if any)
  event FundsWithdrawn(
    address indexed withdrawnBy,
    address indexed withdrawnTo,
    uint256 amount,
    address feeRecipient,
    uint256 feeAmount
  );

  ERC721Drop holographNFTBase;
  MockUser mockUser;
  DummyMetadataRenderer public dummyRenderer = new DummyMetadataRenderer();
  HolographFeeManager public feeManager;
  FactoryUpgradeGate public factoryUpgradeGate;
  address public constant DEFAULT_OWNER_ADDRESS = address(0x23499);
  address payable public constant DEFAULT_FUNDS_RECIPIENT_ADDRESS = payable(address(0x21303));
  address payable public constant DEFAULT_HOLOGRAPH_DAO_ADDRESS = payable(address(0x999));
  address public constant UPGRADE_GATE_ADMIN_ADDRESS = address(0x942924224);
  address public constant mediaContract = address(0x123456);
  address public impl;
  address public ownedSubscriptionManager;

  struct Configuration {
    IMetadataRenderer metadataRenderer;
    uint64 editionSize;
    uint16 royaltyBPS;
    address payable fundsRecipient;
  }

  modifier setupHolographNFTBase(uint64 editionSize) {
    // // The stuff below should be moved to setup
    // vm.prank(DEFAULT_HOLOGRAPH_DAO_ADDRESS);
    // feeManager = new HolographFeeManager(0, DEFAULT_HOLOGRAPH_DAO_ADDRESS);
    // factoryUpgradeGate = new FactoryUpgradeGate(UPGRADE_GATE_ADMIN_ADDRESS);
    // vm.etch(address(0x000000000000AAeB6D7670E522A718067333cd4E), address(new OperatorFilterRegistry()).code);
    // ownedSubscriptionManager = address(new OwnedSubscriptionManager(address(0x123456)));
    // vm.prank(DEFAULT_HOLOGRAPH_DAO_ADDRESS);

    // impl = address(new ERC721Drop());
    // // address payable newDrop = payable(address(new ERC721DropProxy()));
    // // holographNFTBase = ERC721Drop(newDrop);
    // vm.prank(DEFAULT_HOLOGRAPH_DAO_ADDRESS);
    // feeManager.setFeeOverride(address(holographNFTBase), 500);
    // ////////////////////////

    // DropInitializer memory initializer = DropInitializer({
    //   holographFeeManager: address(feeManager),
    //   holographERC721TransferHelper: address(0x1234),
    //   factoryUpgradeGate: address(factoryUpgradeGate),
    //   marketFilterDAOAddress: address(0x0),
    //   contractName: "Test NFT",
    //   contractSymbol: "TNFT",
    //   initialOwner: DEFAULT_OWNER_ADDRESS,
    //   fundsRecipient: payable(DEFAULT_FUNDS_RECIPIENT_ADDRESS),
    //   editionSize: editionSize,
    //   royaltyBPS: 800,
    //   setupCalls: new bytes[](0),
    //   metadataRenderer: address(dummyRenderer),
    //   metadataRendererInit: ""
    // });

    // ERC721DropProxy erc721DropProxy = new ERC721DropProxy();
    // erc721DropProxy.init(abi.encode(new ERC721Drop(), abi.encode(initializer)));

    // address payable newDrop = payable(address(erc721DropProxy));
    // holographNFTBase = ERC721Drop(newDrop);

    _;
  }

  function setUp() public {
    // The stuff below should be moved to setup
    vm.prank(DEFAULT_HOLOGRAPH_DAO_ADDRESS);
    feeManager = new HolographFeeManager(0, DEFAULT_HOLOGRAPH_DAO_ADDRESS);
    factoryUpgradeGate = new FactoryUpgradeGate(UPGRADE_GATE_ADMIN_ADDRESS);
    vm.etch(address(0x000000000000AAeB6D7670E522A718067333cd4E), address(new OperatorFilterRegistry()).code);
    ownedSubscriptionManager = address(new OwnedSubscriptionManager(address(0x123456)));
    vm.prank(DEFAULT_HOLOGRAPH_DAO_ADDRESS);

    impl = address(new ERC721Drop());
    // address payable newDrop = payable(address(new ERC721DropProxy()));
    // holographNFTBase = ERC721Drop(newDrop);
    vm.prank(DEFAULT_HOLOGRAPH_DAO_ADDRESS);
    feeManager.setFeeOverride(address(holographNFTBase), 500);
    ////////////////////////

    DropInitializer memory initializer = DropInitializer({
      holographFeeManager: address(feeManager),
      holographERC721TransferHelper: address(0x1234),
      factoryUpgradeGate: address(factoryUpgradeGate),
      marketFilterDAOAddress: address(0x0),
      contractName: "Test NFT",
      contractSymbol: "TNFT",
      initialOwner: DEFAULT_OWNER_ADDRESS,
      fundsRecipient: payable(DEFAULT_FUNDS_RECIPIENT_ADDRESS),
      editionSize: 10,
      royaltyBPS: 800,
      setupCalls: new bytes[](0),
      metadataRenderer: address(dummyRenderer),
      metadataRendererInit: ""
    });

    ERC721DropProxy erc721DropProxy = new ERC721DropProxy();
    erc721DropProxy.init(abi.encode(new ERC721Drop(), abi.encode(initializer)));

    address payable newDrop = payable(address(erc721DropProxy));
    holographNFTBase = ERC721Drop(newDrop);
  }

  // modifier factoryWithSubscriptionAddress(address subscriptionAddress) {
  //   vm.prank(DEFAULT_HOLOGRAPH_DAO_ADDRESS);
  //   impl = address(new ERC721Drop());
  //   ERC721Drop(payable(impl)).init(
  //     abi.encode(
  //       address(feeManager),
  //       address(0x1234),
  //       factoryUpgradeGate,
  //       subscriptionAddress,
  //       "Contract Name",
  //       "Contract Symbol",
  //       address(0x0),
  //       address(0x0),
  //       uint64(0),
  //       uint16(0),
  //       new bytes[](0),
  //       address(0x0),
  //       new bytes(0)
  //     )
  //   );
  //   address payable newDrop = payable(address(new ERC721DropProxy()));
  //   holographNFTBase = ERC721Drop(newDrop);

  //   _;
  // }

  function test_Init() public setupHolographNFTBase(10) {
    console.log("test_Init");
    require(holographNFTBase.owner() == DEFAULT_OWNER_ADDRESS, "Default owner set wrong");
    (
      IMetadataRenderer renderer,
      uint64 editionSize,
      uint16 royaltyBPS,
      address payable fundsRecipient
    ) = holographNFTBase.config();
    require(address(renderer) == address(dummyRenderer));
    require(editionSize == 10, "EditionSize is wrong");
    require(royaltyBPS == 800, "RoyaltyBPS is wrong");
    require(fundsRecipient == payable(DEFAULT_FUNDS_RECIPIENT_ADDRESS), "FundsRecipient is wrong");
    string memory name = holographNFTBase.name();
    string memory symbol = holographNFTBase.symbol();
    require(keccak256(bytes(name)) == keccak256(bytes("Test NFT")));
    require(keccak256(bytes(symbol)) == keccak256(bytes("TNFT")));
    vm.expectRevert("HOLOGRAPH: already initialized");
    holographNFTBase.init(
      abi.encode(
        address(feeManager),
        address(0x1234),
        factoryUpgradeGate,
        address(0x0),
        "Test NFT",
        "TNFT",
        DEFAULT_OWNER_ADDRESS,
        payable(DEFAULT_FUNDS_RECIPIENT_ADDRESS),
        uint64(10),
        uint16(800),
        new bytes[](0),
        dummyRenderer,
        new bytes(0)
      )
    );
  }

  // function test_SubscriptionEnabled()
  //   public
  //   factoryWithSubscriptionAddress(ownedSubscriptionManager)
  //   setupHolographNFTBase(10)
  // {
  //   IOperatorFilterRegistry operatorFilterRegistry = IOperatorFilterRegistry(
  //     0x000000000000AAeB6D7670E522A718067333cd4E
  //   );
  //   vm.startPrank(address(0x123456));
  //   operatorFilterRegistry.updateOperator(ownedSubscriptionManager, address(0xcafeea3), true);
  //   vm.stopPrank();
  //   vm.startPrank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.manageMarketFilterDAOSubscription(true);
  //   holographNFTBase.adminMint(DEFAULT_OWNER_ADDRESS, 10);
  //   holographNFTBase.setApprovalForAll(address(0xcafeea3), true);
  //   vm.stopPrank();
  //   vm.prank(address(0xcafeea3));
  //   vm.expectRevert(
  //     abi.encodeWithSelector(OperatorFilterRegistryErrorsAndEvents.AddressFiltered.selector, address(0xcafeea3))
  //   );
  //   holographNFTBase.transferFrom(DEFAULT_OWNER_ADDRESS, address(0x123456), 1);
  //   vm.prank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.manageMarketFilterDAOSubscription(false);
  //   vm.prank(address(0xcafeea3));
  //   holographNFTBase.transferFrom(DEFAULT_OWNER_ADDRESS, address(0x123456), 1);
  // }

  // function test_OnlyAdminEnableSubscription()
  //   public
  //   factoryWithSubscriptionAddress(ownedSubscriptionManager)
  //   setupHolographNFTBase(10)
  // {
  //   vm.startPrank(address(0xcafecafe));
  //   vm.expectRevert(IERC721Drop.Access_OnlyAdmin.selector);
  //   holographNFTBase.manageMarketFilterDAOSubscription(true);
  //   vm.stopPrank();
  // }

  // function test_ProxySubscriptionAccessOnlyAdmin()
  //   public
  //   factoryWithSubscriptionAddress(ownedSubscriptionManager)
  //   setupHolographNFTBase(10)
  // {
  //   bytes memory baseCall = abi.encodeWithSelector(
  //     IOperatorFilterRegistry.register.selector,
  //     address(holographNFTBase)
  //   );
  //   vm.startPrank(address(0xcafecafe));
  //   vm.expectRevert(IERC721Drop.Access_OnlyAdmin.selector);
  //   holographNFTBase.updateMarketFilterSettings(baseCall);
  //   vm.stopPrank();
  // }

  // function test_ProxySubscriptionAccess()
  //   public
  //   factoryWithSubscriptionAddress(ownedSubscriptionManager)
  //   setupHolographNFTBase(10)
  // {
  //   vm.startPrank(address(DEFAULT_OWNER_ADDRESS));
  //   bytes memory baseCall = abi.encodeWithSelector(
  //     IOperatorFilterRegistry.register.selector,
  //     address(holographNFTBase)
  //   );
  //   holographNFTBase.updateMarketFilterSettings(baseCall);
  //   vm.stopPrank();
  // }

  // function test_Purchase(uint64 amount) public setupHolographNFTBase(10) {
  //   vm.prank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.setSaleConfiguration({
  //     publicSaleStart: 0,
  //     publicSaleEnd: type(uint64).max,
  //     presaleStart: 0,
  //     presaleEnd: 0,
  //     publicSalePrice: amount,
  //     maxSalePurchasePerAddress: 2,
  //     presaleMerkleRoot: bytes32(0)
  //   });

  //   vm.deal(address(0x456), uint256(amount) * 2);
  //   vm.prank(address(0x456));
  //   holographNFTBase.purchase{value: amount}(1);

  //   assertEq(holographNFTBase.saleDetails().maxSupply, 10);
  //   assertEq(holographNFTBase.saleDetails().totalMinted, 1);
  //   require(holographNFTBase.ownerOf(1) == address(0x456), "owner is wrong for new minted token");
  //   assertEq(address(holographNFTBase).balance, amount);
  // }

  // function test_UpgradeApproved() public setupHolographNFTBase(10) {
  //   address newImpl = address(new ERC721Drop());
  //   ERC721Drop(payable(newImpl)).init(
  //     abi.encode(
  //       address(0xadadad),
  //       address(0x3333),
  //       factoryUpgradeGate,
  //       address(0x0),
  //       "Contract Name",
  //       "Contract Symbol",
  //       address(0x0),
  //       address(0x0),
  //       uint64(0),
  //       uint16(0),
  //       new bytes[](0),
  //       address(0x0),
  //       new bytes(0)
  //     )
  //   );

  //   address[] memory lastImpls = new address[](1);
  //   lastImpls[0] = impl;
  //   vm.prank(UPGRADE_GATE_ADMIN_ADDRESS);
  //   factoryUpgradeGate.registerNewUpgradePath({_newImpl: newImpl, _supportedPrevImpls: lastImpls});
  //   vm.prank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.upgradeTo(newImpl);
  //   assertEq(address(holographNFTBase.holographFeeManager()), address(0xadadad));
  // }

  // function test_PurchaseTime() public setupHolographNFTBase(10) {
  //   vm.prank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.setSaleConfiguration({
  //     publicSaleStart: 0,
  //     publicSaleEnd: 0,
  //     presaleStart: 0,
  //     presaleEnd: 0,
  //     publicSalePrice: 0.1 ether,
  //     maxSalePurchasePerAddress: 2,
  //     presaleMerkleRoot: bytes32(0)
  //   });

  //   assertTrue(!holographNFTBase.saleDetails().publicSaleActive);

  //   vm.deal(address(0x456), 1 ether);
  //   vm.prank(address(0x456));
  //   vm.expectRevert(IERC721Drop.Sale_Inactive.selector);
  //   holographNFTBase.purchase{value: 0.1 ether}(1);

  //   assertEq(holographNFTBase.saleDetails().maxSupply, 10);
  //   assertEq(holographNFTBase.saleDetails().totalMinted, 0);

  //   vm.prank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.setSaleConfiguration({
  //     publicSaleStart: 9 * 3600,
  //     publicSaleEnd: 11 * 3600,
  //     presaleStart: 0,
  //     presaleEnd: 0,
  //     maxSalePurchasePerAddress: 20,
  //     publicSalePrice: 0.1 ether,
  //     presaleMerkleRoot: bytes32(0)
  //   });

  //   assertTrue(!holographNFTBase.saleDetails().publicSaleActive);
  //   // jan 1st 1980
  //   vm.warp(10 * 3600);
  //   assertTrue(holographNFTBase.saleDetails().publicSaleActive);
  //   assertTrue(!holographNFTBase.saleDetails().presaleActive);

  //   vm.prank(address(0x456));
  //   holographNFTBase.purchase{value: 0.1 ether}(1);

  //   assertEq(holographNFTBase.saleDetails().totalMinted, 1);
  //   assertEq(holographNFTBase.ownerOf(1), address(0x456));
  // }

  // function test_Mint() public setupHolographNFTBase(10) {
  //   vm.prank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.adminMint(DEFAULT_OWNER_ADDRESS, 1);
  //   assertEq(holographNFTBase.saleDetails().maxSupply, 10);
  //   assertEq(holographNFTBase.saleDetails().totalMinted, 1);
  //   require(holographNFTBase.ownerOf(1) == DEFAULT_OWNER_ADDRESS, "Owner is wrong for new minted token");
  // }

  // function test_MintMulticall() public setupHolographNFTBase(10) {
  //   vm.startPrank(DEFAULT_OWNER_ADDRESS);
  //   bytes[] memory calls = new bytes[](3);
  //   calls[0] = abi.encodeWithSelector(IERC721Drop.adminMint.selector, DEFAULT_OWNER_ADDRESS, 5);
  //   calls[1] = abi.encodeWithSelector(IERC721Drop.adminMint.selector, address(0x123), 3);
  //   calls[2] = abi.encodeWithSelector(IERC721Drop.saleDetails.selector);
  //   bytes[] memory results = holographNFTBase.multicall(calls);

  //   (bool saleActive, bool presaleActive, uint256 publicSalePrice, , , , , , , , ) = abi.decode(
  //     results[2],
  //     (bool, bool, uint256, uint64, uint64, uint64, uint64, bytes32, uint256, uint256, uint256)
  //   );
  //   assertTrue(!saleActive);
  //   assertTrue(!presaleActive);
  //   assertEq(publicSalePrice, 0);
  //   uint256 firstMintedId = abi.decode(results[0], (uint256));
  //   uint256 secondMintedId = abi.decode(results[1], (uint256));
  //   assertEq(firstMintedId, 5);
  //   assertEq(secondMintedId, 8);
  // }

  // function test_UpdatePriceMulticall() public setupHolographNFTBase(10) {
  //   vm.startPrank(DEFAULT_OWNER_ADDRESS);
  //   bytes[] memory calls = new bytes[](3);
  //   calls[0] = abi.encodeWithSelector(
  //     IERC721Drop.setSaleConfiguration.selector,
  //     0.1 ether,
  //     2,
  //     0,
  //     type(uint64).max,
  //     0,
  //     0,
  //     bytes32(0)
  //   );
  //   calls[1] = abi.encodeWithSelector(IERC721Drop.adminMint.selector, address(0x123), 3);
  //   calls[2] = abi.encodeWithSelector(IERC721Drop.adminMint.selector, address(0x123), 3);
  //   bytes[] memory results = holographNFTBase.multicall(calls);

  //   IERC721Drop.SaleDetails memory saleDetails = holographNFTBase.saleDetails();

  //   assertTrue(saleDetails.publicSaleActive);
  //   assertTrue(!saleDetails.presaleActive);
  //   assertEq(saleDetails.publicSalePrice, 0.1 ether);
  //   uint256 firstMintedId = abi.decode(results[1], (uint256));
  //   uint256 secondMintedId = abi.decode(results[2], (uint256));
  //   assertEq(firstMintedId, 3);
  //   assertEq(secondMintedId, 6);
  //   vm.stopPrank();
  //   vm.startPrank(address(0x111));
  //   vm.deal(address(0x111), 0.3 ether);
  //   holographNFTBase.purchase{value: 0.2 ether}(2);
  //   assertEq(holographNFTBase.balanceOf(address(0x111)), 2);
  //   vm.stopPrank();
  // }

  // function test_MintWrongValue() public setupHolographNFTBase(10) {
  //   vm.deal(address(0x456), 1 ether);
  //   vm.prank(address(0x456));
  //   vm.expectRevert(IERC721Drop.Sale_Inactive.selector);
  //   holographNFTBase.purchase{value: 0.12 ether}(1);
  //   vm.prank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.setSaleConfiguration({
  //     publicSaleStart: 0,
  //     publicSaleEnd: type(uint64).max,
  //     presaleStart: 0,
  //     presaleEnd: 0,
  //     publicSalePrice: 0.15 ether,
  //     maxSalePurchasePerAddress: 2,
  //     presaleMerkleRoot: bytes32(0)
  //   });
  //   vm.prank(address(0x456));
  //   vm.expectRevert(abi.encodeWithSelector(IERC721Drop.Purchase_WrongPrice.selector, 0.15 ether));
  //   holographNFTBase.purchase{value: 0.12 ether}(1);
  // }

  // function test_Withdraw(uint128 amount) public setupHolographNFTBase(10) {
  //   vm.assume(amount > 0.01 ether);
  //   vm.deal(address(holographNFTBase), amount);
  //   vm.prank(DEFAULT_OWNER_ADDRESS);
  //   vm.expectEmit(true, true, true, true);
  //   uint256 leftoverFunds = amount - (amount * 1) / 20;
  //   emit FundsWithdrawn(
  //     DEFAULT_OWNER_ADDRESS,
  //     DEFAULT_FUNDS_RECIPIENT_ADDRESS,
  //     leftoverFunds,
  //     DEFAULT_HOLOGRAPH_DAO_ADDRESS,
  //     (amount * 1) / 20
  //   );
  //   holographNFTBase.withdraw();

  //   (, uint256 feeBps) = feeManager.getHOLOGRAPHWithdrawFeesBPS(address(holographNFTBase));
  //   assertEq(feeBps, 500);

  //   assertTrue(
  //     DEFAULT_HOLOGRAPH_DAO_ADDRESS.balance < ((uint256(amount) * 1_000 * 5) / 100000) + 2 ||
  //       DEFAULT_HOLOGRAPH_DAO_ADDRESS.balance > ((uint256(amount) * 1_000 * 5) / 100000) + 2
  //   );
  //   assertTrue(
  //     DEFAULT_FUNDS_RECIPIENT_ADDRESS.balance > ((uint256(amount) * 1_000 * 95) / 100000) - 2 ||
  //       DEFAULT_FUNDS_RECIPIENT_ADDRESS.balance < ((uint256(amount) * 1_000 * 95) / 100000) + 2
  //   );
  // }

  // function test_MintLimit(uint8 limit) public setupHolographNFTBase(5000) {
  //   // set limit to speed up tests
  //   vm.assume(limit > 0 && limit < 50);
  //   vm.prank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.setSaleConfiguration({
  //     publicSaleStart: 0,
  //     publicSaleEnd: type(uint64).max,
  //     presaleStart: 0,
  //     presaleEnd: 0,
  //     publicSalePrice: 0.1 ether,
  //     maxSalePurchasePerAddress: limit,
  //     presaleMerkleRoot: bytes32(0)
  //   });
  //   vm.deal(address(0x456), 1_000_000 ether);
  //   vm.prank(address(0x456));
  //   holographNFTBase.purchase{value: 0.1 ether * uint256(limit)}(limit);

  //   assertEq(holographNFTBase.saleDetails().totalMinted, limit);

  //   vm.deal(address(0x444), 1_000_000 ether);
  //   vm.prank(address(0x444));
  //   vm.expectRevert(IERC721Drop.Purchase_TooManyForAddress.selector);
  //   holographNFTBase.purchase{value: 0.1 ether * (uint256(limit) + 1)}(uint256(limit) + 1);

  //   assertEq(holographNFTBase.saleDetails().totalMinted, limit);
  // }

  // function testSetSalesConfiguration() public setupHolographNFTBase(10) {
  //   vm.prank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.setSaleConfiguration({
  //     publicSaleStart: 0,
  //     publicSaleEnd: type(uint64).max,
  //     presaleStart: 0,
  //     presaleEnd: 100,
  //     publicSalePrice: 0.1 ether,
  //     maxSalePurchasePerAddress: 10,
  //     presaleMerkleRoot: bytes32(0)
  //   });

  //   (, , , , , uint64 presaleEndLookup, ) = holographNFTBase.salesConfig();
  //   assertEq(presaleEndLookup, 100);

  //   address SALES_MANAGER_ADDR = address(0x11002);
  //   vm.startPrank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.grantRole(holographNFTBase.SALES_MANAGER_ROLE(), SALES_MANAGER_ADDR);
  //   vm.stopPrank();
  //   vm.prank(SALES_MANAGER_ADDR);
  //   holographNFTBase.setSaleConfiguration({
  //     publicSaleStart: 0,
  //     publicSaleEnd: type(uint64).max,
  //     presaleStart: 100,
  //     presaleEnd: 0,
  //     publicSalePrice: 0.1 ether,
  //     maxSalePurchasePerAddress: 1003,
  //     presaleMerkleRoot: bytes32(0)
  //   });

  //   (, , , , uint64 presaleStartLookup2, uint64 presaleEndLookup2, ) = holographNFTBase.salesConfig();
  //   assertEq(presaleEndLookup2, 0);
  //   assertEq(presaleStartLookup2, 100);
  // }

  // function test_GlobalLimit(uint16 limit) public setupHolographNFTBase(uint64(limit)) {
  //   vm.assume(limit > 0);
  //   vm.startPrank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.adminMint(DEFAULT_OWNER_ADDRESS, limit);
  //   vm.expectRevert(IERC721Drop.Mint_SoldOut.selector);
  //   holographNFTBase.adminMint(DEFAULT_OWNER_ADDRESS, 1);
  // }

  // function test_WithdrawNotAllowed() public setupHolographNFTBase(10) {
  //   vm.expectRevert(IERC721Drop.Access_WithdrawNotAllowed.selector);
  //   holographNFTBase.withdraw();
  // }

  // function test_InvalidFinalizeOpenEdition() public setupHolographNFTBase(5) {
  //   vm.prank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.setSaleConfiguration({
  //     publicSaleStart: 0,
  //     publicSaleEnd: type(uint64).max,
  //     presaleStart: 0,
  //     presaleEnd: 0,
  //     publicSalePrice: 0.2 ether,
  //     presaleMerkleRoot: bytes32(0),
  //     maxSalePurchasePerAddress: 5
  //   });
  //   holographNFTBase.purchase{value: 0.6 ether}(3);
  //   vm.prank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.adminMint(address(0x1234), 2);
  //   vm.prank(DEFAULT_OWNER_ADDRESS);
  //   vm.expectRevert(IERC721Drop.Admin_UnableToFinalizeNotOpenEdition.selector);
  //   holographNFTBase.finalizeOpenEdition();
  // }

  // function test_ValidFinalizeOpenEdition() public setupHolographNFTBase(type(uint64).max) {
  //   vm.prank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.setSaleConfiguration({
  //     publicSaleStart: 0,
  //     publicSaleEnd: type(uint64).max,
  //     presaleStart: 0,
  //     presaleEnd: 0,
  //     publicSalePrice: 0.2 ether,
  //     presaleMerkleRoot: bytes32(0),
  //     maxSalePurchasePerAddress: 10
  //   });
  //   holographNFTBase.purchase{value: 0.6 ether}(3);
  //   vm.prank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.adminMint(address(0x1234), 2);
  //   vm.prank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.finalizeOpenEdition();
  //   vm.expectRevert(IERC721Drop.Mint_SoldOut.selector);
  //   vm.prank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.adminMint(address(0x1234), 2);
  //   vm.expectRevert(IERC721Drop.Mint_SoldOut.selector);
  //   holographNFTBase.purchase{value: 0.6 ether}(3);
  // }

  // function test_AdminMint() public setupHolographNFTBase(10) {
  //   address minter = address(0x32402);
  //   vm.startPrank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.adminMint(DEFAULT_OWNER_ADDRESS, 1);
  //   require(holographNFTBase.balanceOf(DEFAULT_OWNER_ADDRESS) == 1, "Wrong balance");
  //   holographNFTBase.grantRole(holographNFTBase.MINTER_ROLE(), minter);
  //   vm.stopPrank();
  //   vm.prank(minter);
  //   holographNFTBase.adminMint(minter, 1);
  //   require(holographNFTBase.balanceOf(minter) == 1, "Wrong balance");
  //   assertEq(holographNFTBase.saleDetails().totalMinted, 2);
  // }

  // function test_EditionSizeZero() public setupHolographNFTBase(0) {
  //   address minter = address(0x32402);
  //   vm.startPrank(DEFAULT_OWNER_ADDRESS);
  //   vm.expectRevert(IERC721Drop.Mint_SoldOut.selector);
  //   holographNFTBase.adminMint(DEFAULT_OWNER_ADDRESS, 1);
  //   holographNFTBase.grantRole(holographNFTBase.MINTER_ROLE(), minter);
  //   vm.stopPrank();
  //   vm.prank(minter);
  //   vm.expectRevert(IERC721Drop.Mint_SoldOut.selector);
  //   holographNFTBase.adminMint(minter, 1);

  //   vm.prank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.setSaleConfiguration({
  //     publicSaleStart: 0,
  //     publicSaleEnd: type(uint64).max,
  //     presaleStart: 0,
  //     presaleEnd: 0,
  //     publicSalePrice: 1,
  //     maxSalePurchasePerAddress: 2,
  //     presaleMerkleRoot: bytes32(0)
  //   });

  //   vm.deal(address(0x456), uint256(1) * 2);
  //   vm.prank(address(0x456));
  //   vm.expectRevert(IERC721Drop.Mint_SoldOut.selector);
  //   holographNFTBase.purchase{value: 1}(1);
  // }

  // // test Admin airdrop
  // function test_AdminMintAirdrop() public setupHolographNFTBase(1000) {
  //   vm.startPrank(DEFAULT_OWNER_ADDRESS);
  //   address[] memory toMint = new address[](4);
  //   toMint[0] = address(0x10);
  //   toMint[1] = address(0x11);
  //   toMint[2] = address(0x12);
  //   toMint[3] = address(0x13);
  //   holographNFTBase.adminMintAirdrop(toMint);
  //   assertEq(holographNFTBase.saleDetails().totalMinted, 4);
  //   assertEq(holographNFTBase.balanceOf(address(0x10)), 1);
  //   assertEq(holographNFTBase.balanceOf(address(0x11)), 1);
  //   assertEq(holographNFTBase.balanceOf(address(0x12)), 1);
  //   assertEq(holographNFTBase.balanceOf(address(0x13)), 1);
  // }

  // function test_AdminMintAirdropFails() public setupHolographNFTBase(1000) {
  //   vm.startPrank(address(0x10));
  //   address[] memory toMint = new address[](4);
  //   toMint[0] = address(0x10);
  //   toMint[1] = address(0x11);
  //   toMint[2] = address(0x12);
  //   toMint[3] = address(0x13);
  //   bytes32 minterRole = holographNFTBase.MINTER_ROLE();
  //   vm.expectRevert(abi.encodeWithSignature("Access_MissingRoleOrAdmin(bytes32)", minterRole));
  //   holographNFTBase.adminMintAirdrop(toMint);
  // }

  // // test admin mint non-admin permissions
  // function test_AdminMintBatch() public setupHolographNFTBase(1000) {
  //   vm.startPrank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.adminMint(DEFAULT_OWNER_ADDRESS, 100);
  //   assertEq(holographNFTBase.saleDetails().totalMinted, 100);
  //   assertEq(holographNFTBase.balanceOf(DEFAULT_OWNER_ADDRESS), 100);
  // }

  // function test_AdminMintBatchFails() public setupHolographNFTBase(1000) {
  //   vm.startPrank(address(0x10));
  //   bytes32 role = holographNFTBase.MINTER_ROLE();
  //   vm.expectRevert(abi.encodeWithSignature("Access_MissingRoleOrAdmin(bytes32)", role));
  //   holographNFTBase.adminMint(address(0x10), 100);
  // }

  // function test_Burn() public setupHolographNFTBase(10) {
  //   address minter = address(0x32402);
  //   vm.startPrank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.grantRole(holographNFTBase.MINTER_ROLE(), minter);
  //   vm.stopPrank();
  //   vm.startPrank(minter);
  //   address[] memory airdrop = new address[](1);
  //   airdrop[0] = minter;
  //   holographNFTBase.adminMintAirdrop(airdrop);
  //   holographNFTBase.burn(1);
  //   vm.stopPrank();
  // }

  // function test_BurnNonOwner() public setupHolographNFTBase(10) {
  //   address minter = address(0x32402);
  //   vm.startPrank(DEFAULT_OWNER_ADDRESS);
  //   holographNFTBase.grantRole(holographNFTBase.MINTER_ROLE(), minter);
  //   vm.stopPrank();
  //   vm.startPrank(minter);
  //   address[] memory airdrop = new address[](1);
  //   airdrop[0] = minter;
  //   holographNFTBase.adminMintAirdrop(airdrop);
  //   vm.stopPrank();

  //   vm.prank(address(0x1));
  //   vm.expectRevert(IERC721AUpgradeable.TransferCallerNotOwnerNorApproved.selector);
  //   holographNFTBase.burn(1);
  // }

  // // Add test burn failure state for users that don't own the token

  // function test_EIP165() public view {
  //   require(holographNFTBase.supportsInterface(0x01ffc9a7), "supports 165");
  //   require(holographNFTBase.supportsInterface(0x80ac58cd), "supports 721");
  //   require(holographNFTBase.supportsInterface(0x5b5e139f), "supports 721-metdata");
  //   require(holographNFTBase.supportsInterface(0x2a55205a), "supports 2981");
  //   require(!holographNFTBase.supportsInterface(0x0000000), "doesnt allow non-interface");
  // }
}
