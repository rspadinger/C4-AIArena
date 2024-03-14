
# M01 - RankedBattle::updateBattleRecord can be called several times for the same round and tokenId 

## Risk: Medium

## Issue Type:

## Title: RankedBattle::updateBattleRecord can be called several times for the same round and tokenId 

## Links: https://github.com/code-423n4/2024-02-ai-arena/blob/cd1a0e6d1b40168657d1aaee8223dc050e15f8cc/src/RankedBattle.sol#L322

## Impact

The updateBattleRecord in the RankedBattle contract can potentially be called several times by the game server for the same round and tokenId, which would falsify the amount of points and NRN tokens distributed to the corresponding fighter NFT.


## Proof of Concept

Add the following test to the RankedBattle.t.sol file:

```
function testCallingUpdateBattleRecordSeveralTimesShouldFail() public {
    address player = vm.addr(3);
    _mintFromMergingPool(player);
    _fundUserWith4kNeuronByTreasury(player);
    vm.prank(player);
    _rankedBattleContract.stakeNRN(3_000 * 10 ** 18, 0);

    vm.startPrank(address(_GAME_SERVER_ADDRESS));
    _rankedBattleContract.updateBattleRecord(0, 50, 0, 1500, true);

    //by accident, the updateBattleRecord() function is called a second time
    _rankedBattleContract.updateBattleRecord(0, 50, 0, 1500, true);
    vm.stopPrank();

    _rankedBattleContract.setNewRound();

    //40500 points should have been distributed, however, because the updateBattleRecord() function
    //was called twice by accident, 81000 points have been distributed to the player
    emit log_uint(_rankedBattleContract.accumulatedPointsPerAddress(player, 0));

    assertEq(_rankedBattleContract.accumulatedPointsPerAddress(player, 0), 40500); //this fails!
}
```

According to the values provided for the updateBattleRecord() function, the player should only get 40500 points. However, because the updateBattleRecord() function was called twice for the same round and tokenId by the game server, the player received 81000 points. 


## Tools Used

Manual Review

## Recommended Mitigation Steps

Add the following mapping to the RankedBattle contract:

```
/// @notice Indicates whether we have already called the updateBattleRecord function for a given round and token.
mapping(uint256 => mapping(uint256 => bool)) public updateBattleRecordAlreadyCalled;
```



Add the following verification on top of the updateBattleRecord() function:

```
require(!updateBattleRecordAlreadyCalled[roundId][tokenId], "update already called for the current round and the specified fighter");
```


# M02 - StakeAtRisk::_sweepLostStake : Stuck NRN can't be recovered from the contract

## Risk: Medium

## Issue Type:

## Title: StakeAtRisk::_sweepLostStake : Stuck NRN can't be recovered from the contract 

## Links: https://github.com/code-423n4/2024-02-ai-arena/blob/cd1a0e6d1b40168657d1aaee8223dc050e15f8cc/src/StakeAtRisk.sol#L143


## Impact

At the end of each round, the RankedBattle contract calls the setNewRound() function on the StakeAtRisk contract, which calls the _sweepLostStake() function in order to transfer the lost stake to the treasury contract.

However, only the amount: totalStakeAtRisk[roundId] can be transferred from the StakeAtRisk contract to the treasury. Any other funds remain stuck in the contract and can't be recovered.

Additional NRN tokens can accumulate in the StakeAtRisk contract if NRNs are transferred to the contract by accident by a user or by any protocol contract. 

Instead of transferring the amount: totalStakeAtRisk[roundId], it would be better to specify the total NRN balane contained in the contract (_neuronInstance.balanceOf(address(this) to make sure the entire NRN balance of the contract is transferred to the treasury at the end of each round.


## Proof of Concept

Add the following test to the SstakeAtRisk.t.sol file:

```
function testNRNStuckInStakeAtRiskContract() public {
    //NRN is sent to StakeAtRisk contract by accident, either by a user or another protocol contract
    vm.prank(_treasuryAddress);
    _neuronContract.transfer(address(_stakeAtRiskContract), 1_000 * 10 ** 18);

    address player = vm.addr(3);
    uint256 stakeAmount = 3_000 * 10 ** 18;
    uint256 expectedStakeAtRiskAmount = (stakeAmount * 100) / 100000;
    _mintFromMergingPool(player);
    _fundUserWith4kNeuronByTreasury(player);

    vm.prank(player);
    _rankedBattleContract.stakeNRN(stakeAmount, 0);

    vm.prank(address(_GAME_SERVER_ADDRESS));
    _rankedBattleContract.updateBattleRecord(0, 50, 2, 1500, true); //loses battle => 3 NRN staked at risk

    //1003 NRN tokens are in the contract
    console.log("NRN in StakeAtRiskContract: ", _neuronContract.balanceOf(address(_stakeAtRiskContract)));

    vm.prank(address(_rankedBattleContract));

    //the player lost the battle, 3 NRN were staked at risk in te StakeAtRisk contract
    //at the end of the round, the RankedBattle contract calls setNewRound, which calls the _sweepLostStake function
    //and transfers the amount that was staked at risk to the treasury
    //however, any other funds remain stuck in the contract and can't be recovered
    _stakeAtRiskContract.setNewRound(1);

    //1000 NRN tokens remain stuck in the contract and cant be recovered
    console.log("NRN stuck in StakeAtRiskContract: ", _neuronContract.balanceOf(address(_stakeAtRiskContract)));
}
```


## Tools Used
Manual Review


## Recommended Mitigation Steps

Make the following modification in the _sweepLostStake() function:

```
- return _neuronInstance.transfer(treasuryAddress, totalStakeAtRisk[roundId]);
+ return _neuronInstance.transfer(treasuryAddress, totalStakeAtRisk[roundId]);
```

Or, add a withraw() function to the contract that allows the admin to recover any stuck funds.


# M03 - FighterFarm::updateModel : A player can retrieve modelHash and modelType from most successful fighter NFT and use them for their own fighter NFT

## Risk: Medium

## Issue Type:

## Title: FighterFarm::updateModel : A player can retrieve modelHash and modelType from most successful fighter NFT and use them for their own fighter NFT  

## Links: https://github.com/code-423n4/2024-02-ai-arena/blob/cd1a0e6d1b40168657d1aaee8223dc050e15f8cc/src/FighterFarm.sol#L283


## Impact

The modelHash and modelType parameters refer to the off-chain fighter data that determine the skill/strength... of the fighter. Any player could recover the modelHash and modelType (stored on-chain for all fighter NFTs) of the most successful fighter and update their own fighter NFT with those values by calling the updateModel() function with those 2 parameters and therefore gain an advantage over other players. 


## Tools Used

Manual Review


## Recommended Mitigation Steps

The modelHash that corresponds with the off-chain model data should only be available for the owner of the model data and needs to be locked for all other players.

Only the owner of a specific fighter has access to the corresponding model data. The off-chain game server needs to create the corresponding modelHash whenever a player either creates a new fighter or updates/trains an existing fighter. The corresponding hash than needs to be updated by the game server on the FighterFarm contract for that specific fighterId 

Add the following state variable to the FighterFarm contract:

```
/// @notice Mapping to keep track of the modelHash for a specific fighterId.
mapping(uint256 => string) public fighterHash;
```

Add the following setter function to the contract that can only be called by the game server:
 
```
function setModelHashForTokenId(uint256 tokenId, string calldata modelHash) external {
    require(msg.sender == _gameServerAddress);
    fighterHash[tokenId] = modelHash;
}
```

In the updateModel() function, add the following require statement at the top of the function:

```
require(keccak256(abi.encodePacked(fighterHash[tokenId])) == keccak256(abi.encodePacked(modelHash)), "modelHash not matching");
```


# M04 - MergingPool::claimRewards : User can provide whatever model data and customAttributes he wants for the reward NFTs

## Risk: Medium

## Issue Type:

## Title: MergingPool::claimRewards : User can provide whatever model data and customAttributes he wants for the reward NFTs  

## Links: https://github.com/code-423n4/2024-02-ai-arena/blob/cd1a0e6d1b40168657d1aaee8223dc050e15f8cc/src/MergingPool.sol#L139


## Impact

The model data and customAttributes for the reward NFTs should be provided by the game server and the user should not be able to modify those attributes. Currently, a winning user can provide whatever data he wants for the NFTs.


## Tools Used

Manual Review


## Recommended Mitigation Steps

The off-chain game server should provide the attributes for the winning NFTs together with a sinature that must be validated in the claimRewards() function.  

Modify the claimRewards() function:

```
- function claimRewards(string[] calldata modelURIs, string[] calldata modelTypes, uint256[2][] calldata customAttributes) external {
+ function claimRewards(bytes[] calldata signatures, string[] calldata modelURIs, string[] calldata modelTypes, uint256[2][] calldata customAttributes) external {
```

In the second for-loop of the claimRewards() function, after the verification (if (msg.sender == ...) add the following code:

```
bytes32 msgHash = bytes32(keccak256(abi.encode(msg.sender, modelURIs[i], modelTypes[i], customAttributes[i])));          
require(Verification.verify(msgHash, signatures[i], _delegatedAddress));
```

