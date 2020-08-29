pragma solidity ^0.6.7;

import "ds-token/token.sol";
import "ds-math/math.sol";
import "ds-test/test.sol";

import "../interfaces/hevm.sol";
import "../interfaces/weth.sol";

import "../constants.sol";
import "../g-sushi.sol";

contract GSushiTest is DSTest, DSMath {
    Hevm hevm;
    GSushi gSushi;
    UniswapRouterV2 univ2;

    DSToken sushi;
    WETH weth;

    function setUp() public payable {
        // Cheat address for time travelling
        // https://github.com/dapphub/dapptools/pull/71
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        univ2 = UniswapRouterV2(Constants.UNIV2_ROUTER2);
        gSushi = new GSushi();

        sushi = DSToken(Constants.SUSHI);
        weth = WETH(Constants.WETH);
    }

    function _getRequiredEthForExactSushi(uint256 _amount)
        internal
        view
        returns (uint256)
    {
        address[] memory path = new address[](2);
        path[0] = Constants.WETH;
        path[1] = Constants.SUSHI;

        uint256[] memory ins = univ2.getAmountsIn(_amount, path);

        return ins[0];
    }

    function _getWeth(uint256 amount) internal {
        weth.deposit{value: amount}();
    }

    function _getSushi(uint256 _amount) internal {
        address[] memory path = new address[](2);
        path[0] = Constants.WETH;
        path[1] = Constants.SUSHI;

        uint256 ethAmount = _getRequiredEthForExactSushi(_amount);
        uint256 ethBal = address(this).balance;
        assertTrue(ethBal >= ethAmount);

        univ2.swapETHForExactTokens{value: ethAmount}(
            _amount,
            path,
            address(this),
            now + 60
        );
    }

    function test_get_sushi() public {
        uint256 initialBal = sushi.balanceOf(address(this));
        _getSushi(100 ether);
        uint256 finalBal = sushi.balanceOf(address(this));
        assertTrue(finalBal > initialBal);
    }

    function test_gSushi_deposit() public {
        uint256 initialGSushiBal = gSushi.balanceOf(address(this));

        uint256 sushiBal = 100 ether;
        _getSushi(sushiBal);
        sushi.approve(address(gSushi), sushiBal);
        gSushi.deposit(sushiBal);

        uint256 finalGSushiBal = gSushi.balanceOf(address(this));

        assertTrue(finalGSushiBal > initialGSushiBal);
    }

    function test_gSushi_withdraw() public {
        uint256 sushiBal = 100 ether;

        _getSushi(sushiBal);
        sushi.approve(address(gSushi), sushiBal);
        gSushi.deposit(sushiBal);

        uint256 initialSushiBal = sushi.balanceOf(address(this));
        gSushi.withdrawAll();
        uint256 finalSushiBal = sushi.balanceOf(address(this));

        assertTrue(finalSushiBal > initialSushiBal);
    }

    function test_gSushi_harvester() public {
        // Additional LP tokens we wanna add to
        // the gSushi token. To make sure the ratio increases
        uint256 sushiToAdd = 1000 ether;
        _getSushi(sushiToAdd);
        uint256 wethToAdd = _getRequiredEthForExactSushi(sushiToAdd);
        _getWeth(wethToAdd);

        // Approves
        sushi.approve(address(gSushi), uint256(-1));
        weth.approve(address(gSushi), uint256(-1));

        // Deposit
        _getSushi(1 ether);
        gSushi.deposit(1 ether);

        // Send sushi + weth and then deposit again
        // This is so it converts the entire balance
        // into LP tokens
        sushi.transfer(address(gSushi), sushiToAdd);
        weth.transfer(address(gSushi), wethToAdd);
        gSushi.harvest();

        uint256 initialSushiBal = sushi.balanceOf(address(this));
        gSushi.withdrawAll();
        uint256 finalSushiBal = sushi.balanceOf(address(this));

        assertTrue(sub(finalSushiBal, initialSushiBal) > 999 ether);
    }

    function test_gSushi_get_ratio() public {
        uint256 initialRatio = gSushi.getGSushiOverSushiRatio();

        uint256 sushiBal = 100 ether;
        _getSushi(sushiBal);
        sushi.approve(address(gSushi), sushiBal);
        gSushi.deposit(sushiBal);

        uint256 finalRatio = gSushi.getGSushiOverSushiRatio();

        assertTrue(finalRatio > initialRatio);
    }

    function test_gSushi_get_ratio2() public {
        // Additional LP tokens we wanna add to
        // the gSushi token. To make sure the ratio increases
        uint256 sushiToAdd = 1000 ether;
        _getSushi(sushiToAdd);
        uint256 wethToAdd = _getRequiredEthForExactSushi(sushiToAdd);
        _getWeth(wethToAdd);

        // Approves
        sushi.approve(address(gSushi), uint256(-1));
        weth.approve(address(gSushi), uint256(-1));

        // Deposit
        _getSushi(1 ether);
        gSushi.deposit(1 ether);

        uint256 initialRatio = gSushi.getGSushiOverSushiRatio();

        // Send sushi + weth and then deposit again
        // This is so it converts the entire balance
        // into LP tokens
        sushi.transfer(address(gSushi), sushiToAdd);
        weth.transfer(address(gSushi), wethToAdd);
        gSushi.harvest();

        uint256 finalRatio = gSushi.getGSushiOverSushiRatio();

        // Has at accurred ~1000x premium
        assertTrue(finalRatio > initialRatio * 990);
    }

    function test_gSushi_get_ratio3() public {
        // Approves
        sushi.approve(address(gSushi), uint256(-1));
        weth.approve(address(gSushi), uint256(-1));

        // Deposit
        _getSushi(100 ether);
        gSushi.deposit(100 ether);

        uint256 initialRatio = gSushi.getGSushiOverSushiRatio();
        uint256 gSushiBal = gSushi.balanceOf(address(this));
        uint256 expectedSushiBal = mul(gSushiBal, initialRatio) / 1e18;

        // Withdraw
        gSushi.withdrawAll();
        uint256 sushiBal = sushi.balanceOf(address(this));

        // Roughly equals
        uint256 delta = sub(
            max(sushiBal, expectedSushiBal),
            min(sushiBal, expectedSushiBal)
        );
        assertTrue(delta < 1e18);
    }

    function test_gSushi_harvest() public {
        // Approves
        sushi.approve(address(gSushi), uint256(-1));
        weth.approve(address(gSushi), uint256(-1));

        // Deposit
        _getSushi(100 ether);
        gSushi.deposit(100 ether);
        gSushi.harvest();

        // Shouldn't be able to harvest
        try gSushi.harvest()  {
            log_named_string("gSushi.harvest", "harvest-should-fail");
            assertTrue(false);
        } catch (bytes memory) {}

        // Warp
        hevm.warp(gSushi.lastHarvest() + 1 hours + 1 minutes);
        gSushi.harvest();
    }

    function test_gSushi_multiple_deposits_withdraw() public {
        // Approves
        sushi.approve(address(gSushi), uint256(-1));

        // Deposit
        _getSushi(10 ether);
        gSushi.deposit(1 ether);
        gSushi.deposit(1 ether);
        gSushi.deposit(1 ether);
        gSushi.deposit(1 ether);

        uint256 gSushibal = gSushi.balanceOf(address(this));
        gSushi.withdraw(gSushibal / 4);
        gSushi.withdraw(gSushibal / 4);
        gSushi.withdraw(gSushibal / 4);
    }
}
