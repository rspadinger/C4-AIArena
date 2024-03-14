// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import {Neuron} from "./Neuron.sol";
import {RankedBattle} from "./RankedBattle.sol";

/// @title StakeAtRisk
/// @author ArenaX Labs Inc.
/// @notice Manages the NRNs that are at risk of being lost during a round of competition
contract StakeAtRisk {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Event emitted when NRNs are reclaimed from this contract (after a win in ranked).
    event ReclaimedStake(uint256 fighterId, uint256 reclaimAmount);

    /// @notice Event emitted when more NRNs are placed at risk.
    event IncreasedStakeAtRisk(uint256 fighterId, uint256 atRiskAmount);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The current roundId.
    //@audit-ok we also have this in MergingPool & RankedBattle => there should only be 1 source - eg: RankedBattle => this is only modified by RankedBattle
    uint256 public roundId = 0;

    /// @notice The treasury address.
    address public treasuryAddress;

    /// @notice The RankedBattle contract address.
    address _rankedBattleAddress;

    /// @notice The Neuron contract instance.
    Neuron _neuronInstance;

    /*//////////////////////////////////////////////////////////////
                                MAPPINGS
    //////////////////////////////////////////////////////////////*/

    /// @notice Maps the roundId to the total stake at risk for that round.
    mapping(uint256 => uint256) public totalStakeAtRisk;

    /// @notice Maps the roundId to the fighterId to the stake at risk for that fighter.
    mapping(uint256 => mapping(uint256 => uint256)) public stakeAtRisk;

    /// @notice Mapping of address to the amount of NRNs that have been swept.
    mapping(address => uint256) public amountLost;

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the community treasury address and ranked battle contract address.
    /// Instantiates the Neuron contract.
    /// @param treasuryAddress_ The address of the treasury contract
    /// @param nrnAddress The address of the Neuron contract
    /// @param rankedBattleAddress The address of the Ranked Battle contract
    constructor(address treasuryAddress_, address nrnAddress, address rankedBattleAddress) {
        treasuryAddress = treasuryAddress_;
        _rankedBattleAddress = rankedBattleAddress;
        _neuronInstance = Neuron(nrnAddress);
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets a new round for staking
    /// @dev This function can only be called by the RankedBattle contract to set a new round for staking.
    /// @dev At the end of a round, it sweeps all NRNs held in this contract and sends it to treasury.
    /// @param roundId_ The ID of the new round.
    function setNewRound(uint256 roundId_) external {
        require(msg.sender == _rankedBattleAddress, "Not authorized to set new round");
        //@audit-ok RB::setNewRound (set: roundId & rankedNrnDistribution) => SAR::setNewRound (set roundId & sweep) :: if _sweepLostStake fails, roundId stays the same
        //check is not required => _sweepLostStake either returns true or reverts => it never returns false
        bool success = _sweepLostStake();
        if (success) {
            roundId = roundId_;
        }
    }

    /// @notice Reclaims NRN tokens from the stake at risk.
    /// @dev This function can only be called by the RankedBattle contract to reclaim
    /// NRN tokens from the stake at risk.
    /// @dev This gets triggered when they win a match while having NRNs at risk.
    /// @param nrnToReclaim The amount of NRN tokens to reclaim.
    /// @param fighterId The ID of the fighter.
    /// @param fighterOwner The owner of the fighter.
    function reclaimNRN(uint256 nrnToReclaim, uint256 fighterId, address fighterOwner) external {
        require(msg.sender == _rankedBattleAddress, "Call must be from RankedBattle contract");
        //require(stakeAtRisk[roundId][fighterId] >= nrnToReclaim, "Fighter does not have enough stake at risk");

        //@audit-ok find case where nrnToReclaim > neuron.balanceOf(this)
        //@audit-ok this could fail => but RB assumes this worked & sets SVs accordingly => require success :: note transfer either reverts or returns true
        bool success = _neuronInstance.transfer(_rankedBattleAddress, nrnToReclaim);
        //success check is not really required, because if not successful, transfer reverts
        if (success) {
            //@audit-ok could any of this underflow
            stakeAtRisk[roundId][fighterId] -= nrnToReclaim;
            totalStakeAtRisk[roundId] -= nrnToReclaim;
            amountLost[fighterOwner] -= nrnToReclaim; //???
            emit ReclaimedStake(fighterId, nrnToReclaim);
        }
    }

    /// @notice Updates the stake at risk records for a fighter.
    /// @dev This function can only be called by the RankedBattle contract to update the stake at
    /// risk records for a fighter.
    /// @dev This gets triggered when the fighter has 0 points and loses (i.e. goes into deficit).
    /// @param nrnToPlaceAtRisk The amount of NRN tokens to place at risk.
    /// @param fighterId The ID of the fighter.
    function updateAtRiskRecords(uint256 nrnToPlaceAtRisk, uint256 fighterId, address fighterOwner) external {
        require(msg.sender == _rankedBattleAddress, "Call must be from RankedBattle contract");
        stakeAtRisk[roundId][fighterId] += nrnToPlaceAtRisk;
        totalStakeAtRisk[roundId] += nrnToPlaceAtRisk;
        amountLost[fighterOwner] += nrnToPlaceAtRisk;
        emit IncreasedStakeAtRisk(fighterId, nrnToPlaceAtRisk);
    }

    /// @notice Gets the stake at risk for a specific fighter in the current round.
    /// @param fighterId The ID of the fighter.
    /// @return Amount of NRN tokens at risk for the fighter in the current round.
    function getStakeAtRisk(uint256 fighterId) external view returns (uint256) {
        return stakeAtRisk[roundId][fighterId];
    }

    /*//////////////////////////////////////////////////////////////
                            PRIVATE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sweeps the lost stake to the treasury contract.
    /// @dev This function is called internally to transfer the lost stake to the treasury contract.
    function _sweepLostStake() private returns (bool) {
        //@audit-ok could we find cases where totalStakeAtRisk[roundId] > neuron.balanceOf(this) => send entire balance
        // totalStakeAtRisk[roundId] <  neuron.balanceOf(this) IF ???
        //@audit-ok approve ?
        //return _neuronInstance.transfer(address(0), totalStakeAtRisk[roundId]);
        //return _neuronInstance.transfer(treasuryAddress, totalStakeAtRisk[roundId]);
        //return _neuronInstance.transfer(treasuryAddress, _neuronInstance.balanceOf(address(this)));
    }
}
