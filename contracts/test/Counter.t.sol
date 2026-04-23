// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Counter} from "../src/Counter.sol";

contract CounterTest is Test {
    Counter internal counter;

    function setUp() public {
        counter = new Counter();
    }

    function test_InitialNumberIsZero() public view {
        assertEq(counter.number(), 0);
    }

    function test_IncrementAddsOne() public {
        counter.increment();

        assertEq(counter.number(), 1);
    }

    function test_SetNumberUpdatesState() public {
        counter.setNumber(7);

        assertEq(counter.number(), 7);
    }
}
