// SPDX-License-Identifier: Apache-2.0
/** # This code has been created by TokenLabs. # @‌website TokenLabs.network # @‌contact admin@tokenlabs.network # Its use and modification are permitted, but always give credit to TokenLabs. # This comment will help you comply with legal requirements. # # Licensed under the Apache License, Version 2.0 (the "License"); # you may not use this file except in compliance with the License. # You may obtain a copy of the License at # # http://www.apache.org/licenses/LICENSE-2.0 # # Unless required by applicable law or agreed to in writing, software # distributed under the License is distributed on an "AS IS" BASIS, # WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. # See the License for the specific language governing permissions and # limitations under the License.
*/
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title ITokenLabsTokenFactory
 * @dev Interface for the TokenLabsTokenFactory contract.
 */
interface ITokenLabsTokenFactory { function whitelist(address token) external view returns (bool); }

/**
 * @title IFactoryWithPair
 * @dev Interface for the factory contract.
 */
interface IFactoryWithPair { function getPair(address tokenA, address tokenB) external view returns (address pair); function createPair(address tokenA, address tokenB) external returns (address pair);}

interface IWETH { function deposit() external payable; function transfer(address to, uint256 value) external returns (bool); }

/**
 * @title IPair
 * @dev Interface for the pair contract to check totalSupply.
 */
interface IPair { function totalSupply() external view returns (uint256); function mint(address to) external returns (uint256 liquidity);}

/**
 * @title TokenLabsLaunchpadFactory
 * @dev This contract allows the creation of token sales for launching new tokens. 
 *      It charges a fee for creating each sale and handles the token sale process.
 */
contract TokenLabsLaunchpadFactory is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address[] public sales;
    event SaleCreated(address newSale);
    event FeeAmountUpdated(uint256 oldFeeAmount, uint256 newFeeAmount);

    uint256 private _feeAmount = 1 ether; // 1 ETH fee
    address private immutable _weth;
    address private immutable _tokenFactory;
    address private immutable _pairFactory;

    struct SaleParams { 
        address payable seller; ERC20 token; uint256 softcap; uint256 hardcap; uint256 startTime; uint256 endTime; 
        uint256 tokensPerWei; uint256 tokensPerWeiListing; bool limitPerAccountEnabled; uint256 limitPerAccount; 
        address pairingToken; uint256 referralRewardPercentage; uint256 rewardPool; 
    }

    /**
     * @dev Initializes the contract with the given parameters.
     * @param pairFactory The address of the Pair Factory.
     * @param weth The address of the Wrapped ETH token.
     * @param tokenFactory The address of the token factory contract.
     */
    constructor(address pairFactory, address weth, address tokenFactory) Ownable(msg.sender) {
        _weth = weth; _tokenFactory = tokenFactory; _pairFactory = pairFactory;
    }

    /**
     * @notice Creates a new token sale.
     * @param params The parameters of the sale.
     * @return The address of the newly created sale contract.
     * @dev Requires a fee to be paid. The fee is transferred to the contract owner.
     */
    function createSale(SaleParams memory params) public payable nonReentrant returns (address) {
        require(msg.sender == tx.origin, "Contracts are not allowed");
        require(msg.value == _feeAmount, "Incorrect fee amount");
        require(params.referralRewardPercentage <= 10, "Referral reward percentage cannot exceed 10%");

        // Validate that the token is on the whitelist of the second contract
        ITokenLabsTokenFactory tokenFactory = ITokenLabsTokenFactory(_tokenFactory);
        require(tokenFactory.whitelist(address(params.token)), "Token is not whitelisted");

        // Validate that the pair does not exist in the MagicSeaFactory contract
        IFactoryWithPair pairFactory = IFactoryWithPair(_pairFactory);

        address pairingToken = params.pairingToken;

        if(pairingToken == address(0)){ pairingToken = _weth; }
        
        address pair = pairFactory.getPair(address(params.token), pairingToken);

        if(pair != address(0)){
            IPair existingPair = IPair(pair);
            uint256 totalSupply = existingPair.totalSupply();
            require(totalSupply == 0, "Pair already exists");

            uint256 saleTokenPairBalance = IERC20(params.token).balanceOf(pair);
            require(saleTokenPairBalance == 0, "Pair already exists");

        }

        if(params.referralRewardPercentage > 0){ require(params.rewardPool > 0, "Reward Pool cannot be 0"); }

        (bool success, ) = owner().call{value: msg.value}("");
        require(success, "Transfer failed");

        uint256 tokenAmountForSale = (params.hardcap * params.tokensPerWei) + (params.hardcap * params.tokensPerWeiListing) + params.rewardPool;
        IERC20(address(params.token)).safeTransferFrom(params.seller, address(this), tokenAmountForSale);

        SaleContract newSale = new SaleContract(params, _pairFactory, _weth, msg.sender);
        IERC20(address(params.token)).safeTransfer(address(newSale), tokenAmountForSale);

        sales.push(address(newSale));
        emit SaleCreated(address(newSale));
        return address(newSale);
    }

    /**
    * @notice Override renounceOwnership.
    */
    function renounceOwnership() public override onlyOwner { revert("Renounce ownership is not allowed"); }

    /**
     * @notice Sets the fee amount for creating a sale.
     * @param feeAmount The new fee amount.
     */
    function setFeeAmount(uint256 feeAmount) external onlyOwner {
        uint256 oldFeeAmount = _feeAmount;
        _feeAmount = feeAmount;
        emit FeeAmountUpdated(oldFeeAmount, feeAmount);
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
    address public pairFactory;
    mapping(address => uint256) public contributions;
    mapping(address => uint256) public tokenAmounts;
    mapping(address => uint256) public referralRewards;
    address public weth;
    bool public isListed = false;
    bool public isCanceled = false;
    string public cancelMsg = "";

    /**
     * @dev Initializes the sale contract with the given parameters.
     * @param params The parameters of the sale.
     * @param _pairFactory The address of the Uniswap V2 Factory.
     * @param _weth The address of the Wrapped ETH token.
     * @param _owner The owner address of the contract.
     */
    constructor(TokenLabsLaunchpadFactory.SaleParams memory params, address _pairFactory, address _weth, address _owner) Ownable(_owner) {
        require(params.softcap < params.hardcap, "Softcap must not be greater than Hardcap");
        sale = Sale(params.seller, params.token, params.softcap, params.hardcap, params.startTime, params.endTime, params.tokensPerWei, params.tokensPerWeiListing, 0, params.limitPerAccountEnabled, params.limitPerAccount, params.referralRewardPercentage, params.rewardPool);
        additionalSaleDetails = AdditionalSaleDetails(params.pairingToken);
        pairFactory = _pairFactory;
        weth = _weth;
    }

    /**
     * @notice Allows users to buy tokens during the sale.
     * @param erc20Amount The amount of ERC20 tokens to buy.
     * @param referrer The address of the referrer.
     * @dev Users can buy tokens using ETH or another ERC20 token. Applies referral rewards if applicable.
     */
    function buyTokens(uint256 erc20Amount, address referrer) public payable nonReentrant {
        require(msg.sender == tx.origin, "Contracts are not allowed");
        require(block.timestamp >= sale.startTime && block.timestamp <= sale.endTime, "Sale is not ongoing");
        require(referrer != msg.sender, "You cannot refer yourself");
        require(!isListed, "Tokens were listed");
        require(!isCanceled, "Tokens Sale Canceled");

        uint256 purchaseAmount = 0;
        bool isETH = false;
        uint256 excessAmount = 0;

        if (additionalSaleDetails.pairingToken == address(0)) {
            require(msg.value > 0, "Amount must be greater than zero");
            isETH = true;
            purchaseAmount = msg.value;
        } else {
            require(erc20Amount > 0, "Amount must be greater than zero");
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
        
        if (excessAmount > 0 && isETH) {
            (bool success, ) = msg.sender.call{value: excessAmount}("");
            require(success, "Refund transfer failed");
        }

        if (excessAmount > 0 && !isETH) { IERC20(additionalSaleDetails.pairingToken).safeTransfer(msg.sender, excessAmount); }

        sale.collectedETH += purchaseAmount;

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
    function addLiquidityToDEX(uint256 tokenAmount, uint256 ethAmount, address tokenA, address pair, address pairingToken) private {

        if (pair == address(0)) {
            pair = IFactoryWithPair(pairFactory).createPair(tokenA, pairingToken);
        }

        IERC20(address(tokenA)).safeTransfer(pair, tokenAmount);

        if(pairingToken == weth){
            IWETH(weth).deposit{value: ethAmount}();
            assert(IWETH(weth).transfer(pair, ethAmount));
        }else{
            IERC20(address(pairingToken)).safeTransfer(pair, ethAmount);
        }     

        IPair(pair).mint(address(0));

    }

    /**
     * @notice Ends the token sale and adds liquidity to Uniswap V2.
     * @dev The sale can only be ended if the softcap is reached and the sale end conditions are met.
     */
    function endSale() external nonReentrant {
        require(msg.sender == tx.origin, "Contracts are not allowed");
        require(!isListed, "Tokens were listed");
        require(block.timestamp > sale.endTime || sale.collectedETH >= sale.hardcap, "Sale end conditions not met");
        if (sale.collectedETH < sale.softcap) return;

        address pairingToken = additionalSaleDetails.pairingToken;

        // Validate that the pair does not exist in the MagicSeaFactory contract
        IFactoryWithPair _pairFactory = IFactoryWithPair(pairFactory);

        if(pairingToken == address(0)){ pairingToken = weth; }
        
        address pair = _pairFactory.getPair(address(sale.token), pairingToken);
        
        if(pair != address(0)){

            IPair existingPair = IPair(pair);
            uint256 totalSupply = existingPair.totalSupply();
            if (totalSupply > 0) { isCanceled = true; }

            uint256 saleTokenPairBalance = IERC20(sale.token).balanceOf(pair);
            if (saleTokenPairBalance > 0) { isCanceled = true; }

            if(isCanceled){
                sale.endTime = block.timestamp;
                cancelMsg = "Pair Created";
                return;
            }

        }

        uint256 liquidityETH = sale.collectedETH > sale.hardcap ? sale.hardcap : sale.collectedETH;
        uint256 excessETH = sale.collectedETH > sale.hardcap ? sale.collectedETH - sale.hardcap : 0;

        ERC20Burnable token = ERC20Burnable(address(sale.token));

        if (sale.collectedETH >= sale.softcap && sale.collectedETH < sale.hardcap) {
            uint256 remainingEth = sale.hardcap > sale.collectedETH ? sale.hardcap - sale.collectedETH : 0;
            uint256 remainingTokens = (remainingEth * sale.tokensPerWeiListing) + (remainingEth * sale.tokensPerWei);
            
            if (remainingTokens > 0) { token.burn(remainingTokens); }
            
        }

        if (sale.rewardPool > 0) { token.burn(sale.rewardPool); }

        if (excessETH > 0) {
            if (additionalSaleDetails.pairingToken == address(0)) {
                (bool success, ) = sale.seller.call{value: excessETH}("");
                require(success, "Transfer failed");
            } else {
                IERC20(additionalSaleDetails.pairingToken).safeTransfer(sale.seller, excessETH);
            }
        }

        uint256 liquidityToken = liquidityETH * sale.tokensPerWeiListing;
        if (additionalSaleDetails.pairingToken == address(0)) {
            addLiquidityToDEX(liquidityToken, liquidityETH, address(sale.token), pair, pairingToken);
        } else {
            uint256 pairingTokenAmount = IERC20(additionalSaleDetails.pairingToken).balanceOf(address(this));
            addLiquidityToDEX(liquidityToken, pairingTokenAmount, address(sale.token), pair, pairingToken);
        }

        sale.endTime = block.timestamp;
        isListed = true;
    }

    /**
     * @notice Allows users to claim their purchased tokens or refunds after the sale ends.
     * @dev If the sale did not reach the softcap, users can claim refunds. Otherwise, they can claim their tokens.
     */
    function claim() external nonReentrant {
        require(msg.sender == tx.origin, "Contracts are not allowed");
        require(block.timestamp > sale.endTime, "Sale has not ended");
        
        if (sale.collectedETH < sale.softcap || isCanceled) {

            uint256 ethAmount = contributions[msg.sender];

            if (sale.seller == msg.sender) {

                uint256 remainingTokens = IERC20(address(sale.token)).balanceOf(address(this));

                require(remainingTokens > 0, "No Remaining Tokens");

                contributions[msg.sender] = 0;
                tokenAmounts[msg.sender] = 0;
                referralRewards[msg.sender] = 0;
                
                IERC20(address(sale.token)).safeTransfer(msg.sender, remainingTokens);

                if(ethAmount > 0){

                    if (additionalSaleDetails.pairingToken == address(0)) {
                        (bool success, ) = msg.sender.call{value: ethAmount}("");
                        require(success, "Transfer failed");
                    } else {
                        IERC20(additionalSaleDetails.pairingToken).safeTransfer(msg.sender, ethAmount);
                    }

                }

            } else {

                require(ethAmount > 0, "No amount available to claim");
                
                contributions[msg.sender] = 0;
                tokenAmounts[msg.sender] = 0;
                referralRewards[msg.sender] = 0;
                if (additionalSaleDetails.pairingToken == address(0)) {
                    (bool success, ) = msg.sender.call{value: ethAmount}("");
                    require(success, "Transfer failed");
                } else {
                    IERC20(additionalSaleDetails.pairingToken).safeTransfer(msg.sender, ethAmount);
                }
            }

        } else {
            require(isListed == true, "Sale has not ended");
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
        isCanceled = true;
        cancelMsg = "Sale Owner";
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
