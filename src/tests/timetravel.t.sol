pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "../interfaces/hevm.sol";

contract TimeTravel is DSTest {
    Hevm hevm;

    function setUp() public {
        // Cheat address
        // https://github.com/dapphub/dapptools/pull/71
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    }

    function test_basic_sanity() public {
        uint256 lastTime = now;
        bool isWarped = now > lastTime;
        assertTrue(!isWarped);
    }

    function test_can_time_travel() public {
        uint256 lastTime = now;

        hevm.warp(lastTime + 500);

        bool isWarped = now > lastTime;

        assertTrue(isWarped);
    }
}
