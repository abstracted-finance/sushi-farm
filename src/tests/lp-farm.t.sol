pragma solidity ^0.6.7;

import "ds-token/token.sol";
import "ds-test/test.sol";
import "ds-auth/auth.sol";

import "../safe-math.sol";

import "../interfaces/masterchef.sol";
import "../interfaces/hevm.sol";
import "../interfaces/weth.sol";

import "../constants.sol";
import "../lp-farm.sol";

contract LPFarmTest is DSTest {
    using SafeMath for uint256;

    Hevm hevm;
    LPFarm lpFarm;
    UniswapRouterV2 univ2;
    Masterchef masterchef;

    DSToken degenLpToken;
    DSToken lpToken;
    DSToken sushi;
    DSToken snx;
    WETH weth;

    function setUp() public payable {
        // Cheat address for time travelling
        // https://github.com/dapphub/dapptools/pull/71
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        univ2 = UniswapRouterV2(Constants.UNIV2_ROUTER2);

        lpFarm = new LPFarm();
        degenLpToken = lpFarm.degenLpToken();
        masterchef = lpFarm.masterchef();

        snx = DSToken(Constants.SNX);
        weth = WETH(Constants.WETH);
        sushi = DSToken(Constants.SUSHI);
        lpToken = DSToken(Constants.UNIV2_SNX_ETH);
    }

    // **** Helper functions **** //

    function _getRequiredEthForExactToken(address _token, uint256 _amount)
        internal
        view
        returns (uint256)
    {
        address[] memory path = new address[](2);
        path[0] = Constants.WETH;
        path[1] = _token;

        uint256[] memory ins = univ2.getAmountsIn(_amount, path);

        return ins[0];
    }

    function _supplyToLp(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1
    ) internal returns (uint256) {
        DSToken(token0).approve(address(univ2), amount0);
        DSToken(token1).approve(address(univ2), amount1);

        (, , uint256 liquidity) = univ2.addLiquidity(
            token0,
            token1,
            amount0,
            amount1,
            0,
            0,
            address(this),
            now + 60
        );

        return liquidity;
    }

    function _ethToWeth(uint256 amount) internal {
        weth.deposit{value: amount}();
    }

    function _ethToExactToken(address _token, uint256 _amount) internal {
        address[] memory path = new address[](2);
        path[0] = Constants.WETH;
        path[1] = _token;

        uint256 ethAmount = _getRequiredEthForExactToken(_token, _amount);
        uint256 ethBal = address(this).balance;
        assertTrue(ethBal >= ethAmount);

        univ2.swapETHForExactTokens{value: ethAmount}(
            _amount,
            path,
            address(this),
            now + 60
        );
    }

    function _getSnxEthLpToken(uint256 amount0, uint256 amount1)
        internal
        returns (uint256)
    {
        _ethToExactToken(address(snx), amount0);
        _ethToWeth(amount1);

        // Ratio ~1 ETH = 59 SNX as of 2020/09/01
        return _supplyToLp(address(weth), address(snx), amount0, amount1);
    }

    // **** Tests **** //

    function test_get_snx() public {
        uint256 _before = snx.balanceOf(address(this));
        _ethToExactToken(address(snx), 10 ether);
        uint256 _after = snx.balanceOf(address(this));
        assertTrue(_after.sub(_before) == 10 ether);
    }

    function test_weth() public {
        uint256 _before = weth.balanceOf(address(this));
        _ethToWeth(10 ether);
        uint256 _after = weth.balanceOf(address(this));
        assertTrue(_after.sub(_before) == 10 ether);
    }

    function test_get_lpToken() public {
        // Ratio ~1 ETH = 59 SNX as of 2020/09/01
        uint256 _before = lpToken.balanceOf(address(this));
        uint256 liquidity = _getSnxEthLpToken(59 ether, 1 ether);
        uint256 _after = lpToken.balanceOf(address(this));
        assertTrue(_after.sub(_before) == liquidity);
        assertTrue(_after > _before);
    }

    function test_deposit() public {
        uint256 liquidity = _getSnxEthLpToken(59 ether, 1 ether);

        uint256 _before = degenLpToken.balanceOf(address(this));
        lpToken.approve(address(lpFarm), liquidity);
        lpFarm.deposit(liquidity);
        uint256 _after = degenLpToken.balanceOf(address(this));

        assertTrue(_after > _before);
    }

    function test_withdraw() public {
        uint256 liquidity = _getSnxEthLpToken(59 ether, 1 ether);
        lpToken.approve(address(lpFarm), liquidity);
        lpFarm.deposit(liquidity);

        uint256 _before = lpToken.balanceOf(address(this));
        degenLpToken.approve(address(lpFarm), uint256(-1));
        lpFarm.withdrawAll();
        uint256 _after = lpToken.balanceOf(address(this));

        assertTrue(_after > _before);
    }

    function test_multi_deposit_withdraw() public {
        uint256 liquidity = _getSnxEthLpToken(59 ether, 1 ether);
        lpToken.approve(address(lpFarm), liquidity);

        lpFarm.deposit(liquidity.div(4));
        lpFarm.deposit(liquidity.div(4));
        lpFarm.deposit(liquidity.div(4));
        lpFarm.deposit(liquidity.div(4));

        uint256 bal = degenLpToken.balanceOf(address(this));
        degenLpToken.approve(address(lpFarm), uint256(-1));
        lpFarm.withdraw(bal.div(4));
        lpFarm.withdraw(bal.div(4));
        lpFarm.withdraw(bal.div(4));
        lpFarm.withdraw(bal.div(4));
    }

    function test_harvest1() public {
        uint256 liquidity = _getSnxEthLpToken(59 ether, 1 ether);
        lpToken.approve(address(lpFarm), liquidity);
        lpFarm.deposit(liquidity);

        // Mimics block rewards
        _ethToExactToken(Constants.SUSHI, 100 ether);
        sushi.transfer(address(lpFarm), 100 ether);

        uint256 _before = lpToken.balanceOf(address(this));
        uint256 _beforeDev = lpToken.balanceOf(lpFarm.dev());
        lpFarm.harvest();
        uint256 _after = lpToken.balanceOf(address(this));
        uint256 _afterDev = lpToken.balanceOf(lpFarm.dev());
        assertTrue(_after > _before);
        assertTrue(_afterDev > _beforeDev);
    }

    function test_harvest2() public {
        uint256 liquidity = _getSnxEthLpToken(59 ether, 1 ether);
        lpToken.approve(address(lpFarm), liquidity);
        lpFarm.deposit(liquidity);

        // Mimics block rewards
        _ethToExactToken(Constants.SUSHI, 100 ether);
        sushi.transfer(address(lpFarm), 100 ether);

        uint256 _before = lpToken.balanceOf(address(this));
        degenLpToken.approve(address(lpFarm), uint256(-1));
        lpFarm.harvestAndWithdrawAll();
        uint256 _after = lpToken.balanceOf(lpFarm.dev());

        assertTrue(_after.sub(_before) > liquidity);
        assertTrue(degenLpToken.totalSupply() == 0);
    }

    function test_harvest3() public {
        uint256 liquidity = _getSnxEthLpToken(59 ether, 1 ether);
        lpToken.approve(address(lpFarm), liquidity);
        lpFarm.deposit(liquidity);

        // Gets current contract balance
        uint256 _before = lpFarm.getLpTokenBalance();
        uint256 _beforeDev = lpToken.balanceOf(lpFarm.dev());
        uint256 _beforeHarvester = lpToken.balanceOf(address(this));

        // Mimics block rewards
        _ethToExactToken(Constants.SUSHI, 100 ether);
        sushi.transfer(address(lpFarm), 100 ether);
        lpFarm.harvest();

        uint256 _after = lpFarm.getLpTokenBalance();
        uint256 _afterDev = lpToken.balanceOf(lpFarm.dev());
        uint256 _afterHarvester = lpToken.balanceOf(lpFarm.dev());

        // Same profits
        assertTrue(
            _afterHarvester.sub(_beforeHarvester) == _afterDev.sub(_beforeDev)
        );

        // Pool profit is 95%
        uint256 _poolProfit = _after.sub(_before);

        // Get full profit
        uint256 _fullProfit = _poolProfit.mul(100 ether).div(95 ether);

        // Delta
        uint256 _delta = _afterHarvester.sub(_beforeHarvester);
        assertTrue(_fullProfit == _delta.mul(2).add(_poolProfit));
    }

    function test_ratio1() public {
        uint256 liquidity = _getSnxEthLpToken(59 ether, 1 ether);
        lpToken.approve(address(lpFarm), liquidity);
        lpFarm.deposit(liquidity);

        // Mimics block rewards
        _ethToExactToken(Constants.SUSHI, 100 ether);
        sushi.transfer(address(lpFarm), 100 ether);

        uint256 _before = lpFarm.getRatioPerShare();
        lpFarm.harvest();
        uint256 _after = lpFarm.getRatioPerShare();
        assertTrue(_after > _before);
    }

    function test_ratio2() public {
        uint256 _before = lpFarm.getRatioPerShare();

        uint256 liquidity = _getSnxEthLpToken(59 ether, 1 ether);
        lpToken.approve(address(lpFarm), liquidity);
        lpFarm.deposit(liquidity);

        uint256 _after = lpFarm.getRatioPerShare();

        assertTrue(_after > _before);
    }
}
