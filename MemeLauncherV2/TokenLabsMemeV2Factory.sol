// SPDX-License-Identifier: MIT
// Fork from https://bellum.exchange/

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./TokenLabsMemeV2.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/ITokenLabsMemeV2.sol";
pragma solidity ^0.8.17;

contract TokenLabsMemeV2Factory is Ownable, ReentrancyGuard {

    // Ecosystem Info
    bool public isPaused;
    address public ROUTER;
    address public feeReceiver;
    uint256 public createFee;
    uint256 public creationFees;
    uint256 public tradingFee; // 50 = 0.5% 50 = 0.5%
    uint112 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18; // 1 billion tokens, with 18 decimals

    // Constants
    uint256 public constant ETHER = 1 ether;
    uint256 public immutable BIN_WIDTH;
    uint256 public constant BASIS = 10000;
    uint256 public immutable COEF;
    uint256 public immutable MIN_IN;

    struct Curve {
        uint256[] distribution;
        uint256 percentOfLP; // 5000 = 5%
        uint256 ethAtLaunch;
    }

    struct Token {
        address creator;
        uint8 curveIndex;
        uint256 ethAccumulated;
        uint256 currentIndex;
        uint256 currentValue;
        uint256 initialSupply;
        bool hasLaunched;
    }

    address[] public allTokens;

    mapping(uint8 => Curve) public curves;
    mapping(address => Token) public tokens;

    event TokenCreated(
        address indexed token,
        address indexed creator,
        bool isPowder,
        uint curveIndex
    );

    event CurveCreated(uint indexed curveIndex);

    event TokenLabsSwap(
        address indexed token,
        address indexed sender,
        uint amount0In,
        uint amount0Out,
        uint amount1In,
        uint amount1Out
    );

    event CurveCompleted(
        address indexed token0,
        address indexed dist,
        address indexed mlp
    );

    constructor(address owner_, address router_, uint256 min_in_, uint256 coef_, uint256 bin_width_, uint256 create_fee_) Ownable(msg.sender) {
        tradingFee = 100; // 1%
        ROUTER = router_;
        feeReceiver = owner_;
        MIN_IN = min_in_;
        COEF = coef_;
        BIN_WIDTH = bin_width_;
        createFee = create_fee_;
    }

    function createToken(
        string memory name_,
        string memory symbol_,
        uint8 curveIndex_
    ) external payable nonReentrant {
        (uint256[] memory arr, uint256 percent) = getCurve(curveIndex_);
        uint256 createFee_ = createFee;
        require(!isPaused, "TokenLabs: NEW_TOKEN_CREATION_IS_PAUSED");
        require(percent > 4999, "TokenLabs: CURVE_DOES_NOT_EXIST");
        require(msg.value <= 500 ether + createFee_, "TokenLabs: TOO_MUCH_ETH");
        require(msg.value >= createFee_, "TokenLabs: TOO_LITTLE_ETH");

        TokenLabsMemeV2 token = new TokenLabsMemeV2(
            name_,
            symbol_,
            INITIAL_SUPPLY
        );

        address t = address(token);
        allTokens.push(t);
        uint256 supply = uint256((INITIAL_SUPPLY * percent) / BASIS);

        tokens[t].initialSupply = supply;
        tokens[t].currentValue = (supply * arr[0]) / BASIS;
        tokens[t].curveIndex = curveIndex_;
        tokens[t].creator = msg.sender;
        IERC20(t).approve(ROUTER, type(uint256).max);
        emit TokenCreated(t, msg.sender, false, curveIndex_);
        creationFees += createFee_;
        if (msg.value != createFee_) {
            _buy(t, msg.sender, msg.value - createFee_, 0);
        }
    }

    function createCurve(
        uint8 index,
        uint256[] memory lists
    ) external onlyOwner {
        require(
            curves[index].percentOfLP == 0,
            "TokenLabs: CURVE_ALREADY_IN_USE"
        );
        uint256 totalDistribution = 0;
        // Amount of ETH
        uint256 cumulativeValue = 0;

        // Start price at 1 ether
        uint256 length = lists.length;
        // Calculate the cumulative value and track the last non-zero bin
        for (uint256 i = 0; i < length; i++) {
            require(lists[i] > 0, "TokenLabs: INVALID_BIN");
            totalDistribution += lists[i];
            uint256 price = (ETHER * (BASIS + (i * BIN_WIDTH))) / BASIS;
            cumulativeValue += lists[i] * price;
        }

        // Ensure the total distribution equals 10,000 (in basis points)
        require(
            totalDistribution == BASIS,
            "TokenLabs: INVALID_TOTAL_DISTRIBUTION"
        );

        // Calculate the price for the last non-zero bin
        uint256 lastNonZeroPrice = (ETHER *
            (((length - 1) * BIN_WIDTH) + BASIS)) / BASIS;

        // Calculate the required market cap based on the last non-zero bin value and total tokens
        uint256 requiredMarketCap = BASIS * lastNonZeroPrice;
        uint256 fraction = (BASIS * requiredMarketCap) /
            (requiredMarketCap + cumulativeValue);
        curves[index] = Curve(lists, fraction, cumulativeValue / COEF);
        emit CurveCreated(index);
    }

    function buy(address token0, uint8 minBin) external payable nonReentrant {
        require(msg.value >= MIN_IN, "TokenLabs: NOT_ENOUGH_ETH");
        _buy(token0, msg.sender, msg.value, minBin);
    }

    function _buy(
        address token0,
        address sender,
        uint256 amountIn,
        uint8 minBin
    ) internal {
        Token storage t = tokens[token0];
        require(t.initialSupply > 0, "TokenLabs: TOKEN_DOES_NOT_EXIST");
        require(!t.hasLaunched, "TokenLabs: ALREADY_LAUNCHED");
        require(t.currentIndex <= minBin, "TokenLabs: SLIPPAGE_LIMIT");

        uint256[] memory arr = curves[t.curveIndex].distribution;
        uint256 _fee = (amountIn * tradingFee) / BASIS;
        uint256 value = amountIn - _fee;
        uint256 amount0Out;
        uint256 amount1Used;
        uint256 i = t.currentIndex;
        while (amount1Used < value) {
            uint256 amountPerETH = (t.initialSupply * COEF) /
                (BASIS + (BIN_WIDTH * i));
            uint256 valueLeft = value - amount1Used;
            uint256 amount0InBin = t.currentValue;

            if (amount0InBin > (valueLeft * amountPerETH) / ETHER) {
                uint256 usedValue = valueLeft;
                uint256 outputAmount = (amountPerETH * valueLeft) / ETHER;

                amount1Used += usedValue;
                amount0Out += outputAmount;
                t.currentValue = amount0InBin - outputAmount; // Update storage once

                break;
            } else {
                uint256 usedValue = (amount0InBin * ETHER) / amountPerETH;

                amount1Used += usedValue;
                amount0Out += amount0InBin;
                i++;
                if (i < arr.length) {
                    t.currentValue = (arr[i] * t.initialSupply) / BASIS;
                } else {
                    break;
                }
            }
        }

        t.currentIndex = i;
        IERC20(token0).transfer(sender, amount0Out);
        (bool success, ) = feeReceiver.call{value: _fee}("");
        require(success, "Failed to send Ether");
        emit TokenLabsSwap(token0, sender, 0, amount0Out, amountIn, 0);
        t.ethAccumulated += amountIn;
        if (i >= arr.length) {
            (bool sent, ) = sender.call{value: value - amount1Used}("");
            require(sent, "Failed to send Ether");
            _launchToken(token0);
        }
    }

    function sell(
        address token0,
        uint256 amount0In,
        uint8 minBin
    ) external nonReentrant {
        Token storage t = tokens[token0];
        require(t.initialSupply > 0, "TokenLabs: TOKEN_DOES_NOT_EXIST");
        require(!t.hasLaunched, "TokenLabs: INSUFFICIENT_LIQUIDITY");
        require(t.currentIndex >= minBin, "TokenLabs: SLIPPAGE_LIMIT");
        require(
            IERC20(token0).transferFrom(msg.sender, address(this), amount0In),
            "TokenLabs: TRANSFER_FAILED"
        );

        uint256[] memory arr = curves[t.curveIndex].distribution;
        uint256 amount1Out;
        uint256 amount0Used;
        uint256 i = t.currentIndex;
        while (amount0Used < amount0In) {
            uint256 amountPerETH = (t.initialSupply * COEF) /
                (BASIS + (BIN_WIDTH * i));
            uint256 amountLeft = amount0In - amount0Used;
            uint256 amount0InBin = t.currentValue;
            uint256 amount0InBinMax = (arr[i] * t.initialSupply) / BASIS;
            if (amount0InBin + amountLeft <= amount0InBinMax) {
                amount1Out += (amountLeft * ETHER) / amountPerETH;
                t.currentValue += amountLeft; // Update storage once
                break;
            } else {
                uint256 fillBin = amount0InBinMax - amount0InBin;
                amount0Used += fillBin;
                amount1Out += (fillBin * ETHER) / amountPerETH;
                i--;
                t.currentValue = 0; // Update storage once
            }
        }
        t.currentIndex = i;

        uint256 _fee = (amount1Out * tradingFee) / BASIS;
        (bool success, ) = feeReceiver.call{value: _fee}("");
        require(success, "Failed to send Ether");
        (bool sent, ) = msg.sender.call{value: amount1Out - _fee}("");
        require(sent, "Failed to send Ether");
        emit TokenLabsSwap(token0, msg.sender, amount0In, 0, 0, amount1Out);
        t.ethAccumulated -= amount1Out;
    }

    function _launchToken(address token0) internal {
        Token storage t = tokens[token0];

        require(!t.hasLaunched, "TokenLabs: ALREADY_LAUNCHED");

        ITokenLabsMemeV2(token0).completeTheCurve();
        IRouter MemeRouter = IRouter(ROUTER);
        address memeFactory = MemeRouter.factory();
        address weth = MemeRouter.WETH();
        address pair = IFactory(memeFactory).getPair(token0, weth);
        if (pair == address(0)) {
            pair = IFactory(memeFactory).createPair(token0, weth);
        }

        uint256 ethToLaunch = curves[t.curveIndex].ethAtLaunch;
        MemeRouter.addLiquidityETH{value: ethToLaunch}(
            token0,
            IERC20(token0).balanceOf(address(this)),
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0),
            block.timestamp
        );
        t.hasLaunched = true;
        emit CurveCompleted(token0, address(0), pair);
    }

    function getCurve(
        uint8 index
    ) public view returns (uint256[] memory, uint256) {
        return (curves[index].distribution, curves[index].percentOfLP);
    }

    function allTokensLength() external view returns (uint) {
        return allTokens.length;
    }

    // Owner
    function changeFeeReceiver(address feeReceiver_) external onlyOwner {
        feeReceiver = feeReceiver_;
    }

    function changeFee(uint256 newFee_) external onlyOwner {
        require(newFee_ <= 250, "TokenLabs: FEE_TOO_HIGH");
        tradingFee = newFee_;
    }

    function changeCreateFee(uint256 newFee_) external onlyOwner {
        createFee = newFee_;
    }

    function setIsPaused(bool isPaused_) external onlyOwner {
        isPaused = isPaused_;
    }

    function withdrawFees() external nonReentrant onlyOwner {
        uint256 fees = creationFees;
        creationFees = 0;
        (bool success, ) = feeReceiver.call{value: fees}("");
        require(success, "Failed to send Ether");
    }

}
