pragma solidity >=0.5.0;

interface Hevm {
    function warp(uint256) external;
    function roll(uint256) external;
}
