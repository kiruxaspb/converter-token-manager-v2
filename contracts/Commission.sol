// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract Commission is Ownable {

    uint256 private constant ONE_HUNDRED = 100;
    uint256 private immutable FIXED_NATIVE_TOKEN_COMMISSION_LIMIT;
    
    enum CommissionType {
        PercentageTokens, // commission in percentage tokens
        FixTokens, // commission in fix value of tokens
        NativeCurrency // commission in native currency
    }

    CommissionSettings public commissionSettings;
    struct CommissionSettings {
        uint8 convertTokenPercentage; // percentage for commission in tokens
        bool commissionIsEnabled; // activate/deactivate commission
        uint256 fixedNativeTokenCommission; // fixed value of commission in native tokens
        uint256 fixedTokenCommission; // fixed value of commission in tokens
        address payable commissionReceiver; // commission receiver
        CommissionType commissionType; // global type of commission
    }
    
    // Address of token contract for  
    address internal _token;

    bytes4 private constant TRANSFERFROM_SELECTOR = bytes4(keccak256("transferFrom(address,address,uint256)"));
    bytes4 private constant MINT_SELECTOR = bytes4(keccak256("mint(address,uint256)"));
    bytes4 private constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    event UpdateReceiver(address indexed previousReceiver, address indexed newReceiver);
    event NativeCurrencyCommissionClaim(uint256 claimedBalance, uint256 time);
    event UpdateCommissionConfiguration(
        uint256 updateTimestamp,
        bool commissionIsEnabled,
        uint8 convertTokenPercentage,
        uint256 commissionType,
        uint256 fixedTokenCommission,
        uint256 fixedNativeTokenCommission,
        address newCommissionReceiver
    );
    event UpdateTypeCommission(
        uint256 updateTimestamp,
        uint8 convertTokenPercentage,
        uint256 commissionType,
        uint256 fixedTokenCommission,
        uint256 fixedNativeTokenCommission   
    );
    event UpdateFixedNativeTokenCommission(uint256 updateTime, uint256 newFixedNativeTokenCommission);
    event UpdatePercentageTokensCommission(uint256 updateTime, uint8 newPercentage);
    event UpdateFixedTokenCommission(uint256 updateTime, uint256 newFixedTokenCommisssion);
    event UpdateTokenTypeCommission(uint256 updateTime, uint256 newTypeTokenCommission);

    modifier checkPercentageLimit(uint8 amount) {
        require(amount <= 100, "Violates percentage limits");
        _;
    }

    constructor(
        bool commissionIsEnabled,
        uint256 commissionType,
        uint256 fixedNativeTokenCommission,
        uint256 fixedNativeTokenCommissionLimit,
        uint256 fixedTokenCommission,
        uint8 convertTokenPercentage,
        address commissionReceiver
    )
        Ownable()
        checkPercentageLimit(convertTokenPercentage)
    {
        commissionSettings.commissionReceiver = payable(commissionReceiver);
        FIXED_NATIVE_TOKEN_COMMISSION_LIMIT = fixedNativeTokenCommissionLimit;

        if (!commissionIsEnabled) return;

        commissionSettings.commissionIsEnabled = true;

        _updateCommissionSettings(
            convertTokenPercentage,
            commissionType,
            fixedTokenCommission, 
            fixedNativeTokenCommission
        );

        emit UpdateCommissionConfiguration(
            block.timestamp,
            commissionIsEnabled,
            convertTokenPercentage,
            commissionType,
            fixedTokenCommission,
            fixedNativeTokenCommission,
            commissionReceiver
        );
    }

    function _checkPayedCommissionInNative() internal {
        require(
            msg.value == commissionSettings.fixedNativeTokenCommission,
            "Inaccurate payed commission in native token"
        );
    }

    function _takeCommissionInTokenOutput(uint256 amount) internal returns (uint256) {
        uint256 commissionAmount = _calculateCommissionInToken(amount);

        if (commissionAmount > 0) {
            (bool success, ) = _token.call(
                abi.encodeWithSelector(
                    TRANSFERFROM_SELECTOR,
                    _msgSender(),
                    commissionSettings.commissionReceiver,
                    commissionAmount
                )
            );

            require(success, "Commission transfer failed");
        }
        return commissionAmount;
    }

    function _takeCommissionInTokenInput(uint256 amount) internal returns (uint256) {
        uint256 commissionAmount = _calculateCommissionInToken(amount);

        // transfer minted commission to receiver
        if (commissionAmount > 0) {
            (bool success, ) = _token.call(
                abi.encodeWithSelector(
                    TRANSFER_SELECTOR,
                    commissionSettings.commissionReceiver,
                    commissionAmount
                )
            );

            require(success, "Commission transfer failed");
        }
        return commissionAmount;
    }

    function _calculateCommissionInToken(uint256 amount) internal view returns (uint256) {
        if (commissionSettings.commissionType == CommissionType.PercentageTokens) {
            return amount * uint256(commissionSettings.convertTokenPercentage) / ONE_HUNDRED;
        } 
        // If commissionType is not PercentageTokens, it's FixTokens 
        return commissionSettings.fixedTokenCommission;
    }

    function disableCommission() external onlyOwner {
        commissionSettings.commissionIsEnabled = false;
    }

    function updateCommissionConfiguration(
        bool commissionIsEnabled,
        uint8 newConvertTokenPercentage,
        uint256 newCommissionType,
        uint256 newFixedTokenCommission,
        uint256 newFixedNativeTokenCommission
    )
        external onlyOwner
        checkPercentageLimit(newConvertTokenPercentage)
    {
        if (!commissionSettings.commissionIsEnabled)
            commissionSettings.commissionIsEnabled = true;

        _updateCommissionSettings(
            newConvertTokenPercentage,
            newCommissionType,
            newFixedTokenCommission, 
            newFixedNativeTokenCommission
        );

        emit UpdateCommissionConfiguration(
            block.timestamp,
            commissionIsEnabled,
            newConvertTokenPercentage,
            newCommissionType,
            newFixedTokenCommission,
            newFixedNativeTokenCommission,
            commissionSettings.commissionReceiver
        );
    }

    function updateFixedNativeTokenCommission(
        uint256 newFixedNativeTokenCommission
    )
        external
        onlyOwner
    {
        require(
            commissionSettings.commissionIsEnabled && 
            commissionSettings.commissionType == CommissionType.NativeCurrency,
            "At the current moment commission disabled or active a different commission type"
        );
        require(newFixedNativeTokenCommission > 0, "Zero value of new commission in native token");
        
        _checkFixedNativeTokenLimit(newFixedNativeTokenCommission);
        commissionSettings.fixedNativeTokenCommission = newFixedNativeTokenCommission;
      
        emit UpdateFixedNativeTokenCommission(block.timestamp, newFixedNativeTokenCommission);
    }

    function updateTokenTypeCommission(
        uint8 newPercentage, 
        uint256 newTokenTypeCommission,
        uint256 newFixedTokenCommisssion
    )
        external
        onlyOwner
        checkPercentageLimit(newPercentage)
    {
        require(
            commissionSettings.commissionIsEnabled &&
            commissionSettings.commissionType != CommissionType.NativeCurrency &&
            newTokenTypeCommission != uint256(commissionSettings.commissionType),
            "Update type token commission unavailable"
        );

        emit UpdateTokenTypeCommission(block.timestamp, newTokenTypeCommission);
        
        if(newTokenTypeCommission == 0) {
            commissionSettings.convertTokenPercentage = newPercentage;
            commissionSettings.commissionType = CommissionType.PercentageTokens;

            emit UpdatePercentageTokensCommission(block.timestamp, newPercentage);
        } else {
            require(
                newFixedTokenCommisssion > 0,
                "The fixed value of the commission in tokens cannot be equal to zero"
            );

            commissionSettings.fixedTokenCommission = newFixedTokenCommisssion;
            commissionSettings.commissionType = CommissionType.FixTokens;

            emit UpdateFixedTokenCommission(block.timestamp, newFixedTokenCommisssion);
        }
    }

    function updatePercentageTokensCommission(uint8 newPercentage)
        external
        onlyOwner
        checkPercentageLimit(newPercentage)
    {
        require(
            commissionSettings.commissionIsEnabled && 
            commissionSettings.commissionType == CommissionType.PercentageTokens,
            "At the current moment commission disabled or active a different commission type"
        );

        if (newPercentage > 0) commissionSettings.convertTokenPercentage = newPercentage;

        emit UpdatePercentageTokensCommission(block.timestamp, newPercentage);
    }

    function updateFixedTokensCommission(uint256 newFixedTokenCommisssion)
        external
        onlyOwner
    {
        require(
            commissionSettings.commissionIsEnabled && 
            commissionSettings.commissionType == CommissionType.FixTokens,
            "At the current moment commission disabled or active a different commission type"
        );

        if (newFixedTokenCommisssion > 0) commissionSettings.fixedTokenCommission = newFixedTokenCommisssion;

        emit UpdateFixedTokenCommission(block.timestamp, newFixedTokenCommisssion);
    }

    function setCommissionReceiver(address newCommissionReceiver) external onlyOwner {
        require(newCommissionReceiver != address(0));
    
        emit UpdateReceiver(commissionSettings.commissionReceiver, newCommissionReceiver);

        commissionSettings.commissionReceiver = payable(newCommissionReceiver);
    }

    function claimNativeCurrencyCommission() external onlyOwner {
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0);

        (bool success,) = (commissionSettings.commissionReceiver).call{value: contractBalance}("");
        require(success, "Commission claim failed");
        
        emit NativeCurrencyCommissionClaim(contractBalance, block.timestamp);
    }

    function getCommissionReceiverAddress() external view returns(address) {
        return commissionSettings.commissionReceiver;
    }

    function getCommissionSettings() public view returns (
        bool commissionIsEnabled,
        uint256 fixedTokenCommission,
        uint8 convertTokenPercentage,
        uint256 tokenTypeCommission,
        uint256 fixedNativeTokenCommission,
        address payable commissionReceiver,
        address token
    ) {
        return (
            commissionSettings.commissionIsEnabled,
            uint256(commissionSettings.commissionType),
            commissionSettings.convertTokenPercentage,
            commissionSettings.fixedTokenCommission,
            commissionSettings.fixedNativeTokenCommission,
            commissionSettings.commissionReceiver,
            _token
        );
    }

    function _updateCommissionSettings(
        uint8 convertTokenPercentage,
        uint256 commissionType,
        uint256 fixedTokenCommission,
        uint256 fixedNativeTokenCommission 
        ) 
        private 
    {
            
        if (commissionType == 0 && convertTokenPercentage > 0) {
            commissionSettings.convertTokenPercentage = convertTokenPercentage;
            commissionSettings.commissionType = CommissionType.PercentageTokens;
        } else if(commissionType == 1) {
            commissionSettings.fixedTokenCommission = fixedTokenCommission;
            commissionSettings.commissionType = CommissionType.FixTokens;
        } else if (fixedNativeTokenCommission > 0) {
            _checkFixedNativeTokenLimit(fixedNativeTokenCommission);
            commissionSettings.fixedNativeTokenCommission = fixedNativeTokenCommission;
            commissionSettings.commissionType = CommissionType.NativeCurrency;
            emit UpdateTypeCommission(
                block.timestamp,
                convertTokenPercentage,
                commissionType,
                fixedTokenCommission,
                fixedNativeTokenCommission   
            );
        }
    }

    function _checkFixedNativeTokenLimit(uint256 fixedNativeTokenCommission) private view {
        require(
            fixedNativeTokenCommission <= FIXED_NATIVE_TOKEN_COMMISSION_LIMIT, 
            "Violates native token commission limit"
        );
    }

}
