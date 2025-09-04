// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @title SecurityLib
/// @notice Advanced security library for EigenVault production hardening
library SecurityLib {
    /// @notice Security configuration
    struct SecurityConfig {
        uint256 maxOrderSize;
        uint256 maxPoolExposure;
        uint256 maxSlippageBps;
        uint256 emergencyPauseThreshold;
        bool emergencyPaused;
        uint256 lastSecurityCheck;
        uint256 securityCheckInterval;
    }

    /// @notice Risk assessment result
    struct RiskAssessment {
        bool isHighRisk;
        uint256 riskScore;
        string riskReason;
        bool shouldExecute;
        uint256 recommendedSlippage;
    }

    /// @notice Security events
    event EmergencyPauseActivated(string reason, uint256 timestamp);
    event EmergencyPauseDeactivated(uint256 timestamp);
    event SecurityCheckPerformed(uint256 riskScore, bool passed);
    event AnomalyDetected(string anomalyType, uint256 severity, string details);

    /// @notice Perform comprehensive security check
    /// @param config Security configuration
    /// @param orderSize Order size to check
    /// @param poolExposure Current pool exposure
    /// @param slippage Requested slippage
    /// @return assessment Risk assessment result
    function performSecurityCheck(
        SecurityConfig storage config,
        uint256 orderSize,
        uint256 poolExposure,
        uint256 slippage
    ) internal returns (RiskAssessment memory assessment) {
        // Check if emergency pause is active
        if (config.emergencyPaused) {
            return RiskAssessment({
                isHighRisk: true,
                riskScore: 100,
                riskReason: "Emergency pause active",
                shouldExecute: false,
                recommendedSlippage: 0
            });
        }

        // Check order size limits
        if (orderSize > config.maxOrderSize) {
            return RiskAssessment({
                isHighRisk: true,
                riskScore: 85,
                riskReason: "Order size exceeds maximum",
                shouldExecute: false,
                recommendedSlippage: 0
            });
        }

        // Check pool exposure limits
        if (poolExposure > config.maxPoolExposure) {
            return RiskAssessment({
                isHighRisk: true,
                riskScore: 90,
                riskReason: "Pool exposure limit exceeded",
                shouldExecute: false,
                recommendedSlippage: 0
            });
        }

        // Check slippage limits
        if (slippage > config.maxSlippageBps) {
            return RiskAssessment({
                isHighRisk: true,
                riskScore: 75,
                riskReason: "Slippage exceeds maximum",
                shouldExecute: false,
                recommendedSlippage: config.maxSlippageBps
            });
        }

        // Calculate risk score based on multiple factors
        uint256 riskScore = _calculateRiskScore(orderSize, poolExposure, slippage, config);
        
        // Determine if execution should proceed
        bool shouldExecute = riskScore < 50;
        
        // Calculate recommended slippage
        uint256 recommendedSlippage = _calculateRecommendedSlippage(riskScore, slippage, config);

        assessment = RiskAssessment({
            isHighRisk: riskScore >= 70,
            riskScore: riskScore,
            riskReason: _getRiskReason(riskScore),
            shouldExecute: shouldExecute,
            recommendedSlippage: recommendedSlippage
        });

        // Update last security check
        config.lastSecurityCheck = block.timestamp;

        // Emit security check event
        emit SecurityCheckPerformed(riskScore, shouldExecute);

        return assessment;
    }

    /// @notice Calculate comprehensive risk score
    /// @param orderSize Order size
    /// @param poolExposure Pool exposure
    /// @param slippage Requested slippage
    /// @param config Security configuration
    /// @return riskScore Calculated risk score (0-100)
    function _calculateRiskScore(
        uint256 orderSize,
        uint256 poolExposure,
        uint256 slippage,
        SecurityConfig storage config
    ) internal view returns (uint256 riskScore) {
        // Size risk (0-30 points)
        uint256 sizeRisk = (orderSize * 30) / config.maxOrderSize;
        if (sizeRisk > 30) sizeRisk = 30;

        // Exposure risk (0-30 points)
        uint256 exposureRisk = (poolExposure * 30) / config.maxPoolExposure;
        if (exposureRisk > 30) exposureRisk = 30;

        // Slippage risk (0-25 points)
        uint256 slippageRisk = (slippage * 25) / config.maxSlippageBps;
        if (slippageRisk > 25) slippageRisk = 25;

        // Time-based risk (0-15 points)
        uint256 timeRisk = 0;
        if (config.lastSecurityCheck > 0) {
            uint256 timeSinceLastCheck = block.timestamp - config.lastSecurityCheck;
            if (timeSinceLastCheck > config.securityCheckInterval) {
                timeRisk = 15;
            }
        }

        riskScore = sizeRisk + exposureRisk + slippageRisk + timeRisk;
        
        // Cap at 100
        if (riskScore > 100) riskScore = 100;
    }

    /// @notice Calculate recommended slippage based on risk
    /// @param riskScore Current risk score
    /// @param requestedSlippage Requested slippage
    /// @param config Security configuration
    /// @return recommendedSlippage Recommended slippage value
    function _calculateRecommendedSlippage(
        uint256 riskScore,
        uint256 requestedSlippage,
        SecurityConfig storage config
    ) internal view returns (uint256 recommendedSlippage) {
        if (riskScore < 30) {
            // Low risk - allow requested slippage
            recommendedSlippage = requestedSlippage;
        } else if (riskScore < 60) {
            // Medium risk - reduce slippage
            recommendedSlippage = (requestedSlippage * 80) / 100;
        } else {
            // High risk - use maximum allowed
            recommendedSlippage = config.maxSlippageBps;
        }

        // Ensure within limits
        if (recommendedSlippage > config.maxSlippageBps) {
            recommendedSlippage = config.maxSlippageBps;
        }
    }

    /// @notice Get risk reason based on score
    /// @param riskScore Risk score
    /// @return reason Human-readable risk reason
    function _getRiskReason(uint256 riskScore) internal pure returns (string memory reason) {
        if (riskScore < 20) {
            return "Low risk - safe to execute";
        } else if (riskScore < 40) {
            return "Moderate risk - proceed with caution";
        } else if (riskScore < 60) {
            return "Elevated risk - consider reducing size/slippage";
        } else if (riskScore < 80) {
            return "High risk - execution not recommended";
        } else {
            return "Critical risk - execution blocked";
        }
    }

    /// @notice Activate emergency pause
    /// @param config Security configuration
    /// @param reason Reason for emergency pause
    function activateEmergencyPause(
        SecurityConfig storage config,
        string memory reason
    ) internal {
        config.emergencyPaused = true;
        emit EmergencyPauseActivated(reason, block.timestamp);
    }

    /// @notice Deactivate emergency pause
    /// @param config Security configuration
    function deactivateEmergencyPause(SecurityConfig storage config) internal {
        config.emergencyPaused = false;
        emit EmergencyPauseDeactivated(block.timestamp);
    }

    /// @notice Detect anomalies in trading patterns
    /// @param orderSize Order size
    /// @param poolExposure Pool exposure
    /// @param recentOrders Recent order history
    /// @return hasAnomaly Whether an anomaly was detected
    /// @return anomalyType Type of anomaly detected
    function detectAnomalies(
        uint256 orderSize,
        uint256 poolExposure,
        uint256[] memory recentOrders
    ) internal pure returns (bool hasAnomaly, string memory anomalyType) {
        // Check for sudden large orders
        if (orderSize > 1000e18) {
            return (true, "Large order anomaly");
        }

        // Check for rapid exposure increase
        if (poolExposure > 10000e18) {
            return (true, "High exposure anomaly");
        }

        // Check for unusual order patterns
        if (recentOrders.length > 10) {
            uint256 totalVolume = 0;
            for (uint256 i = 0; i < recentOrders.length; i++) {
                totalVolume += recentOrders[i];
            }
            
            if (totalVolume > 50000e18) {
                return (true, "Volume spike anomaly");
            }
        }

        return (false, "");
    }

    /// @notice Validate security parameters
    /// @param config Security configuration
    /// @return isValid Whether the configuration is valid
    function validateSecurityConfig(
        SecurityConfig memory config
    ) internal pure returns (bool isValid) {
        return (
            config.maxOrderSize > 0 &&
            config.maxPoolExposure > 0 &&
            config.maxSlippageBps > 0 &&
            config.maxSlippageBps <= 1000 && // Max 10%
            config.securityCheckInterval > 0
        );
    }

    /// @notice Get security status summary
    /// @param config Security configuration
    /// @return isPaused Whether emergency pause is active
    /// @return lastCheck Last security check timestamp
    /// @return checkInterval Security check interval
    /// @return needsCheck Whether security check is needed
    function getSecurityStatus(
        SecurityConfig storage config
    ) internal view returns (
        bool isPaused,
        uint256 lastCheck,
        uint256 checkInterval,
        bool needsCheck
    ) {
        isPaused = config.emergencyPaused;
        lastCheck = config.lastSecurityCheck;
        checkInterval = config.securityCheckInterval;
        needsCheck = block.timestamp > lastCheck + checkInterval;
    }
} 