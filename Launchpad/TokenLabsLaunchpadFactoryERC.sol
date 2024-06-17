// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title TokenLabsLaunchpadFactory
 * @dev This contract allows the creation of token sales for launching new tokens. 
 *      It charges a fee for creating each sale and handles the token sale process.
 */
contract TokenLabsLaunchpadFactory is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address[] public sales;
    event SaleCreated(address newSale);

    uint256 private _feeAmount = 1 ether; // 1 ETH fee
    IUniswapV2Router02 private immutable _router;
    address private immutable _weth;

    struct SaleParams { 
        address payable seller; ERC20 token; uint256 softcap; uint256 hardcap; uint256 startTime; uint256 endTime; 
        uint256 tokensPerWei; uint256 tokensPerWeiListing; bool limitPerAccountEnabled; uint256 limitPerAccount; 
        address pairingToken; uint256 referralRewardPercentage; uint256 rewardPool; 
    }

    /**
     * @dev Initializes the contract with the given parameters.
     * @param router The address of the Uniswap V2 router.
     * @param weth The address of the Wrapped ETH token.
     */
    constructor(IUniswapV2Router02 router, address weth) Ownable(msg.sender) {
        (_router, _weth) = (router, weth);
    }

    /**
     * @notice Creates a new token sale.
     * @param params The parameters of the sale.
     * @return The address of the newly created sale contract.
     * @dev Requires a fee to be paid. The fee is transferred to the contract owner.
     */
    function createSale(SaleParams memory params) public payable nonReentrant returns (address) {
        require(msg.value == _feeAmount, "Incorrect fee amount");
        require(params.referralRewardPercentage <= 10, "Referral reward percentage cannot exceed 10%");

        require(payable(owner()).send(msg.value), "Transfer failed");

        uint256 tokenAmountForSale = (params.hardcap * params.tokensPerWei) + (params.hardcap * params.tokensPerWeiListing) + params.rewardPool;
        IERC20(address(params.token)).safeTransferFrom(params.seller, address(this), tokenAmountForSale);

        SaleContract newSale = new SaleContract(params, _router, _weth);
        IERC20(address(params.token)).safeTransfer(address(newSale), tokenAmountForSale);

        sales.push(address(newSale));
        emit SaleCreated(address(newSale));
        return address(newSale);
    }

    /**
     * @notice Returns the fee amount for creating a sale.
     * @return The fee amount.
     */
    function getFeeAmount() external view returns (uint256) { return _feeAmount; }

    /**
     * @notice Returns the list of created sales.
     * @return An array of sale addresses.
     */
    function getSales() public view returns (address[] memory) { return sales; }
}

/**
 * @title SaleContract
 * @dev This contract handles the token sale process, including buying tokens, adding liquidity, and claiming tokens.
 */
contract SaleContract is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Sale { 
        address payable seller; ERC20 token; uint256 softcap; uint256 hardcap; uint256 startTime; uint256 endTime; 
        uint256 tokensPerWei; uint256 tokensPerWeiListing; uint256 collectedETH; bool limitPerAccountEnabled; 
        uint256 limitPerAccount; uint256 referralRewardPercentage; uint256 rewardPool; 
    }

    struct AdditionalSaleDetails { address pairingToken; }

    Sale public sale;
    AdditionalSaleDetails public additionalSaleDetails;
    IUniswapV2Router02 public dexRouter;
    mapping(address => uint256) public contributions;
    mapping(address => uint256) public tokenAmounts;
    mapping(address => uint256) public referralRewards;
    address public weth;
    bool public isListed = false;

    /**
     * @dev Initializes the sale contract with the given parameters.
     * @param params The parameters of the sale.
     * @param _dexRouter The address of the Uniswap V2 router.
     * @param _weth The address of the Wrapped ETH token.
     */
    constructor(TokenLabsLaunchpadFactory.SaleParams memory params, IUniswapV2Router02 _dexRouter, address _weth) Ownable(msg.sender) {
        sale = Sale(params.seller, params.token, params.softcap, params.hardcap, params.startTime, params.endTime, params.tokensPerWei, params.tokensPerWeiListing, 0, params.limitPerAccountEnabled, params.limitPerAccount, params.referralRewardPercentage, params.rewardPool);
        additionalSaleDetails = AdditionalSaleDetails(params.pairingToken);
        dexRouter = _dexRouter;
        weth = _weth;
    }

    /**
     * @notice Allows users to buy tokens during the sale.
     * @param erc20Amount The amount of ERC20 tokens to buy.
     * @param referrer The address of the referrer.
     * @dev Users can buy tokens using ETH or another ERC20 token. Applies referral rewards if applicable.
     */
    function buyTokens(uint256 erc20Amount, address referrer) public payable nonReentrant {
        require(block.timestamp >= sale.startTime && block.timestamp <= sale.endTime, "Sale is not ongoing");
        require(msg.value > 0 || erc20Amount > 0, "Amount must be greater than zero");
        require(referrer != msg.sender, "You cannot refer yourself");

        uint256 purchaseAmount;
        bool isETH = msg.value > 0;
        uint256 excessAmount = 0;

        if (isETH) {
            purchaseAmount = msg.value;
        } else {
            purchaseAmount = erc20Amount;
            IERC20(additionalSaleDetails.pairingToken).safeTransferFrom(msg.sender, address(this), purchaseAmount);
        }

        if (sale.limitPerAccountEnabled && sale.collectedETH < sale.softcap) {
            uint256 allowedAmount = sale.limitPerAccount - contributions[msg.sender];
            if (purchaseAmount > allowedAmount) {
                excessAmount = purchaseAmount - allowedAmount;
                purchaseAmount = allowedAmount;
            }
        }

        if (purchaseAmount + sale.collectedETH > sale.hardcap) {
            excessAmount += purchaseAmount + sale.collectedETH - sale.hardcap;
            purchaseAmount -= excessAmount;
        }

        uint256 amountOfTokens = (purchaseAmount) * sale.tokensPerWei;
        require(amountOfTokens > 0, "Not enough amount for tokens");

        tokenAmounts[msg.sender] += amountOfTokens;
        
        if (excessAmount > 0 && isETH) require(payable(owner()).send(msg.value), "Transfer failed");

        if (excessAmount > 0 && !isETH) IERC20(additionalSaleDetails.pairingToken).safeTransfer(msg.sender, excessAmount);

        sale.collectedETH = isETH ? address(this).balance : IERC20(additionalSaleDetails.pairingToken).balanceOf(address(this));

        contributions[msg.sender] += purchaseAmount;

        if (referrer != address(0) && sale.rewardPool > 0) {
            uint256 referralReward = (amountOfTokens * sale.referralRewardPercentage) / 100;
            if (referralReward > sale.rewardPool) {
                referralReward = sale.rewardPool;
            }
            referralRewards[referrer] += referralReward;
            sale.rewardPool -= referralReward;
        }
    }

    /**
     * @dev Adds liquidity to Uniswap V2.
     * @param tokenAmount The amount of tokens to add as liquidity.
     * @param ethAmount The amount of ETH to add as liquidity.
     */
    function addLiquidityToDEX(uint256 tokenAmount, uint256 ethAmount) private {
        IERC20(address(sale.token)).approve(address(dexRouter), tokenAmount);
        if (additionalSaleDetails.pairingToken == address(0)) {
            dexRouter.addLiquidityETH{value: ethAmount}(address(sale.token), tokenAmount, 0, 0, address(0), block.timestamp);
        } else {
            IERC20(additionalSaleDetails.pairingToken).approve(address(dexRouter), ethAmount);
            dexRouter.addLiquidity(address(sale.token), additionalSaleDetails.pairingToken, tokenAmount, ethAmount, 0, 0, address(0), block.timestamp);
        }
    }

    /**
     * @notice Ends the token sale and adds liquidity to Uniswap V2.
     * @dev The sale can only be ended if the softcap is reached and the sale end conditions are met.
     */
    function endSale() external nonReentrant {
        require(!isListed, "Tokens were listed");
        require(block.timestamp > sale.endTime || sale.collectedETH >= sale.hardcap, "Sale end conditions not met");
        if (sale.collectedETH < sale.softcap) return;

        uint256 liquidityETH = sale.collectedETH > sale.hardcap ? sale.hardcap : sale.collectedETH;
        uint256 excessETH = sale.collectedETH > sale.hardcap ? sale.collectedETH - sale.hardcap : 0;

        if (sale.collectedETH >= sale.softcap && sale.collectedETH < sale.hardcap) {
            uint256 remainingEth = sale.hardcap > sale.collectedETH ? sale.hardcap - sale.collectedETH : 0;
            uint256 remainingTokens = (remainingEth * sale.tokensPerWeiListing) + (remainingEth * sale.tokensPerWei);
            ERC20Burnable token = ERC20Burnable(address(sale.token));
            if (remainingTokens > 0) {
                token.burn(remainingTokens);
            }
            if (sale.rewardPool > 0) {
                token.burn(sale.rewardPool);
            }
        }

        if (excessETH > 0) {
            if (additionalSaleDetails.pairingToken == address(0)) {
                sale.seller.transfer(excessETH);
            } else {
                IERC20(additionalSaleDetails.pairingToken).safeTransfer(sale.seller, excessETH);
            }
        }

        uint256 liquidityToken = liquidityETH * sale.tokensPerWeiListing;
        if (additionalSaleDetails.pairingToken == address(0)) {
            addLiquidityToDEX(liquidityToken, liquidityETH);
        } else {
            uint256 pairingTokenAmount = IERC20(additionalSaleDetails.pairingToken).balanceOf(address(this));
            addLiquidityToDEX(liquidityToken, pairingTokenAmount);
        }

        sale.endTime = block.timestamp;
        isListed = true;
    }

    /**
     * @notice Allows users to claim their purchased tokens or refunds after the sale ends.
     * @dev If the sale did not reach the softcap, users can claim refunds. Otherwise, they can claim their tokens.
     */
    function claim() external nonReentrant {
        require(block.timestamp > sale.endTime, "Sale has not ended");
        if (sale.collectedETH < sale.softcap) {
            uint256 remainingTokens = IERC20(address(sale.token)).balanceOf(address(this));
            uint256 ethAmount = contributions[msg.sender];

            if (sale.seller == msg.sender && remainingTokens > 0) {
                IERC20(address(sale.token)).safeTransfer(msg.sender, remainingTokens);
                if(ethAmount > 0){
                    contributions[msg.sender] = 0;
                    require(payable(msg.sender).send(ethAmount), "Transfer failed");
                }
            } else {
                require(ethAmount > 0, "No amount available to claim");
                contributions[msg.sender] = 0;
                require(payable(msg.sender).send(ethAmount), "Transfer failed");
            }
        } else {
            uint256 tokens = tokenAmounts[msg.sender];
            uint256 referralReward = referralRewards[msg.sender];
            uint256 totalTokens = tokens + referralReward;

            require(totalTokens > 0, "No tokens available to claim");
            tokenAmounts[msg.sender] = 0;
            referralRewards[msg.sender] = 0;
            IERC20(address(sale.token)).safeTransfer(msg.sender, totalTokens);
        }
    }

    /**
     * @notice Cancels the token sale.
     * @dev The sale can only be cancelled before it starts or after it ends.
     */
    function cancelSale() external onlyOwner nonReentrant {
        require(block.timestamp < sale.startTime || block.timestamp > sale.endTime, "Sale cannot be cancelled after it has started");
        sale.endTime = block.timestamp; // Mark the sale as ended
    }

    /**
     * @notice Returns the balance of tokens for a specific account.
     * @param account The address of the account.
     * @return The balance of tokens.
     */
    function balanceOf(address account) public view returns (uint256) { return tokenAmounts[account]; }

    /**
     * @notice Returns the balance of tokens in the contract.
     * @return The balance of tokens.
     */
    function getTokenBalance() public view returns (uint256) { return sale.token.balanceOf(address(this)); }

    /**
     * @notice Returns the total amount of ETH collected during the sale.
     * @return The amount of collected ETH.
     */
    function getCollectedETH() public view returns (uint256) { return sale.collectedETH; }

    /**
     * @notice Returns the softcap of the sale.
     * @return The softcap.
     */
    function getSoftcap() public view returns (uint256) { return sale.softcap; }

    /**
     * @notice Returns the hardcap of the sale.
     * @return The hardcap.
     */
    function getHardcap() public view returns (uint256) { return sale.hardcap; }

    /**
     * @notice Returns the start time of the sale.
     * @return The start time.
     */
    function getStartTime() public view returns (uint256) { return sale.startTime; }

    /**
     * @notice Returns the end time of the sale.
     * @return The end time.
     */
    function getEndTime() public view returns (uint256) { return sale.endTime; }

    /**
     * @notice Returns the expected liquidity in ETH.
     * @return The expected liquidity in ETH.
     */
    function getExpectedLiquidityETH() public view returns (uint256) { return sale.collectedETH; }

    /**
     * @notice Returns the ETH balance of the contract.
     * @return The ETH balance of the contract.
     */
    function getContractETHBalance() public view returns (uint256) { return address(this).balance; }

    /**
     * @notice Returns the address of the seller.
     * @return The seller address.
     */
    function getSellerAddress() public view returns (address payable) { return sale.seller; }

    /**
     * @notice Returns the liquidity in ETH.
     * @return The liquidity in ETH.
     */
    function getLiquidityETH() public view returns (uint256) { return sale.collectedETH; }

    /**
     * @notice Returns the amount of tokens for liquidity.
     * @return The amount of tokens for liquidity.
     */
    function getLiquidityTokenAmount() public view returns (uint256) { return (sale.collectedETH == 0) ? 0 : ((sale.collectedETH > sale.hardcap ? sale.hardcap : sale.collectedETH) * sale.tokensPerWeiListing); }

    /**
     * @notice Returns the token contract.
     * @return The token contract.
     */
    function getTokenContract() public view returns (IERC20) { return sale.token; }

    /**
     * @notice Returns the number of tokens per Wei during the sale.
     * @return The number of tokens per Wei.
     */
    function getTokensPerWei() public view returns (uint256) { return sale.tokensPerWei; }

    /**
     * @notice Returns the number of tokens per Wei for liquidity listing.
     * @return The number of tokens per Wei for liquidity listing.
     */
    function getTokensPerWeiListing() public view returns (uint256) { return sale.tokensPerWeiListing; }

    /**
     * @notice Returns the contributions of a specific user.
     * @param user The address of the user.
     * @return The contributions of the user.
     */
    function getContributions(address user) public view returns (uint256) { return contributions[user]; }
}
