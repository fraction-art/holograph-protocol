/*HOLOGRAPH_LICENSE_HEADER*/

/*SOLIDITY_COMPILER_VERSION*/

import {ERC721H} from "../../abstract/ERC721H.sol";
import {NonReentrant} from "../../abstract/NonReentrant.sol";

import {HolographTreasury} from "../../HolographTreasury.sol";

import {HolographERC721Interface} from "../../interface/HolographERC721Interface.sol";
import {HolographerInterface} from "../../interface/HolographerInterface.sol";
import {HolographInterface} from "../../interface/HolographInterface.sol";

import {AddressMintDetails} from "../struct/AddressMintDetails.sol";
import {Configuration} from "../struct/Configuration.sol";
import {DropsInitializer} from "../struct/DropsInitializer.sol";
import {SaleDetails} from "../struct/SaleDetails.sol";
import {SalesConfiguration} from "../struct/SalesConfiguration.sol";

import {Address} from "../library/Address.sol";
import {MerkleProof} from "../library/MerkleProof.sol";

import {IMetadataRenderer} from "../interface/IMetadataRenderer.sol";
import {IHolographDropERC721} from "../interface/IHolographDropERC721.sol";

import {IDropsPriceOracle} from "../interface/IDropsPriceOracle.sol";

/**
 * @dev This contract subscribes to the following HolographERC721 events:
 *       - beforeSafeTransfer
 *       - beforeTransfer
 *       - onIsApprovedForAll
 *       - customContractURI
 *
 *       Do not enable or subscribe to any other events unless you modified your source code for them.
 */
contract HolographDropERC721 is NonReentrant, ERC721H, IHolographDropERC721 {
  /**
   * CONTRACT VARIABLES
   * all variables, without custom storage slots, are defined here
   */

  /**
   * @dev Address of the price oracle proxy
   */
  IDropsPriceOracle public constant dropsPriceOracle = IDropsPriceOracle(0x34D76b88BC848aaFD11CA609cC6ab6fEEC638A51);

  /**
   * @dev Instance of the Holograph Treasury
   */
  HolographTreasury public holographTreasury;

  /**
   * @dev Internal reference used for minting incremental token ids.
   */
  uint224 private _currentTokenId;

  /**
   * @dev HOLOGRAPH transfer helper address for auto-approval
   */
  address public erc721TransferHelper;

  /// @dev Gas limit for transferring funds
  uint256 private constant STATIC_GAS_LIMIT = 210_000;

  /**
   * @notice Configuration for NFT minting contract storage
   */
  Configuration public config;

  /**
   * @notice Sales configuration
   */
  SalesConfiguration public salesConfig;

  /**
   * @dev Mapping for presale mint counts by address to allow public mint limit
   */
  mapping(address => uint256) public presaleMintsByAddress;

  /**
   * @dev Mapping for presale mint counts by address to allow public mint limit
   */
  mapping(address => uint256) public totalMintsByAddress;

  /**
   * CUSTOM ERRORS
   */

  /**
   * MODIFIERS
   */

  /**
   * @notice Allows user to mint tokens at a quantity
   */
  modifier canMintTokens(uint256 quantity) {
    if (config.editionSize != 0 && quantity + _currentTokenId > config.editionSize) {
      revert Mint_SoldOut();
    }

    _;
  }

  /**
   * @notice Presale active
   */
  modifier onlyPresaleActive() {
    if (!_presaleActive()) {
      revert Presale_Inactive();
    }

    _;
  }

  /**
   * @notice Public sale active
   */
  modifier onlyPublicSaleActive() {
    if (!_publicSaleActive()) {
      revert Sale_Inactive();
    }

    _;
  }

  /**
   * CONTRACT INITIALIZERS
   * init function is used instead of constructor
   */

  /**
   * @dev Constructor is left empty and init is used instead
   */
  constructor() {}

  /**
   * @notice Used internally to initialize the contract instead of through a constructor
   * @dev This function is called by the deployer/factory when creating a contract
   * @param initPayload abi encoded payload to use for contract initilaization
   */
  function init(bytes memory initPayload) external override returns (bytes4) {
    require(!_isInitialized(), "HOLOGRAPH: already initialized");

    DropsInitializer memory initializer = abi.decode(initPayload, (DropsInitializer));

    erc721TransferHelper = initializer.erc721TransferHelper;

    // Setup the owner role
    _setOwner(initializer.initialOwner);

    // to enable sourceExternalCall to work on init, we set holographer here since it's only set after init
    assembly {
      sstore(_holographerSlot, caller())
    }

    // Setup config variables
    config = Configuration({
      metadataRenderer: IMetadataRenderer(initializer.metadataRenderer),
      editionSize: initializer.editionSize,
      royaltyBPS: initializer.royaltyBPS,
      fundsRecipient: initializer.fundsRecipient
    });

    salesConfig = initializer.salesConfiguration;

    // TODO: Need to make sure to initialize the metadata renderer
    if (initializer.metadataRenderer != address(0)) {
      IMetadataRenderer(initializer.metadataRenderer).initializeWithData(initializer.metadataRendererInit);
    }

    setStatus(1);

    return _init(initPayload);
  }

  /**
   * PUBLIC NON STATE CHANGING FUNCTIONS
   * static
   */

  /**
   * @notice Returns the version of the contract
   * @dev Used for contract versioning and validation
   * @return version string representing the version of the contract
   */
  function version() external pure returns (string memory) {
    return "1.0.0";
  }

  function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
    return interfaceId == type(IHolographDropERC721).interfaceId;
  }

  /**
   * PUBLIC NON STATE CHANGING FUNCTIONS
   * dynamic
   */

  function owner() external view override(ERC721H, IHolographDropERC721) returns (address) {
    return _getOwner();
  }

  function isAdmin(address user) external view returns (bool) {
    return (_getOwner() == user);
  }

  function onIsApprovedForAll(address /* _wallet*/, address _operator) external view returns (bool approved) {
    approved = (erc721TransferHelper != address(0) && _operator == erc721TransferHelper);
  }

  /**
   * @notice Sale details
   * @return SaleDetails sale information details
   */
  function saleDetails() external view returns (SaleDetails memory) {
    return
      SaleDetails({
        publicSaleActive: _publicSaleActive(),
        presaleActive: _presaleActive(),
        publicSalePrice: salesConfig.publicSalePrice,
        publicSaleStart: salesConfig.publicSaleStart,
        publicSaleEnd: salesConfig.publicSaleEnd,
        presaleStart: salesConfig.presaleStart,
        presaleEnd: salesConfig.presaleEnd,
        presaleMerkleRoot: salesConfig.presaleMerkleRoot,
        totalMinted: _currentTokenId,
        maxSupply: config.editionSize,
        maxSalePurchasePerAddress: salesConfig.maxSalePurchasePerAddress
      });
  }

  /// @notice The Holograph fee is a flat fee for each mint in USD
  /// @dev Gets the Holograph protocol fee for amount of mints in USD
  function getHolographFeeUsd(uint256 quantity) public returns (uint256 fee) {
    fee = _getHolographTreasury().holographMintFee() * quantity;
  }

  /// @notice The Holograph fee is a flat fee for each mint in wei after conversion
  /// @dev Gets the Holograph protocol fee for amount of mints in wei
  function getHolographFeeWei(uint256 quantity) public returns (uint256) {
    return _usdToWei(_getHolographTreasury().holographMintFee() * quantity);
  }

  /**
   * @dev Number of NFTs the user has minted per address
   * @param minter to get counts for
   */
  function mintedPerAddress(address minter) external view returns (AddressMintDetails memory) {
    return
      AddressMintDetails({
        presaleMints: presaleMintsByAddress[minter],
        publicMints: totalMintsByAddress[minter] - presaleMintsByAddress[minter],
        totalMints: totalMintsByAddress[minter]
      });
  }

  /**
   * @notice Contract URI Getter, proxies to metadataRenderer
   * @return Contract URI
   */
  function contractURI() external view returns (string memory) {
    return config.metadataRenderer.contractURI();
  }

  /**
   * @notice Getter for metadataRenderer contract
   */
  function metadataRenderer() external view returns (IMetadataRenderer) {
    return IMetadataRenderer(config.metadataRenderer);
  }

  /**
   * @notice Convert USD price to current price in native Ether units
   */
  function getNativePrice() external view returns (uint256) {
    return _usdToWei(salesConfig.publicSalePrice);
  }

  /**
   * @notice Returns the name of the token through the holographer entrypoint
   */
  function name() external view returns (string memory) {
    return HolographERC721Interface(holographer()).name();
  }

  /**
   * @notice Token URI Getter, proxies to metadataRenderer
   * @param tokenId id of token to get URI for
   * @return Token URI
   */
  function tokenURI(uint256 tokenId) external view returns (string memory) {
    HolographERC721Interface H721 = HolographERC721Interface(holographer());
    require(H721.exists(tokenId), "ERC721: token does not exist");

    return config.metadataRenderer.tokenURI(tokenId);
  }

  /**
   * PUBLIC STATE CHANGING FUNCTIONS
   * available to all
   */

  function multicall(bytes[] memory data) public returns (bytes[] memory results) {
    results = new bytes[](data.length);
    for (uint256 i = 0; i < data.length; i++) {
      results[i] = Address.functionDelegateCall(address(this), abi.encodePacked(data[i], msgSender()));
    }
  }

  /**
   * @dev This allows the user to purchase/mint a edition at the given price in the contract.
   */
  function purchase(
    uint256 quantity
  ) external payable nonReentrant canMintTokens(quantity) onlyPublicSaleActive returns (uint256) {
    uint256 salePrice = _usdToWei(salesConfig.publicSalePrice);
    uint256 holographMintFeeInWei = _usdToWei(_getHolographTreasury().holographMintFee());

    if (msg.value < (salePrice + holographMintFeeInWei) * quantity) {
      // The error will display the wrong price that was sent in USD
      revert Purchase_WrongPrice((salesConfig.publicSalePrice + _getHolographTreasury().holographMintFee()) * quantity);
    }
    uint256 remainder = msg.value - (salePrice * quantity);

    // If max purchase per address == 0 there is no limit.
    // Any other number, the per address mint limit is that.
    if (
      salesConfig.maxSalePurchasePerAddress != 0 &&
      totalMintsByAddress[msgSender()] + quantity - presaleMintsByAddress[msgSender()] >
      salesConfig.maxSalePurchasePerAddress
    ) {
      revert Purchase_TooManyForAddress();
    }

    // First mint the NFTs
    _mintNFTs(msgSender(), quantity);

    // Then send the Holograph fee to the recipient (currently the Holograph Treasury)
    _payoutHolographFee(quantity);

    HolographERC721Interface H721 = HolographERC721Interface(holographer());
    uint256 chainPrepend = H721.sourceGetChainPrepend();
    uint256 firstMintedTokenId = (chainPrepend + uint256(_currentTokenId - quantity)) + 1;

    emit Sale({
      to: msgSender(),
      quantity: quantity,
      pricePerToken: salePrice,
      firstPurchasedTokenId: firstMintedTokenId
    });

    // Refund any overpayment
    if (remainder > 0) {
      msgSender().call{value: remainder, gas: gasleft() > STATIC_GAS_LIMIT ? STATIC_GAS_LIMIT : gasleft()}("");
    }

    return firstMintedTokenId;
  }

  /**
   * @notice Merkle-tree based presale purchase function
   * @param quantity quantity to purchase
   * @param maxQuantity max quantity that can be purchased via merkle proof #
   * @param pricePerToken price that each token is purchased at
   * @param merkleProof proof for presale mint
   */
  function purchasePresale(
    uint256 quantity,
    uint256 maxQuantity,
    uint256 pricePerToken,
    bytes32[] calldata merkleProof
  ) external payable nonReentrant canMintTokens(quantity) onlyPresaleActive returns (uint256) {
    if (
      !MerkleProof.verify(
        merkleProof,
        salesConfig.presaleMerkleRoot,
        keccak256(
          // address, uint256, uint256
          abi.encode(msgSender(), maxQuantity, pricePerToken)
        )
      )
    ) {
      revert Presale_MerkleNotApproved();
    }

    uint256 weiPricePerToken = _usdToWei(pricePerToken);
    if (msg.value < weiPricePerToken * quantity) {
      revert Purchase_WrongPrice(pricePerToken * quantity);
    }
    uint256 remainder = msg.value - (weiPricePerToken * quantity);

    presaleMintsByAddress[msgSender()] += quantity;
    if (presaleMintsByAddress[msgSender()] > maxQuantity) {
      revert Presale_TooManyForAddress();
    }

    // First mint the NFTs
    _mintNFTs(msgSender(), quantity);

    // Then send the Holograph fee to the recipient (currently the Holograph Treasury)
    _payoutHolographFee(quantity);

    HolographERC721Interface H721 = HolographERC721Interface(holographer());
    uint256 chainPrepend = H721.sourceGetChainPrepend();
    uint256 firstMintedTokenId = (chainPrepend + uint256(_currentTokenId - quantity)) + 1;

    emit Sale({
      to: msgSender(),
      quantity: quantity,
      pricePerToken: weiPricePerToken,
      firstPurchasedTokenId: firstMintedTokenId
    });

    // Refund any overpayment
    if (remainder > 0) {
      msgSender().call{value: remainder, gas: gasleft() > STATIC_GAS_LIMIT ? STATIC_GAS_LIMIT : gasleft()}("");
    }

    return firstMintedTokenId;
  }

  /**
   * PUBLIC STATE CHANGING FUNCTIONS
   * admin only
   */

  /**
   * @notice Admin mint tokens to a recipient for free
   * @param recipient recipient to mint to
   * @param quantity quantity to mint
   */
  function adminMint(address recipient, uint256 quantity) external onlyOwner canMintTokens(quantity) returns (uint256) {
    _mintNFTs(recipient, quantity);

    return _currentTokenId;
  }

  /**
   * @dev Mints multiple editions to the given list of addresses.
   * @param recipients list of addresses to send the newly minted editions to
   */
  function adminMintAirdrop(
    address[] calldata recipients
  ) external onlyOwner canMintTokens(recipients.length) returns (uint256) {
    unchecked {
      for (uint256 i = 0; i < recipients.length; i++) {
        _mintNFTs(recipients[i], 1);
      }
    }

    return _currentTokenId;
  }

  /**
   * @notice Set a new metadata renderer
   * @param newRenderer new renderer address to use
   * @param setupRenderer data to setup new renderer with
   */
  function setMetadataRenderer(IMetadataRenderer newRenderer, bytes memory setupRenderer) external onlyOwner {
    config.metadataRenderer = newRenderer;

    if (setupRenderer.length > 0) {
      newRenderer.initializeWithData(setupRenderer);
    }

    emit UpdatedMetadataRenderer({sender: msgSender(), renderer: newRenderer});
  }

  /**
   * @dev This sets the sales configuration
   * @param publicSalePrice New public sale price
   * @param maxSalePurchasePerAddress Max # of purchases (public) per address allowed
   * @param publicSaleStart unix timestamp when the public sale starts
   * @param publicSaleEnd unix timestamp when the public sale ends (set to 0 to disable)
   * @param presaleStart unix timestamp when the presale starts
   * @param presaleEnd unix timestamp when the presale ends
   * @param presaleMerkleRoot merkle root for the presale information
   */
  function setSaleConfiguration(
    uint104 publicSalePrice,
    uint32 maxSalePurchasePerAddress,
    uint64 publicSaleStart,
    uint64 publicSaleEnd,
    uint64 presaleStart,
    uint64 presaleEnd,
    bytes32 presaleMerkleRoot
  ) external onlyOwner {
    salesConfig.publicSalePrice = publicSalePrice;
    salesConfig.maxSalePurchasePerAddress = maxSalePurchasePerAddress;
    salesConfig.publicSaleStart = publicSaleStart;
    salesConfig.publicSaleEnd = publicSaleEnd;
    salesConfig.presaleStart = presaleStart;
    salesConfig.presaleEnd = presaleEnd;
    salesConfig.presaleMerkleRoot = presaleMerkleRoot;

    emit SalesConfigChanged(msgSender());
  }

  /**
   * @notice Set a different funds recipient
   * @param newRecipientAddress new funds recipient address
   */
  function setFundsRecipient(address payable newRecipientAddress) external onlyOwner {
    if (newRecipientAddress == address(0)) {
      revert("Funds Recipient cannot be 0 address");
    }
    config.fundsRecipient = newRecipientAddress;
    emit FundsRecipientChanged(newRecipientAddress, msgSender());
  }

  /**
   * @notice This withdraws native tokens from the contract to the contract owner.
   */
  function withdraw() external override nonReentrant {
    if (config.fundsRecipient == address(0)) {
      revert("Funds Recipient address not set");
    }
    address sender = msgSender();

    // Get the contract balance
    uint256 funds = address(this).balance;

    // Check if withdraw is allowed for sender
    if (sender != config.fundsRecipient && sender != _getOwner()) {
      revert Access_WithdrawNotAllowed();
    }

    // Payout recipient
    (bool successFunds, ) = config.fundsRecipient.call{value: funds, gas: STATIC_GAS_LIMIT}("");
    if (!successFunds) {
      revert Withdraw_FundsSendFailure();
    }

    // Emit event for indexing
    emit FundsWithdrawn(sender, config.fundsRecipient, funds);
  }

  /**
   * @notice Admin function to finalize and open edition sale
   */
  function finalizeOpenEdition() external onlyOwner {
    if (config.editionSize != type(uint64).max) {
      revert Admin_UnableToFinalizeNotOpenEdition();
    }

    config.editionSize = uint64(_currentTokenId);
    emit OpenMintFinalized(msgSender(), config.editionSize);
  }

  /**
   * INTERNAL FUNCTIONS
   * non state changing
   */

  function _presaleActive() internal view returns (bool) {
    return salesConfig.presaleStart <= block.timestamp && salesConfig.presaleEnd > block.timestamp;
  }

  function _publicSaleActive() internal view returns (bool) {
    return salesConfig.publicSaleStart <= block.timestamp && salesConfig.publicSaleEnd > block.timestamp;
  }

  function _usdToWei(uint256 amount) internal view returns (uint256 weiAmount) {
    if (amount == 0) {
      return 0;
    }
    weiAmount = dropsPriceOracle.convertUsdToWei(amount);
  }

  /**
   * INTERNAL FUNCTIONS
   * state changing
   */

  function _mintNFTs(address recipient, uint256 quantity) internal {
    HolographERC721Interface H721 = HolographERC721Interface(holographer());
    uint256 chainPrepend = H721.sourceGetChainPrepend();
    uint224 tokenId = 0;
    for (uint256 i = 0; i < quantity; i++) {
      _currentTokenId += 1;
      while (
        H721.exists(chainPrepend + uint256(_currentTokenId)) || H721.burned(chainPrepend + uint256(_currentTokenId))
      ) {
        _currentTokenId += 1;
      }
      tokenId = _currentTokenId;
      H721.sourceMint(recipient, tokenId);

      // TODO: Should we emit this id?
      // uint256 id = chainPrepend + uint256(tokenId);
    }
  }

  /**
   * @notice Internal function to get the HolographTreasury instance
   * @dev This is used to get the HolographTreasury instance from the Holographer
   * @return HolographTreasury instance
   */
  function _getHolographTreasury() internal returns (HolographTreasury) {
    if (address(holographTreasury) == address(0)) {
      holographTreasury = HolographTreasury(
        payable(HolographInterface(HolographerInterface(holographer()).getHolograph()).getTreasury())
      );
    }
    return holographTreasury;
  }

  function _payoutHolographFee(uint256 quantity) internal {
    // Transfer protocol mint fee to recipient address
    uint256 holographMintFeeWei = getHolographFeeWei(quantity);

    // Payout Holograph fee using the cached (or fetched) instance
    address payable holographFeeRecipient = payable(address(_getHolographTreasury()));

    (bool success, ) = holographFeeRecipient.call{value: holographMintFeeWei, gas: STATIC_GAS_LIMIT}("");
    if (!success) {
      revert FeePaymentFailed();
    }
    emit MintFeePayout(holographMintFeeWei, holographFeeRecipient, success);
  }

  fallback() external payable override {
    assembly {
      // Allocate memory for the error message
      let errorMsg := mload(0x40)

      // Error message: "Function not found", properly padded with zeroes
      mstore(errorMsg, 0x46756e6374696f6e206e6f7420666f756e640000000000000000000000000000)

      // Revert with the error message
      revert(errorMsg, 20) // 20 is the length of the error message in bytes
    }
  }
}
