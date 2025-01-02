// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";  
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "erc721a/contracts/ERC721A.sol";


contract SwampNFT is ERC721A, Ownable, ReentrancyGuard {
    using Strings for uint256;
    using EnumerableMap for EnumerableMap.AddressToUintMap;

    // ------------------------
    // Configuration
    // ------------------------
    uint256 public constant MAX_SUPPLY = 10000;      // Updated Total supply to 10,000
    uint256 public constant MAX_PUBLIC_MINT = 10;   // Max 10 per wallet

    // Public mint price: 0.021 ETH
    uint256 public cost = 0.02 ether;

    // Toggle for reveal
    bool public revealedState = false;

    // Pause state for minting
    bool public mintPaused = false;

    // Track number of minted tokens by each user
    mapping(address => uint256) public publicMintCount;

    // Storage for URIs
    string private __baseURI;
    string private _notRevealedURI;

    // Splits
    EnumerableMap.AddressToUintMap private _splits;
    bool public splitsLocked;

    // Dev mint control
    bool public devMintLocked;

    // ------------------------
    // Constructor
    // ------------------------
    constructor(
        string memory initBaseURI_,
        string memory initNotRevealedURI_
    )
        ERC721A("swa.mp swamp", "SWAMP") // Collection name & symbol
        Ownable(msg.sender)
        checkURI(initBaseURI_)
        checkURI(initNotRevealedURI_)
    {
        __baseURI = initBaseURI_;
        _notRevealedURI = initNotRevealedURI_;
    }

    // ------------------------
    // Public Mint Function
    // ------------------------
    function mint(uint8 quantity)
        external
        payable
        supplyCheck(quantity)
        checkCost(cost, quantity)
        nonReentrant
    {
        require(!mintPaused, "[Error] Minting is paused");
        require(
            publicMintCount[msg.sender] + quantity <= MAX_PUBLIC_MINT,
            "[Error] Max Public Mint Reached"
        );

        publicMintCount[msg.sender] += quantity;
        _mint(msg.sender, quantity);
        _sendFunds(msg.value);
    }

    // ------------------------
    // Dev Mint
    // ------------------------
    function devMint(uint256 quantity) external onlyOwner supplyCheck(quantity) {
        require(!devMintLocked, "[Error] Dev mint is locked");
        _mint(msg.sender, quantity);
    }

    function lockDevMint() external onlyOwner {
        devMintLocked = true;
    }

    // ------------------------
    // URI & Reveal
    // ------------------------
    function setBaseURI(string memory newBaseURI)
        external
        onlyOwner
        nonReentrant
        checkURI(newBaseURI)
    {
        __baseURI = newBaseURI;
    }

    function setNotRevealedURI(string memory newNotRevealedURI)
        external
        onlyOwner
        nonReentrant
        checkURI(newNotRevealedURI)
    {
        _notRevealedURI = newNotRevealedURI;
    }

    function toggleReveal() external onlyOwner {
        revealedState = !revealedState;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_exists(tokenId), "[Error] URI query for nonexistent token");

        if (!revealedState) {
            return _notRevealedURI;
        }

        return string(abi.encodePacked(__baseURI, tokenId.toString(), ".json"));
    }

    // ------------------------
    // Admin Functions
    // ------------------------
    function setPublicMintPrice(uint256 value)
        external
        onlyOwner
        checkValue(value)
    {
        cost = value;
    }

    function withdraw() external onlyOwner {
        _sendFunds(address(this).balance);
    }

    // Pause and Resume Minting
    function pauseMinting() external onlyOwner {
        mintPaused = true;
    }

    function resumeMinting() external onlyOwner {
        mintPaused = false;
    }

    // ------------------------
    // Splits Management
    // ------------------------
    function setSplits(address[] memory recipients, uint256[] memory percentages)
        external
        onlyOwner
    {
        require(!splitsLocked, "[Error] Splits are locked");
        require(recipients.length == percentages.length, "[Error] Mismatched inputs");

        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            EnumerableMap.set(_splits, recipients[i], percentages[i]);
            totalPercentage += percentages[i];
        }

        require(totalPercentage == 100, "[Error] Percentages must total 100");
    }

    function lockSplits() external onlyOwner {
        splitsLocked = true;
    }

    // ------------------------
    // Modifiers
    // ------------------------
    modifier supplyCheck(uint256 quantity) {
        require(totalSupply() + quantity <= MAX_SUPPLY, "[Error] Max Supply Exceeded");
        _;
    }

    modifier checkCost(uint256 _cost, uint256 quantity) {
        require(msg.value >= _cost * quantity, "[Error] Insufficient Funds");
        _;
    }

    modifier checkURI(string memory uri) {
        require(bytes(uri).length > 0, "[Error] Invalid URI");
        _;
    }

    modifier checkValue(uint256 value) {
        require(value > 0, "[Error] Value cannot be 0");
        _;
    }

    // ------------------------
    // Internal Payment Handling
    // ------------------------
    function _sendFunds(uint256 amount) internal {
        require(EnumerableMap.length(_splits) > 0, "[Error] No splits defined");
        uint256 remaining = amount;

        for (uint256 i = 0; i < EnumerableMap.length(_splits); i++) {
            (address recipient, uint256 percentage) = EnumerableMap.at(_splits, i);
            uint256 payment = (amount * percentage) / 100;
            remaining -= payment;
            (bool success, ) = recipient.call{value: payment}("");
            require(success, "[Error] Payment failed");
        }

        require(remaining == 0, "[Error] Payment miscalculation");
    }
}
