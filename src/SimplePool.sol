// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import {ISuperfluid, ISuperToken, ISuperApp, ISuperAgreement, SuperAppDefinitions, ISuperfluidToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import {CFAv1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/CFAv1Library.sol";

import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";

import {SuperAppBase} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperAppBase.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IMint} from "./IMinter.sol";

/// @dev Constant Flow Agreement registration key, used to get the address from the host.
bytes32 constant CFA_ID = keccak256(
    "org.superfluid-finance.agreements.ConstantFlowAgreement.v1"
);

/// @dev Thrown when the receiver is the zero adress.
error InvalidReceiver();

/// @dev Thrown when receiver is also a super app.
error ReceiverIsSuperApp();

/// @dev Thrown when the callback caller is not the host.
error Unauthorized();

/// @dev Thrown when the token being streamed to this contract is invalid
error InvalidToken();

/// @dev Thrown when the agreement is other than the Constant Flow Agreement V1
error InvalidAgreement();

contract SimplePool is SuperAppBase, Ownable {
    using CFAv1Library for CFAv1Library.InitData;
    CFAv1Library.InitData public cfaV1Lib;

    ISuperToken[] private pools;

    struct Pool {
        IERC20 underlyingToken;
        ISuperfluidToken poolReward;
        ISuperToken debtToken;
        uint256 totalLiquidity;
        uint256 totalBorrowed;
        address[] streamers;
        uint256[] rewardTime;
    }

    mapping(ISuperToken => Pool) public poolId;

    //pool to rewards accumulated at specific time
    mapping(ISuperToken => mapping(uint256 => uint256)) poolTimeRewards;

    struct ClaimStatus {
        address user_;
        bool claimed;
    }

    mapping(ISuperToken => mapping(uint256 => ClaimStatus)) poolTimeClaimStatus;

    address tokenAddress;

    address[] addresses;

    ISuperfluid private _host; // host

    constructor(address host) {
        _host = ISuperfluid(host);

        cfaV1Lib = CFAv1Library.InitData({
            host: _host,
            cfa: IConstantFlowAgreementV1(
                address(_host.getAgreementClass(CFA_ID))
            )
        });
        uint256 configWord = SuperAppDefinitions.APP_LEVEL_FINAL |
            SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
            SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP;

        _host.registerApp(configWord);
    }

    modifier onlyHost() {
        if (msg.sender != address(cfaV1Lib.host)) revert Unauthorized();
        _;
    }

    modifier onlyExpected(ISuperToken superToken, address agreementClass) {
        //if (superToken != _acceptedToken) revert InvalidToken();
        if (agreementClass != address(cfaV1Lib.cfa)) revert InvalidAgreement();
        _;
    }

    function getAmountMinusFee(uint256 amount_)
        internal
        pure
        returns (uint256 feeCharged_, uint256 userAmount_)
    {
        feeCharged_ = (amount_ / 100);
        userAmount_ = amount_ - feeCharged_;
    }

    function addPool(
        ISuperToken poolToken_,
        ISuperfluidToken poolReward_,
        ISuperToken debtToken_
    ) external onlyOwner {
        IERC20 underlying = IERC20(poolToken_.getUnderlyingToken());

        require(address(underlying) != address(0));
        poolId[poolToken_] = Pool({
            underlyingToken: underlying,
            debtToken: debtToken_,
            poolReward: poolReward_,
            totalLiquidity: 0,
            totalBorrowed: 0,
            streamers: new address[](0),
            rewardTime: new uint256[](0)
        });
        address token_ = ISuperToken(address(poolReward_)).getUnderlyingToken();
        IMint reward_ = IMint(token_);
        reward_.mint(address(this), 1000000 ether);
        IERC20(token_).approve(address(poolReward_), 1000000 ether);
        ISuperToken(address(poolReward_)).upgrade(1000000 ether);
        pools.push(poolToken_);
    }

    //supply liquidity with normal ERC20 Transfer
    function supplyWithTransfer(ISuperToken poolID_, uint256 amount_)
        external
        returns (uint256 amountMinusFee)
    {
        Pool memory supplyPool = poolId[poolID_];
        bool success = supplyPool.underlyingToken.transferFrom(
            msg.sender,
            address(this),
            amount_
        );
        supplyPool.underlyingToken.approve(address(poolID_), amount_);
        poolID_.upgrade(amount_);
        address token_ = ISuperToken(address(supplyPool.poolReward))
            .getUnderlyingToken();
        IMint reward_ = IMint(token_);
        (uint256 fee_, uint256 _amount) = getAmountMinusFee(amount_);
        if (success) {
            reward_.mint(address(this), _amount);
        } else {
            revert();
        }
        IERC20(token_).approve(address(supplyPool.poolReward), _amount);
        ISuperToken(address(supplyPool.poolReward)).upgrade(_amount);
        ISuperToken(address(supplyPool.poolReward)).transfer(
            msg.sender,
            _amount
        );
        poolId[poolID_].totalLiquidity += _amount;
        poolTimeRewards[poolID_][block.timestamp] += fee_;
        poolId[poolID_].rewardTime.push(block.timestamp);
        amountMinusFee = _amount;
    }

    /**
     * used to get the maximum amount borrowable by an account
     */
    function getAddressBowwrowAmount(address borrower_, ISuperToken pool_)
        external
    {}

    function isStreaming(address user_, ISuperToken pool_)
        internal
        view
        returns (bool)
    {
        (, int96 inflow, , ) = cfaV1Lib.cfa.getFlow(
            pool_,
            user_,
            address(this)
        );
        //        address[] memory streamers = pool.streamers;
        if (inflow != 0) {
            return false;
        } else {
            return true;
        }
    }

    function claimRewards(
        ISuperToken _pool /*, uint256 startTime*/ //returns (uint256 nextStartTime)
    ) external {
        Pool memory pool = poolId[_pool];
        uint256[] memory rewardTimes = pool.rewardTime;
        uint256 _length = rewardTimes.length;
        for (uint256 i = 0; i < _length; ) {
            uint256 _time = rewardTimes[i];

            ClaimStatus memory status = poolTimeClaimStatus[_pool][_time];
            if (!status.claimed) {
                uint256 _timeReward = poolTimeRewards[_pool][_time];

                (int256 _poolLiquidity, , ) = _pool.realtimeBalanceOf(
                    address(this),
                    _time
                );
                (int256 userLiquidity, , ) = pool.poolReward.realtimeBalanceOf(
                    msg.sender,
                    _time
                );
                uint256 reward_ = (uint256(userLiquidity) /
                    uint256(_poolLiquidity)) * _timeReward;
                poolTimeRewards[_pool][_time] -= reward_;
                ISuperToken(address(pool.poolReward)).transfer(
                    msg.sender,
                    reward_
                );
                poolTimeClaimStatus[_pool][_time] = ClaimStatus({
                    user_: msg.sender,
                    claimed: true
                });
            }

            unchecked {
                i++;
            }
        }
    }

    function _getUserHealth(address borrower_, ISuperToken pool_)
        internal
        view
        returns (uint256 supply, uint256 debt)
    {
        Pool memory pool = poolId[pool_];
        supply = ISuperToken(address(pool.poolReward)).balanceOf(borrower_);
        debt = ISuperToken(address(pool.debtToken)).balanceOf(borrower_);
    }

    function borrow(ISuperToken _toBorrow, uint256 amount_) external {
        Pool memory pool_ = poolId[_toBorrow];

        require(address(pool_.poolReward) != address(0), "unititalized pool");

        require(
            ISuperToken(address(pool_.poolReward)).balanceOf(msg.sender) != 0,
            "no leverage"
        );

        require(
            amount_ != 0 && amount_ < pool_.totalLiquidity,
            "adjust amount"
        );

        (uint256 _supply, uint256 _debt) = _getUserHealth(
            msg.sender,
            _toBorrow
        );

        uint256 _difference = (_supply - _debt);
        uint256 minimum_health_for_borrow = (_difference / 3);

        if ((minimum_health_for_borrow * 2) >= amount_) {
            (uint256 fee_, ) = getAmountMinusFee(amount_);

            address _und = pool_.debtToken.getUnderlyingToken();

            IMint(_und).mint(address(this), amount_);

            IERC20(_und).approve(address(pool_.debtToken), amount_);

            pool_.debtToken.upgradeTo(msg.sender, amount_, new bytes(0));

            _toBorrow.transfer(msg.sender, amount_);

            poolTimeRewards[_toBorrow][block.timestamp] += fee_;
        }
    }

    /**
        notice: adds an address to the list of streamers
     */
    function _addAddress(ISuperToken pool_, address _toAdd) internal {
        Pool memory _pool = poolId[pool_];
        address[] memory addresses_ = _pool.streamers;
        for (uint256 i = 0; i < addresses_.length; ) {
            if (addresses_[i] == _toAdd) {
                return;
            } else {
                poolId[pool_].streamers.push(_toAdd);
            }
            unchecked {
                i++;
            }
        }
    }

    function getPoolHealth(ISuperToken token_)
        internal
        view
        returns (uint256 totalSupply_, uint256 _totalBorrowed)
    {
        Pool memory pool = poolId[token_];
        totalSupply_ = pool.totalLiquidity;
        _totalBorrowed = pool.totalBorrowed;
    }

    function getPoolRewardAddress(ISuperToken token_)
        internal
        view
        returns (address)
    {
        Pool memory pool = poolId[token_];
        return address(pool.poolReward);
    }

    // ---------------------------------------------------------------------------------------------
    // SUPER APP CALLBACKS

    function afterAgreementCreated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, //_agreementId
        bytes calldata, //_agreementData
        bytes calldata, //_cbdata
        bytes calldata _ctx
    )
        external
        override
        onlyExpected(_superToken, _agreementClass)
        onlyHost
        returns (bytes memory newCtx)
    {
        //ISuperfluid.Context memory dContext = _host.decodeCtx(_ctx);
        //(address reward, ) = abi.decode(dContext.userData, (address, address));
        return _updateOutflow(_ctx, _superToken);
    }

    function afterAgreementUpdated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32, // _agreementId,
        bytes calldata, // _agreementData,
        bytes calldata, // _cbdata,
        bytes calldata _ctx
    )
        external
        override
        onlyExpected(_superToken, _agreementClass)
        onlyHost
        returns (bytes memory newCtx)
    {
        //ISuperfluid.Context memory dContext = _host.decodeCtx(_ctx);

        //(address reward, ) = abi.decode(dContext.userData, (address, address));
        return _updateOutflow(_ctx, _superToken);
    }

    function afterAgreementTerminated(
        ISuperToken _superToken,
        address, //_agreementClass,
        bytes32, // _agreementId,
        bytes calldata, // _agreementData
        bytes calldata, // _cbdata,
        bytes calldata _ctx
    ) external override onlyHost returns (bytes memory newCtx) {
        //ISuperfluid.Context memory dContext = _host.decodeCtx(_ctx);
        //(address reward, ) = abi.decode(dContext.userData, (address, address));
        return _updateOutflow(_ctx, _superToken);
    }

    /// @dev Updates the outflow. The flow is either created, updated, or deleted, depending on the
    /// net flow rate.
    /// @param ctx The context byte array from the Host's calldata.
    /// @return newCtx The new context byte array to be returned to the Host.
    function _updateOutflow(bytes calldata ctx, ISuperToken _acceptedToken)
        private
        returns (bytes memory newCtx)
    {
        //get user inflow
        //get user outflow

        newCtx = ctx;
        ISuperfluid.Context memory dContext = _host.decodeCtx(ctx);
        address sender = dContext.msgSender;
        address reward = getPoolRewardAddress(_acceptedToken);
        (, int96 userInflow, , ) = cfaV1Lib.cfa.getFlow(
            _acceptedToken,
            sender,
            address(this)
        );

        (, int96 userOutflow, , ) = cfaV1Lib.cfa.getFlow(
            ISuperToken(reward),
            address(this),
            sender
        );

        if (userInflow == 0) {
            // The flow does exist and should be deleted.
            newCtx = cfaV1Lib.deleteFlowWithCtx(
                ctx,
                address(this),
                sender,
                ISuperToken(reward)
            );
        } else if (userOutflow != 0) {
            // The flow does exist and needs to be updated.
            newCtx = cfaV1Lib.updateFlowWithCtx(
                ctx,
                sender,
                ISuperToken(reward),
                userInflow
            );
        } else {
            newCtx = cfaV1Lib.createFlowWithCtx(
                ctx,
                sender,
                ISuperToken(reward),
                userInflow
            );
            _addAddress(_acceptedToken, sender);
        }
    }
}
