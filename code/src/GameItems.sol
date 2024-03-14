// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {Neuron} from "./Neuron.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

/// @title GameItems
/// @author ArenaX Labs Inc.
/// @notice This contract represents a collection of game items used in AI Arena.
contract GameItems is ERC1155 {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Event emitted when a game item is bought.
    /// @param buyer The address of the buyer.
    /// @param tokenId The id of the game item.
    /// @param quantity The quantity of the game item.
    event BoughtItem(address buyer, uint256 tokenId, uint256 quantity);

    /// @notice Event emitted when an item is locked and thus cannot be traded.
    /// @param tokenId The id of the game item.
    event Locked(uint256 tokenId);

    /// @notice Event emitted when an item is unlocked and can be traded.
    /// @param tokenId The id of the game item.
    event Unlocked(uint256 tokenId);

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Struct for game item attributes
    struct GameItemAttributes {
        string name;
        bool finiteSupply;
        bool transferable;
        uint256 itemsRemaining;
        uint256 itemPrice;
        uint256 dailyAllowance;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The name of this smart contract.
    string public name = "AI Arena Game Items";

    /// @notice The symbol for this smart contract.
    string public symbol = "AGI";

    /// @notice List of all gameItemAttribute structs representing all game items.
    GameItemAttributes[] public allGameItemAttributes;

    /// @notice The address that recieves funds of purchased game items.
    address public treasuryAddress;

    /// The address that has owner privileges (initially the contract deployer).
    address _ownerAddress;

    /// Total number of game items.
    uint256 _itemCount = 0;

    /// @dev The Neuron contract instance.
    Neuron _neuronInstance;

    /*//////////////////////////////////////////////////////////////
                                MAPPINGS
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping of address to tokenId to get remaining allowance.
    mapping(address => mapping(uint256 => uint256)) public allowanceRemaining;

    /// @notice Mapping of address to tokenId to get replenish timestamp.
    mapping(address => mapping(uint256 => uint256)) public dailyAllowanceReplenishTime;

    /// @notice Mapping tracking addresses allowed to burn game items.
    mapping(address => bool) public allowedBurningAddresses;

    /// @notice Mapping tracking addresses allowed to manage game items.
    mapping(address => bool) public isAdmin;

    /// @notice Mapping of token id to the token URI
    mapping(uint256 => string) private _tokenURIs;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the owner address and the isAdmin mapping to true for the owner address.
    /// @param ownerAddress Address of contract deployer.
    /// @param treasuryAddress_ Address of admin signer for messages.
    constructor(address ownerAddress, address treasuryAddress_) ERC1155("https://ipfs.io/ipfs/") {
        _ownerAddress = ownerAddress;
        treasuryAddress = treasuryAddress_;
        isAdmin[_ownerAddress] = true;
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfers ownership from one address to another.
    /// @dev Only the owner address is authorized to call this function.
    /// @param newOwnerAddress The address of the new owner
    function transferOwnership(address newOwnerAddress) external {
        require(msg.sender == _ownerAddress);
        _ownerAddress = newOwnerAddress;
    }

    /// @notice Adjusts admin access for a user.
    /// @dev Only the owner address is authorized to call this function.
    /// @param adminAddress The address of the admin.
    /// @param access Whether the address has admin access or not.
    function adjustAdminAccess(address adminAddress, bool access) external {
        require(msg.sender == _ownerAddress);
        isAdmin[adminAddress] = access;
    }

    /// @notice Adjusts whether the game item can be transferred or not
    /// @dev Only the owner address is authorized to call this function.
    /// @param tokenId The token id for the specific game item being adjusted.
    /// @param transferable Whether the game item is transferable or not
    function adjustTransferability(uint256 tokenId, bool transferable) external {
        require(msg.sender == _ownerAddress);
        allGameItemAttributes[tokenId].transferable = transferable;
        if (transferable) {
            emit Unlocked(tokenId);
        } else {
            emit Locked(tokenId);
        }
    }

    /// @notice Sets the Neuron contract address and instantiates the contract.
    /// @dev Only the owner address is authorized to call this function.
    /// @param nrnAddress The address of the Neuron contract.
    function instantiateNeuronContract(address nrnAddress) external {
        require(msg.sender == _ownerAddress);
        _neuronInstance = Neuron(nrnAddress);
    }

    /// @notice Mints game items and assigns them to the caller.
    /// @param tokenId The ID of the game item to mint.
    /// @param quantity The quantity of game items to mint.
    function mint(uint256 tokenId, uint256 quantity) external {
        //first item is 0, itemCount = 1
        //@audit-ok check for other rules to be applied: require... :: finiteSupply, itemsRemaining, dailyAllowance
        require(tokenId < _itemCount);
        uint256 price = allGameItemAttributes[tokenId].itemPrice * quantity;
        require(_neuronInstance.balanceOf(msg.sender) >= price, "Not enough NRN for purchase");

        //@audit-ok 2 things need to be checked: allGameItemAttributes[tokenId].itemsRemaining && allowanceRemaining[msg.sender][tokenId]
        require(
            allGameItemAttributes[tokenId].finiteSupply == false ||
                (allGameItemAttributes[tokenId].finiteSupply == true && quantity <= allGameItemAttributes[tokenId].itemsRemaining)
        );

        require(
            //@audit-ok should be && --- OR: delete: dailyAllowanceReplenishTime[msg.sender][tokenId] <= block.timestamp
            //check: dailyAllowanceReplenishTime & call if < : _replenishDailyAllowance(tokenId);
            //case: dailyAllowanceReplenishTime is fine, BUT quantity > allowanceRemaining => this passes
            //with each purchase, allowanceRemaining is set to max
            //Problem case: assume dailyAllowanceReplenishTime is fine => buy more items than allowanceRemaining (not checked)
            dailyAllowanceReplenishTime[msg.sender][tokenId] <= block.timestamp || quantity <= allowanceRemaining[msg.sender][tokenId]
        );

        require(quantity <= allGameItemAttributes[tokenId].dailyAllowance, "daily allowance exceeded");

        _neuronInstance.approveSpender(msg.sender, price);

        bool success = _neuronInstance.transferFrom(msg.sender, treasuryAddress, price);
        if (success) {
            if (dailyAllowanceReplenishTime[msg.sender][tokenId] <= block.timestamp) {
                //set allowanceRemaining = max && dailyAllowanceReplenishTime = +1 day
                //@audit-ok call this function at the beginning
                _replenishDailyAllowance(tokenId); //dailyAllowance is reset => allowanceRemaining
            }

            //@audit-ok underflow

            //require(quantity <= allowanceRemaining[msg.sender][tokenId], "");
            allowanceRemaining[msg.sender][tokenId] -= quantity;

            if (allGameItemAttributes[tokenId].finiteSupply) {
                allGameItemAttributes[tokenId].itemsRemaining -= quantity;
            }

            _mint(msg.sender, tokenId, quantity, bytes("random"));
            emit BoughtItem(msg.sender, tokenId, quantity);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the allowed burning addresses.
    /// @dev Only the admins are authorized to call this function.
    /// @param newBurningAddress The address to allow for burning.
    function setAllowedBurningAddresses(address newBurningAddress) public {
        require(isAdmin[msg.sender]);
        allowedBurningAddresses[newBurningAddress] = true;
    }

    /// @notice Sets the token URI for a game item
    /// @dev Only the admins are authorized to call this function.
    /// @param tokenId The token id for the specific game item being queried.
    /// @param _tokenURI The token id to be set
    function setTokenURI(uint256 tokenId, string memory _tokenURI) public {
        require(isAdmin[msg.sender]);
        _tokenURIs[tokenId] = _tokenURI;
    }

    /// @notice Creates a new game item with the specified attributes.
    /// @dev Only the admins are authorized to call this function.
    /// @param name_ The name of the game item.
    /// @param tokenURI The URI of the game item.
    /// @param finiteSupply Determines if the game item has a finite supply.
    /// @param transferable Boolean of whether or not the game item can be transferred
    /// @param itemsRemaining The number of remaining items for the game item.
    /// @param itemPrice The price of the game item.
    /// @param dailyAllowance The daily allowance for the game item.
    function createGameItem(
        string memory name_,
        string memory tokenURI,
        bool finiteSupply,
        bool transferable,
        uint256 itemsRemaining,
        uint256 itemPrice,
        uint16 dailyAllowance
    ) public {
        //@audit-ok validation for: itemsRemaining, itemPrice, dailyAllowance
        require(isAdmin[msg.sender]);
        require(itemsRemaining > 0 && itemPrice > 0 && dailyAllowance > 0, "itemsRemaining, itemPrice and dailyAllowanc should be greater than 0");

        allGameItemAttributes.push(GameItemAttributes(name_, finiteSupply, transferable, itemsRemaining, itemPrice, dailyAllowance));
        if (!transferable) {
            emit Locked(_itemCount);
        }
        setTokenURI(_itemCount, tokenURI);
        _itemCount += 1;
    }

    /// @notice Burns a specified amount of game items from an account.
    /// @dev Only addresses listed in allowedBurningAddresses are authorized to call this function.
    /// @param account The account from which the game items will be burned.
    /// @param tokenId The ID of the game item.
    /// @param amount The amount of game items to burn.
    function burn(address account, uint256 tokenId, uint256 amount) public {
        require(allowedBurningAddresses[msg.sender]);
        _burn(account, tokenId, amount);
    }

    /// @notice Returns the URI where the contract metadata is stored.
    /// @return URI where the contract metadata is stored.
    function contractURI() public pure returns (string memory) {
        return "ipfs://bafybeih3witscmml3padf4qxbea5jh4rl2xp67aydqvqsxmyuzipwtpnii";
    }

    /// @notice Override the uri function to return the custom URI for each token
    /// @param tokenId The token id for the specific game item being queried.
    /// @return tokenURI The URI for the game item metadata.
    function uri(uint256 tokenId) public view override returns (string memory) {
        //@audit-ok check this
        string memory customURI = _tokenURIs[tokenId];
        if (bytes(customURI).length > 0) {
            return customURI;
        }
        return super.uri(tokenId);
    }

    /// @notice Gets the amount of a game item that a user is still able to mint for the day
    /// @param owner The user's address.
    /// @param tokenId The token id for the specific game item being queried.
    /// @return remaining number of items that can be minted for the day.
    function getAllowanceRemaining(address owner, uint256 tokenId) public view returns (uint256) {
        uint256 remaining = allowanceRemaining[owner][tokenId];
        if (dailyAllowanceReplenishTime[owner][tokenId] <= block.timestamp) {
            remaining = allGameItemAttributes[tokenId].dailyAllowance;
        }
        return remaining;
    }

    /// @notice Returns the remaining supply of a game item with the specified tokenId.
    /// @param tokenId The ID of the game item.
    /// @return Remaining items for the queried token ID.
    function remainingSupply(uint256 tokenId) public view returns (uint256) {
        return allGameItemAttributes[tokenId].itemsRemaining;
    }

    /// @notice Returns the total number of unique game tokens outstanding.
    /// @return Total number of unique game tokens.
    function uniqueTokensOutstanding() public view returns (uint256) {
        return allGameItemAttributes.length;
    }

    /// @notice Safely transfers an NFT from one address to another.
    /// @dev Added a check to see if the game item is transferable.
    function safeTransferFrom(address from, address to, uint256 tokenId, uint256 amount, bytes memory data) public override(ERC1155) {
        require(allGameItemAttributes[tokenId].transferable);
        super.safeTransferFrom(from, to, tokenId, amount, data);
    }

    /*//////////////////////////////////////////////////////////////
                            PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Replenishes the daily allowance for the specified game item token.
    /// @dev This function is called when a user buys a game item after the replenish interval has passed.
    /// @param tokenId The ID of the game item token.
    function _replenishDailyAllowance(uint256 tokenId) private {
        allowanceRemaining[msg.sender][tokenId] = allGameItemAttributes[tokenId].dailyAllowance;
        dailyAllowanceReplenishTime[msg.sender][tokenId] = uint32(block.timestamp + 1 days);
    }
}
