pragma solidity ^0.6.7;

import "ds-token/token.sol";

import "./interfaces/masterchef.sol";
import "./interfaces/uniswap.sol";

import "./safe-math.sol";
import "./constants.sol";

// Liquidity Provider Farming for SushiSwap
// Used to farm LP Tokens.

// Based off https://github.com/iearn-finance/vaults/blob/master/contracts/yVault.sol

contract LPFarm {
    using SafeMath for uint256;

    // Tokens
    DSToken public sushi = DSToken(Constants.SUSHI);
    DSToken public snx = DSToken(Constants.SNX);
    DSToken public weth = DSToken(Constants.WETH);
    DSToken public lpToken = DSToken(Constants.UNIV2_SNX_ETH);
    DSToken public degenLpToken;

    // Uniswap Router and Pair
    UniswapRouterV2 public univ2 = UniswapRouterV2(Constants.UNIV2_ROUTER2);
    UniswapPair public univ2Pair = UniswapPair(address(lpToken));

    // Masterchef Contract
    Masterchef public masterchef = Masterchef(Constants.MASTERCHEF);
    uint256 public poolId = 6;

    // 5% harvester rewards
    // 2.5% to dev
    // 2.5% to harvester
    uint256 public maxharvesterRewards = 5 ether;
    address public dev = 0xAbcCB8f0a3c206Bb0468C52CCc20f3b81077417B;


    constructor() public {
        degenLpToken = new DSToken("dUNI-V2");
        degenLpToken.setName("Degen UNI-V2");
    }

    // **** Harvest profits ****

    function harvestAndWithdrawAll() external {
        harvest();
        withdrawAll();
    }

    function harvest() public {
        // Get rewards
        masterchef.withdraw(poolId, 0);

        uint256 sushiBal = sushi.balanceOf(address(this));
        require(sushiBal > 0, "no-sushi");

        // Converts 1/2 to ETH, 1/2 to SNX
        // Add to liquidity pool
        uint256 _before = getLpTokenBalance();
        _convertSushiToLp(sushiBal);
        uint256 _after = getLpTokenBalance();

        uint256 _amount = _after.sub(_before);

        // Caller gets 2.5%, Dev gets 2.5%
        uint256 _rewards = _amount.mul(maxharvesterRewards).div(100 ether);
        lpToken.transfer(dev, _rewards.div(2));
        lpToken.transfer(msg.sender, _rewards.div(2));

        // Deposit to SNX/ETH pool
        _amount = lpToken.balanceOf(address(this));
        lpToken.approve(address(masterchef), _amount);
        masterchef.deposit(poolId, _amount);
    }

    function _convertSushiToLp(uint256 _amount) internal {
        // SUSHI -> WETH
        address[] memory wethPath = new address[](2);
        wethPath[0] = address(sushi);
        wethPath[1] = address(weth);
        sushi.approve(address(univ2), _amount);
        univ2.swapExactTokensForTokens(
            _amount,
            0,
            wethPath,
            address(this),
            now + 60
        );

        // 1/2 of WETH
        // WETH -> SNX
        uint256 wethHalf = weth.balanceOf(address(this)).div(2);
        address[] memory snxPath = new address[](2);
        snxPath[0] = address(weth);
        snxPath[1] = address(snx);
        weth.approve(address(univ2), wethHalf);
        univ2.swapExactTokensForTokens(
            wethHalf,
            0,
            snxPath,
            address(this),
            now + 60
        );

        // Add liquidity
        uint256 snxBal = snx.balanceOf(address(this));
        uint256 wethBal = weth.balanceOf(address(this));
        snx.approve(address(univ2), snxBal);
        weth.approve(address(univ2), wethBal);
        univ2.addLiquidity(
            address(snx),
            address(weth),
            snxBal,
            wethBal,
            0,
            0,
            address(this),
            now + 60
        );
    }

    // **** Withdraw / Deposit functions ****

    function withdrawAll() public {
        withdraw(degenLpToken.balanceOf(msg.sender));
    }

    function withdraw(uint256 _shares) public {
        // Calculate amount to withdraw
        uint256 _amount = getLpTokenBalance()
            .div(degenLpToken.totalSupply())
            .mul(_shares);

        degenLpToken.burn(msg.sender, _shares);

        // Withdraw tokens
        masterchef.withdraw(poolId, _amount);

        // Send back to user
        lpToken.transfer(msg.sender, _amount);
    }

    function depositAll() public {
        deposit(lpToken.balanceOf(msg.sender));
    }

    function deposit(uint256 _amount) public {
        uint256 _lpBal = getLpTokenBalance();
        uint256 _before = lpToken.balanceOf(address(this));
        lpToken.transferFrom(msg.sender, address(this), _amount);
        uint256 _after = lpToken.balanceOf(address(this));

        uint256 _obtained = _after.sub(_before);
        uint256 _shares = 0;
        uint256 _degenSupply = degenLpToken.totalSupply();

        if (_degenSupply == 0) {
            _shares = _obtained;
        } else {
            _shares = _obtained.mul(_degenSupply).div(_lpBal);
        }

        // Stake coins
        lpToken.approve(address(masterchef), _amount);
        masterchef.deposit(poolId, _obtained);

        degenLpToken.mint(msg.sender, _shares);
    }

    function getRatioPerShare() public view returns (uint256) {
        if (degenLpToken.totalSupply() == 0) {
            return 0;
        }
        
        return getLpTokenBalance().mul(1e18).div(degenLpToken.totalSupply());
    }

    function getLpTokenBalance() public view returns (uint256) {
        (uint256 stakedBal, ) = masterchef.userInfo(poolId, address(this));

        uint256 holdingBal = lpToken.balanceOf(address(this));

        return stakedBal.add(holdingBal);
    }
}
