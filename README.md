# Sushi Farmer Contracts.

Basically [yVaults](https://github.com/iearn-finance/vaults/blob/master/contracts/yVault.sol) that attempts to farm more UNIV2 SNX ETH LP tokens.

Deposit `UNIV2 SNX ETH LP` into the contract, and you get `Degen UNIV2 SNX ETH LP`.

TL;DR: Hold `Degen UNIV2 SNX ETH LP` if you're trying to accrue more `UNIV2 SNX ETH LP`.

- LPFarm [0xC9a6fbCb2541EcB37ed0D67C36d3E7B54A0a09cA](https://etherscan.io/address/0xC9a6fbCb2541EcB37ed0D67C36d3E7B54A0a09cA)
- DegenLPToken [0x594000baf94b5185054cf7ba809d9ec089e2e62e](https://etherscan.io/address/0x594000baf94b5185054cf7ba809d9ec089e2e62e)


#### Harvest

 Harvests the SUSHI profits from the UNIV2-SUSHI-ETH pool. Function caller gets 2.5% of the profits to compensate for GAS, dev gets 2.5% of the profits to compensate for GAS while deploying contracts.

```javascript
harvest()
```

#### Deposit

Converts normal `UNIV2 SNX ETH LP` into `Degen UNIV2 SNX ETH LP`.

```javascript
deposit(uint256 _amount)
```

```javascript
depositAll()
```

#### Withdraw

Converts your `Degen UNIV2 SNX ETH LP` (sushi that grazes) for normal `UNIV2 SNX ETH LP`.

```javascript
withdraw(uint256 _shares)
```

```javascript
withdrawAll()
```

#### Ratio between gSushi and Sushi (gSushi/SUSHI)

How much `UNIV2 SNX ETH LP` does 1 `Degen UNIV2 SNX ETH LP` yield?

i.e. 1 `Degen UNIV2 SNX ETH LP` = X `UNIV2 SNX ETH LP`

```javascript
getRatioPerShare()
```

## Testing

```bash
# Ether.js default Infura provider
export DAPP_TEST_BALANCE_CREATE=10000000000000000000000000
dapp test --rpc-url https://mainnet.infura.io/v3/84842078b09946638c03157f83405213
```
