# Sushi Farmer Contracts.

Basically [yVaults](https://github.com/iearn-finance/vaults/blob/master/contracts/yVault.sol) for sushi-swap's `$SUSHI`.

Deposit `$SUSHI` into the contract, and you get `gSushi`, a "grazing sushi" that will attempt to yield farm `$SUSHI`. Note that holding `gSushi` means that you're exposed to impermenant loss, as it provides liquidity to the ETH/SUSHI Univ2 pool behind the scenes to farm more `$SUSHI`.

TL;DR: Hold `gSUSHI` if you're **LONG** `$SUSHI`

## Functions

#### Harvest

Only callable every hour. Harvests the SUSHI profits from the UNIV2-SUSHI-ETH pool. Function caller gets 5% of the profits to compensate for GAS.
```javascript
harvest()
```

#### Deposit

Converts normal `$SUSHI` into `gSushi`. (Sushi that grazes).

```javascript
deposit(uint256 _amount)
```

```javascript
depositAll()
```

#### Withdraw

Converts your `gSushi` (sushi that grazes) for normal `SUSHI`.

```javascript
withdraw(uint256 _shares)
```

```javascript
withdrawAll()
```

#### Ratio between gSushi and Sushi (gSushi/SUSHI)

How much `$SUSHI` does 1 `gSUSHI` yield?

i.e. 1 gSUSHI = X SUSHI

```javascript
getGSushiOverSushiRatio()
```

## Testing

```bash
# Ether.js default Infura provider
export DAPP_TEST_BALANCE_CREATE=10000000000000000000000000
dapp test --rpc-url https://mainnet.infura.io/v3/84842078b09946638c03157f83405213
```