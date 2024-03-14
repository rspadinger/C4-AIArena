// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {FighterFarm} from "./FighterFarm.sol";
import "forge-std/console.sol";

interface IRankedBattle {
    function setNewRound() external;
}

/// @title MergingPool
/// @author ArenaX Labs Inc.
/// @notice This contract allows users to potentially earn a new fighter NFT.
contract MergingPool {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Event emitted when merging pool points are added.
    event PointsAdded(uint256 tokenId, uint256 points);

    /// @notice Event emitted when claimed.
    event Claimed(address claimer, uint32 amount);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Number of winners per period.
    uint256 public winnersPerPeriod = 2;

    /// @notice Current roundId.
    uint256 public roundId = 0;

    /// @notice Total points.
    uint256 public totalPoints = 0;

    /// The address that has owner privileges (initially the contract deployer).
    address _ownerAddress;

    /// The address of the ranked battle contract.
    address _rankedBattleAddress;

    /// @dev The fighter farm contract instance.
    FighterFarm _fighterFarmInstance;

    /*//////////////////////////////////////////////////////////////
                                MAPPINGS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps the user address to the number of rounds they've claimed for
    mapping(address => uint32) public numRoundsClaimed;

    /// @notice Mapping of address to fighter points.
    mapping(uint256 => uint256) public fighterPoints;

    /// @notice Mapping of roundId to winner addresses list.
    mapping(uint256 => address[]) public winnerAddresses;

    /// @notice Mapping of round id to an indication of whether winners have been selected yet.
    mapping(uint256 => bool) public isSelectionComplete;

    /// @notice Mapping of address to admin status.
    mapping(address => bool) public isAdmin;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the address for the owner and ranked battle smart contract.
    /// Instantiates the fighter farm contract and sets the owner to be an admin
    /// @param ownerAddress Address of contract deployer.
    /// @param rankedBattleAddress Address of ranked battle contract.
    /// @param fighterFarmAddress Address of fighter farm contract.
    constructor(address ownerAddress, address rankedBattleAddress, address fighterFarmAddress) {
        _ownerAddress = ownerAddress;
        _rankedBattleAddress = rankedBattleAddress;
        _fighterFarmInstance = FighterFarm(fighterFarmAddress);
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

    /// @notice Change the number of winners per competition period.
    /// @dev Only admins are authorized to call this function.
    /// @param newWinnersPerPeriodAmount The new number of winners per period.
    function updateWinnersPerPeriod(uint256 newWinnersPerPeriodAmount) external {
        require(isAdmin[msg.sender]);
        winnersPerPeriod = newWinnersPerPeriodAmount;
    }

    /// @notice Allows the admin to pick the winners for the current round.
    /// @dev Only admins are authorized to call this function.
    /// @dev The number of winners must match the expected number of winners per period.
    /// @dev The function will check that there are no existing winners for the current round.
    /// @dev The function will update the winnerAddresses mapping with the addresses of the winners.
    /// @dev The function will also reset the fighterPoints of the winners to zero.
    /// @param winners The array of token IDs representing the winners.
    function pickWinner(uint256[] calldata winners) external {
        require(isAdmin[msg.sender]);
        require(winners.length == winnersPerPeriod, "Incorrect number of winners");
        require(!isSelectionComplete[roundId], "Winners are already selected");
        uint256 winnersLength = winners.length;
        address[] memory currentWinnerAddresses = new address[](winnersLength);

        for (uint256 i = 0; i < winnersLength; i++) {
            currentWinnerAddresses[i] = _fighterFarmInstance.ownerOf(winners[i]);
            //@audit-ok underflow
            //@audit-ok why are points only deducted from winners? => only winner gets points
            totalPoints -= fighterPoints[winners[i]];
            fighterPoints[winners[i]] = 0;
        }

        winnerAddresses[roundId] = currentWinnerAddresses;
        isSelectionComplete[roundId] = true;
        //@audit-ok should be set by RankedBattle => we could get out of sync => call this function in: RankedBattle.setNewRound()
        //what if admin forgets to call this in round x and calls only n round x+1 => consider making this a MEDIUM
        roundId += 1;

        IRankedBattle(_rankedBattleAddress).setNewRound();
    }

    //

    /// @notice Allows the user to batch claim rewards for multiple rounds.
    /// @dev The user can only claim rewards once for each round.
    /// @param modelURIs The array of model URIs corresponding to each round and winner address.
    /// @param modelTypes The array of model types corresponding to each round and winner address.
    /// @param customAttributes Array with [element, weight] of the newly created fighter.
    //@audit-ok check: uint256[2][] calldata customAttributes or: uint256[][2] calldata customAttributes
    //@audit-ok user could mint bad NFT by providing whatever data he wants - eg providing data from already minted NFT
    //@audit-ok the array size provided by the user needs to correspond to number of his wins for all unclaimed rounds => allow to claim specific reward
    function claimRewards(string[] calldata modelURIs, string[] calldata modelTypes, uint256[2][] calldata customAttributes) external {
        //@audit-ok check arr length is the same
        uint256 winnersLength;
        uint32 claimIndex = 0;
        uint32 lowerBound = numRoundsClaimed[msg.sender];
        //@audit-ok go up to index: lowerBound + modelURIs.length => otherwise this may fail
        for (uint32 currentRound = lowerBound; currentRound < roundId; currentRound++) {
            numRoundsClaimed[msg.sender] += 1;
            winnersLength = winnerAddresses[currentRound].length;
            for (uint32 j = 0; j < winnersLength; j++) {
                if (msg.sender == winnerAddresses[currentRound][j]) {
                    //@audit-ok check index: customAttributes[claimIndex]
                    //console.log("eee: ", customAttributes.length);
                    _fighterFarmInstance.mintFromMergingPool(msg.sender, modelURIs[claimIndex], modelTypes[claimIndex], customAttributes[claimIndex]);
                    claimIndex += 1;
                }
            }
        }
        if (claimIndex > 0) {
            emit Claimed(msg.sender, claimIndex);
        }
    }

    /// @notice Gets the unclaimed rewards for a specific address.
    /// @param claimer The address of the claimer.
    /// @return numRewards The amount of unclaimed fighters.
    function getUnclaimedRewards(address claimer) external view returns (uint256) {
        uint256 winnersLength;
        uint256 numRewards = 0;
        uint32 lowerBound = numRoundsClaimed[claimer];
        for (uint32 currentRound = lowerBound; currentRound < roundId; currentRound++) {
            winnersLength = winnerAddresses[currentRound].length;
            for (uint32 j = 0; j < winnersLength; j++) {
                if (claimer == winnerAddresses[currentRound][j]) {
                    numRewards += 1;
                }
            }
        }
        return numRewards;
    }

    /*//////////////////////////////////////////////////////////////
                            PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Add merging pool points to a fighter.
    /// @dev Only the rankedBattle contract address can call this function.
    /// @param tokenId The ID of the fighter token.
    /// @param points The number of points to be added to the fighter.
    function addPoints(uint256 tokenId, uint256 points) public {
        require(msg.sender == _rankedBattleAddress, "Not Ranked Battle contract address");
        fighterPoints[tokenId] += points;
        totalPoints += points;
        //@audit-ok don't emit if points  =0
        emit PointsAdded(tokenId, points);
    }

    /// @notice Retrieves the points for multiple fighters up to the specified maximum token ID.
    /// @param maxId The maximum token ID up to which the points will be retrieved.
    /// @return An array of points corresponding to the fighters' token IDs.
    //@audit-ok add a view for a specific fighterId => otherwise I always have to retrieve all fighter points from 0 onwards
    function getFighterPoints(uint256 maxId) public view returns (uint256[] memory) {
        //@audit-ok : should be: new uint256[](maxId);
        uint256[] memory points = new uint256[](maxId);
        //uint256[] memory points = new uint256[](1);
        for (uint256 i = 0; i < maxId; i++) {
            points[i] = fighterPoints[i];
        }
        return points;
    }

    function getSingleFighterPoints(uint256 fighterId) public view returns (uint256) {
        return fighterPoints[fighterId];
    }
}
