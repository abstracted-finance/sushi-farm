pragma solidity ^0.6.7;

import "ds-math/math.sol";
import "ds-token/token.sol";

import "./interfaces/masterchef.sol";
import "./interfaces/uniswap.sol";

import "./constants.sol";

// Sushi Farm in SushiSwap
// Used to farm sushi. i.e. Deposit into this pool if you want to LONG sushi.

// Based off https://github.com/iearn-finance/vaults/blob/master/contracts/yVault.sol
contract SushiFarm is DSMath {
    // Tokens
    DSToken public sushi = DSToken(Constants.SUSHI);
    DSToken public univ2SushiEth = DSToken(Constants.UNIV2_SUSHI_ETH);
    DSToken public weth = DSToken(Constants.WETH);
    DSToken public gSushi;

    // Uniswap Router and Pair
    UniswapRouterV2 public univ2 = UniswapRouterV2(Constants.UNIV2_ROUTER2);
    UniswapPair public univ2Pair = UniswapPair(address(univ2SushiEth));

    // Masterchef Contract
    Masterchef public masterchef = Masterchef(Constants.MASTERCHEF);
    uint256 public univ2SushiEthPoolId = 12;

    // 5% reward for anyone who calls HARVEST
    uint256 public callerRewards = 5 ether / 100;

    // Last harvest
    uint256 public lastHarvest = 0;

    constructor() public {
        gSushi = new DSToken("gSushi");
        gSushi.setName("Grazing Sushi");
    }

    // **** Harvest profits ****

    function harvest() public {
        // Only callable every hour or so
        if (lastHarvest > 0) {
            require(lastHarvest + 1 hours <= block.timestamp, "!harvest-time");
        }
        lastHarvest = block.timestamp;

        // Withdraw sushi
        masterchef.withdraw(univ2SushiEthPoolId, 0);

        uint256 amount = sushi.balanceOf(address(this));
        uint256 reward = div(mul(amount, callerRewards), 100 ether);

        // Sends 5% fee to caller
        sushi.transfer(msg.sender, reward);

        // Remove amount from rewards
        amount = sub(amount, reward);

        // Add to UniV2 pool
        _sushiToUniV2SushiEth(amount);

        // Deposit into masterchef contract
        uint256 balance = univ2SushiEth.balanceOf(address(this));
        univ2SushiEth.approve(address(masterchef), balance);
        masterchef.deposit(univ2SushiEthPoolId, balance);
    }

    // **** Withdraw / Deposit functions ****

    function withdrawAll() external {
        withdraw(gSushi.balanceOf(msg.sender));
    }

    function withdraw(uint256 _shares) public {
        uint256 univ2Balance = univ2SushiEthBalance();

        uint256 amount = div(mul(_shares, univ2Balance), gSushi.totalSupply());
        gSushi.burn(msg.sender, _shares);

        // Withdraw from Masterchef contract
        masterchef.withdraw(univ2SushiEthPoolId, amount);

        // Retrive shares from Uniswap pool and converts to SUSHI
        uint256 _before = sushi.balanceOf(address(this));
        _uniV2SushiEthToSushi(amount);
        uint256 _after = sushi.balanceOf(address(this));

        // Transfer back SUSHI difference
        sushi.transfer(msg.sender, sub(_after, _before));
    }

    function depositAll() external {
        deposit(sushi.balanceOf(msg.sender));
    }

    function deposit(uint256 _amount) public {
        sushi.transferFrom(msg.sender, address(this), _amount);

        uint256 _pool = univ2SushiEthBalance();
        uint256 _before = univ2SushiEth.balanceOf(address(this));
        _sushiToUniV2SushiEth(_amount);
        uint256 _after = univ2SushiEth.balanceOf(address(this));

        _amount = sub(_after, _before); // Additional check for deflationary tokens

        uint256 shares = 0;
        if (gSushi.totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = div(mul(_amount, gSushi.totalSupply()), _pool);
        }

        // Deposit into Masterchef contract to get rewards
        univ2SushiEth.approve(address(masterchef), _amount);
        masterchef.deposit(univ2SushiEthPoolId, _amount);

        gSushi.mint(msg.sender, shares);
    }

    // Takes <x> amount of SUSHI
    // Converts half of it into ETH,
    // Supplies them into SUSHI/ETH pool
    function _sushiToUniV2SushiEth(uint256 _amount) internal {
        uint256 half = div(_amount, 2);

        // Convert half of the sushi to ETH
        address[] memory path = new address[](2);
        path[0] = address(sushi);
        path[1] = address(weth);
        sushi.approve(address(univ2), half);
        univ2.swapExactTokensForTokens(half, 0, path, address(this), now + 60);

        // Supply liquidity
        uint256 wethBal = weth.balanceOf(address(this));
        uint256 sushiBal = sushi.balanceOf(address(this));
        sushi.approve(address(univ2), sushiBal);
        weth.approve(address(univ2), wethBal);
        univ2.addLiquidity(
            address(sushi),
            address(weth),
            sushiBal,
            wethBal,
            0,
            0,
            address(this),
            now + 60
        );
    }

    // Takes <x> amount of gSushi
    // And removes liquidity from SUSHI/ETH pool
    // Converts the ETH into Sushi
    function _uniV2SushiEthToSushi(uint256 _amount) internal {
        // Remove liquidity
        require(
            univ2SushiEth.balanceOf(address(this)) >= _amount,
            "not-enough-liquidity"
        );
        univ2SushiEth.approve(address(univ2), _amount);
        univ2.removeLiquidity(
            address(sushi),
            address(weth),
            _amount,
            0,
            0,
            address(this),
            now + 60
        );

        // Convert ETH to SUSHI
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(sushi);
        uint256 wethBal = weth.balanceOf(address(this));
        weth.approve(address(univ2), wethBal);
        univ2.swapExactTokensForTokens(
            wethBal,
            0,
            path,
            address(this),
            now + 60
        );
    }

    // 1 gSUSHI = <x> SUSHI
    function getGSushiOverSushiRatio() public view returns (uint256) {
        // How much UniV2 do we have
        uint256 uniV2Balance = univ2SushiEthBalance();

        if (uniV2Balance == 0) {
            return 0;
        }

        // How many SUSHI and ETH can we get for this?
        (uint112 _poolSushiReserve, uint112 _poolWETHReserve, ) = univ2Pair
            .getReserves(); // SUSHI and WETH in pool
        uint256 uniV2liquidity = univ2SushiEth.totalSupply(); // Univ2 total supply
        uint256 uniV2percentage = div(mul(uniV2Balance, 1e18), uniV2liquidity); // How much we own %-wise

        uint256 removableSushi = uint256(
            div(mul(_poolSushiReserve, uniV2percentage), 1e18)
        );
        uint256 removableWeth = uint256(
            div(mul(_poolWETHReserve, uniV2percentage), 1e18)
        );

        // How many SUSHI can we get for the ETH?
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(sushi);
        uint256[] memory outs = univ2.getAmountsOut(removableWeth, path);

        // Get RATIO
        return div(mul(add(outs[1], removableSushi), 1e18), gSushi.totalSupply());
    }

    function univ2SushiEthBalance() public view returns (uint256) {
        (uint256 univ2Balance, ) = masterchef.userInfo(
            univ2SushiEthPoolId,
            address(this)
        );

        return univ2Balance;
    }

    // **** Internal functions ****
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "division by zero");
        uint256 c = a / b;
        return c;
    }
}
