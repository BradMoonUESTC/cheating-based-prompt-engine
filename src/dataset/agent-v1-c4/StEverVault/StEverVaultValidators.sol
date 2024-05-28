pragma solidity >=0.7.0 <0.9.0;
import "./StEverVaultBase.tsol";

/**
 * @title StEverVaultValidators
 *
 * @dev This abstract contract extends the {StEverVaultBase} contract with functions
 * that validate deposit and withdrawal requests.
 */
abstract contract StEverVaultValidators is StEverVaultBase {
    /**
     * @dev See {IStEverVault-validateDepositRequest}.
     *
     * @param _depositConfigs The mapping of deposit configurations.
     * @return ValidationResult[] An array of validation results.
     *
     * **Preconditions**:
     *
     *  - The caller must be the owner.
     *  - The value of the message must be greater than or equal to the sum of DEPLOY_CLUSTER_VALUE and MIN_CALL_MSG_VALUE.
     *
     * **Postconditions**:
     *
     *  - A new cluster is created and added to the clusterPools.
     *  - The ClusterCreated event is emitted.
     */
    function validateDepositRequest(mapping (address => DepositConfig) _depositConfigs) override public view returns(ValidationResult[]) {
        ValidationResult[] validationResults;

        uint128 totalRequiredBalance;
        uint128 totalFee;

        for (uint256 i = 0; !_depositConfigs.empty(); i++) {

            (address strategy, DepositConfig depositConfig) = _depositConfigs.delMin().get();

            if (!strategies.exists(strategy)) {
                validationResults.push(ValidationResult(strategy, ErrorCodes.STRATEGY_NOT_EXISTS));
            }

            if (depositConfig.amount < minStrategyDepositValue) {
                validationResults.push(ValidationResult(strategy, ErrorCodes.BAD_DEPOSIT_TO_STRATEGY_VALUE));
            }

            totalFee += depositConfig.fee;
            uint128 valueToSend = depositConfig.amount + depositConfig.fee;
            totalRequiredBalance += valueToSend;

            if (!canTransferValue(totalRequiredBalance)) {
                validationResults.push(ValidationResult(strategy, ErrorCodes.NOT_ENOUGH_VALUE_TO_DEPOSIT));
            }

            if (totalAssets < totalFee) {
                validationResults.push(ValidationResult(strategy, ErrorCodes.NOT_ENOUGH_TOTAL_ASSETS));
            }

            if (!isStrategyInInitialState(strategy, false)) {
                validationResults.push(ValidationResult(strategy, ErrorCodes.STRATEGY_NOT_IN_INITIAL_STATE));
            }
        }
        return validationResults;
    }

    /**
     * @dev Validates withdraw requsts.
     *
     * @param _withdrawConfig The mapping of strategy address to withdraw config.
     * @return ValidationResult[] An array of validation results.
     *
     * **Preconditions**:
     *
     *  - The caller must be the owner.
     *  - The value of the message must be greater than or equal to the sum of DEPLOY_CLUSTER_VALUE and MIN_CALL_MSG_VALUE.
     *
     * **Postconditions**:
     *
     *  - A new cluster is created and added to the clusterPools.
     *  - The ClusterCreated event is emitted.
     */
    function validateWithdrawFromStrategiesRequest(mapping (address => WithdrawConfig) _withdrawConfig) override public view returns (ValidationResult[]) {
        ValidationResult[] validationResults;

        uint128 totalRequiredBalance;

        for (uint256 i = 0; !_withdrawConfig.empty(); i++) {
            (address strategy ,WithdrawConfig config) = _withdrawConfig.delMin().get();

            if(config.amount < minStrategyWithdrawValue) {
                validationResults.push(ValidationResult(strategy, ErrorCodes.BAD_WITHDRAW_FROM_STRATEGY_VALUE));
            }

            if(!strategies.exists(strategy)) {
                validationResults.push(ValidationResult(strategy, ErrorCodes.STRATEGY_NOT_EXISTS));
            }
            totalRequiredBalance += config.fee;
            if(!canTransferValue(totalRequiredBalance)) {
                validationResults.push(ValidationResult(strategy, ErrorCodes.NOT_ENOUGH_VALUE_TO_WITHDRAW));
            }

            if (totalAssets < totalRequiredBalance) {
                validationResults.push(ValidationResult(strategy, ErrorCodes.NOT_ENOUGH_TOTAL_ASSETS));
            }

            if(!isStrategyInInitialState(strategy, true)) {
                validationResults.push(ValidationResult(strategy, ErrorCodes.STRATEGY_NOT_IN_INITIAL_STATE));
            }
        }
        return validationResults;
    }

}