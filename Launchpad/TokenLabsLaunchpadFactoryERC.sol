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

contract TokenLabsLaunchpadFactory is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address[] public sales;
    event SaleCreated(address newSale);

    uint256 private _feeAmount = 1 ether; // 1 ETH fee
    IUniswapV2Router02 private _router;
    address private _weth;

    struct SaleParams { 
        address payable seller; ERC20 token; uint256 softcap; uint256 hardcap; uint256 startTime; uint256 endTime; 
        uint256 tokensPerWei; uint256 tokensPerWeiListing; bool limitPerAccountEnabled; uint256 limitPerAccount; 
        address pairingToken; uint256 referralRewardPercentage; uint256 rewardPool; 
    }

    constructor( IUniswapV2Router02 router, address weth) Ownable(msg.sender) {
        (_router, _weth) = (router, weth);
    }

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

    function getFeeAmount() external view returns (uint256) { return _feeAmount; }

    function getSales() public view returns (address[] memory) { return sales; }
}

contract SaleContract is ReentrancyGuard {
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
    mapping(address => bool) public admins;
    address public weth;
    bool public isListed = false;

    constructor(TokenLabsLaunchpadFactory.SaleParams memory params, IUniswapV2Router02 _dexRouter, address _weth) {
        sale = Sale(params.seller, params.token, params.softcap, params.hardcap, params.startTime, params.endTime, params.tokensPerWei, params.tokensPerWeiListing, 0, params.limitPerAccountEnabled, params.limitPerAccount, params.referralRewardPercentage, params.rewardPool);
        additionalSaleDetails = AdditionalSaleDetails(params.pairingToken);
        dexRouter = _dexRouter;
        admins[msg.sender] = true;
        weth = _weth;
    }

    modifier onlyAdmin() {
        require(admins[msg.sender] == true, "Caller is not authorized");
        _;
    }

    function addAdmin(address newAdmin) public onlyAdmin {
        admins[newAdmin] = true;
    }

    function removeAdmin(address adminToRemove) public onlyAdmin {
        admins[adminToRemove] = false;
    }

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
        
        if (excessAmount > 0 && isETH) payable(msg.sender).transfer(excessAmount);

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

    function addLiquidityToDEX(uint256 tokenAmount, uint256 ethAmount) private {
        IERC20(address(sale.token)).approve(address(dexRouter), tokenAmount);
        if (additionalSaleDetails.pairingToken == address(0)) {
            dexRouter.addLiquidityETH{value: ethAmount}(address(sale.token), tokenAmount, 0, 0, address(0), block.timestamp);
        } else {
            IERC20(additionalSaleDetails.pairingToken).approve(address(dexRouter), ethAmount);
            dexRouter.addLiquidity(address(sale.token), additionalSaleDetails.pairingToken, tokenAmount, ethAmount, 0, 0, address(0), block.timestamp);
        }
    }

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


    function claim() external nonReentrant {
        require(block.timestamp > sale.endTime, "Sale has not ended");
        if (sale.collectedETH < sale.softcap) {
            uint256 remainingTokens = IERC20(address(sale.token)).balanceOf(address(this));
            uint256 ethAmount = contributions[msg.sender];

            if (sale.seller == msg.sender && remainingTokens > 0) {
                IERC20(address(sale.token)).safeTransfer(msg.sender, remainingTokens);
                if(ethAmount > 0){
                    contributions[msg.sender] = 0;
                    payable(msg.sender).transfer(ethAmount);
                }
            } else {
                require(ethAmount > 0, "No amount available to claim");
                contributions[msg.sender] = 0;
                payable(msg.sender).transfer(ethAmount);
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

    function cancelSale() external onlyAdmin nonReentrant {
        require(block.timestamp < sale.startTime || block.timestamp > sale.endTime, "Sale cannot be cancelled after it has started");
        sale.endTime = block.timestamp; // Mark the sale as ended
    }

    function balanceOf(address account) public view returns (uint256) { return tokenAmounts[account]; }

    function getTokenBalance() public view returns (uint256) { return sale.token.balanceOf(address(this)); }

    function getCollectedETH() public view returns (uint256) { return sale.collectedETH; }

    function getSoftcap() public view returns (uint256) { return sale.softcap; }

    function getHardcap() public view returns (uint256) { return sale.hardcap; }

    function getStartTime() public view returns (uint256) { return sale.startTime; }

    function getEndTime() public view returns (uint256) { return sale.endTime; }

    function getExpectedLiquidityETH() public view returns (uint256) { return sale.collectedETH; }

    function getContractETHBalance() public view returns (uint256) { return address(this).balance; }

    function getSellerAddress() public view returns (address payable) { return sale.seller; }

    function getLiquidityETH() public view returns (uint256) { return sale.collectedETH; }

    function getLiquidityTokenAmount() public view returns (uint256) { return (sale.collectedETH == 0) ? 0 : ((sale.collectedETH > sale.hardcap ? sale.hardcap : sale.collectedETH) * sale.tokensPerWeiListing); }

    function getTokenContract() public view returns (IERC20) { return sale.token; }

    function getTokensPerWei() public view returns (uint256) { return sale.tokensPerWei; }

    function getTokensPerWeiListing() public view returns (uint256) { return sale.tokensPerWeiListing; }

    function getContributions(address user) public view returns (uint256) { return contributions[user]; }
}
