// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SuperfluidTester} from "./SuperfluidTester.sol";
import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import {DebtERC20} from "../src/DebtToken.sol";

import {PoolERC20} from "../src/PoolToken.sol";

import {RewardERC20} from "../src/RewardToken.sol";

import {SimplePool} from "../src/SimplePool.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPureSuperTokenCustom {
    function initialize(
        string calldata name,
        string calldata symbol,
        uint256 initialSupply
    ) external;
}

/**
 * @title Pure Super Token interface
 * @author Superfluid
 */
interface IPureSuperToken is IPureSuperTokenCustom, ISuperToken {

}

contract TestStreamLiquidityProvision is SuperfluidTester {
    address public host_;
    address public cfa_;
    address public ida_;

    PoolERC20 public poolToken;

    RewardERC20 public rewardToken;

    DebtERC20 public debtToken;

    ISuperToken public poolT;
    ISuperToken public rewardT;
    ISuperToken public debtT;

    SimplePool public pool;

    address public admin = address(1);
    address public streamLender = address(2);
    address public normalLender = address(3);

    constructor() SuperfluidTester(admin) {}

    function setUp() public {
        vm.startPrank(admin);

        host_ = address(sf.host);
        cfa_ = address(sf.cfa);
        ida_ = address(sf.ida);

        /**
         * deploy pool
         */
        pool = new SimplePool(host_);

        /** initialize the pool token */
        poolToken = new PoolERC20();

        poolT = ISuperToken(
            sf.superTokenFactory.createSuperTokenLogic(sf.host)
        );
        poolT.initialize(
            IERC20(address(poolToken)),
            18,
            "Super Test Pool Token",
            "SuTPT"
        );

        /**
         * pool liquidity token
         */
        rewardToken = new RewardERC20();

        rewardT = ISuperToken(
            sf.superTokenFactory.createSuperTokenLogic(sf.host)
        );

        rewardT.initialize(
            IERC20(address(rewardToken)),
            18,
            "Super Test Reward Token",
            "SuTRT"
        );
        rewardToken.transferOwnership(address(pool));

        /**
         * debtToken
         */
        debtToken = new DebtERC20();
        debtT = ISuperToken(
            sf.superTokenFactory.createSuperTokenLogic(sf.host)
        );

        debtT.initialize(
            IERC20(address(debtToken)),
            18,
            "Super Test Debt Token",
            "SuTDT"
        );

        debtToken.transferOwnership(address(pool));

        vm.stopPrank();
    }

    function testPool() public {
        vm.startPrank(admin);
        //add pool
        pool.addPool(poolT, rewardT, debtT);

        //test normal deposit

        poolToken.mint(normalLender, 100000 ether);

        poolToken.mint(streamLender, 100000 ether);

        vm.stopPrank();

        vm.startPrank(normalLender);
        //approve pool to spend tokens
        assert(poolToken.balanceOf(normalLender) == 100000 ether);

        //ISuperToken(address(poolToken)).approve(address(pool), 20000 ether);

        //make deposit
        poolToken.approve(address(pool), 20000 ether);
        uint256 poolTokeAmount = pool.supplyWithTransfer(poolT, 20000 ether);
        assert(rewardT.balanceOf(normalLender) == poolTokeAmount);

        /**
         * test borrowing after a normal deposit
         */

        pool.borrow(poolT, 10000 ether);
        vm.stopPrank();

        //test adding address to array
        //pool._addAddress(poolT, streamLender);
        vm.startPrank(streamLender);
        poolToken.approve(address(poolT), 100000 ether);

        poolT.upgrade(100000 ether);
        assert(poolT.balanceOf(streamLender) == 100000 ether);
        bytes memory _userData = abi.encodeCall(
            sf.cfa.createFlow,
            (poolT, address(pool), 0.01 ether, new bytes(0))
        );
        sf.host.callAgreement(sf.cfa, _userData, new bytes(0));

        (, int96 inflow, , ) = sf.cfa.getFlow(
            rewardT,
            address(pool),
            streamLender
        );

        (, int96 outflow, , ) = sf.cfa.getFlow(
            poolT,
            streamLender,
            address(pool)
        );
        /**
         * prove that the flow rate in is same as the flowrate out
         */
        assert(inflow == outflow);
    
        uint256 _timeNow = block.timestamp;

        uint256 _timeToTravel = (_timeNow + 30 days);

        uint256 flowRate_ = uint256(int256(inflow));

        uint256 _amountAccumulated = (flowRate_ * 30 days);

        /**
         * we move the chain 30 days ahead to get the total accumulated
         */
        vm.warp(_timeToTravel);

        /**
         * we ascertain that the amount accumulated is same as the user's token balance
         */
        assert(rewardT.balanceOf(streamLender) >= _amountAccumulated);

        uint256 amountStreamBorrower = (_amountAccumulated / 2);
        pool.borrow(poolT, amountStreamBorrower);

        /**
         * ascertain that the debt Token was transfered to the user
         */
        assert(debtT.balanceOf(streamLender) == amountStreamBorrower);
        vm.stopPrank();
    }
}
