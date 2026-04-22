// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import {Trap} from "drosera-contracts/Trap.sol";

/// @title LiquidationSpikeTrap
/// @notice Detects coordinated liquidation cascades (Euler Finance style - $197M)
/// @dev Monitors liquidation metrics and triggers on abnormal spikes

interface ILiquidationTracker {
    function totalLiquidations() external view returns (uint256);
    function totalLiquidatedValue() external view returns (uint256);
}

struct CollectOutput {
    uint256 liquidationCount;
    uint256 liquidatedValue;
    uint256 blockNumber;
}

contract LiquidationSpikeTrap is Trap {
    address public constant PROTOCOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    uint256 public constant MAX_LIQUIDATION_COUNT = 50;
    uint256 public constant MAX_LIQUIDATED_VALUE = 500_000e18; // $500K

    constructor() {}

    function collect() external view override returns (bytes memory) {
        uint256 liqCount;
        uint256 liqValue;

        try ILiquidationTracker(PROTOCOL).totalLiquidations() returns (uint256 count) {
            liqCount = count;
        } catch {
            liqCount = 0;
        }

        try ILiquidationTracker(PROTOCOL).totalLiquidatedValue() returns (uint256 value) {
            liqValue = value;
        } catch {
            liqValue = 0;
        }

        return abi.encode(CollectOutput({
            liquidationCount: liqCount,
            liquidatedValue: liqValue,
            blockNumber: block.number
        }));
    }

    function shouldRespond(
        bytes[] calldata data
    ) external pure override returns (bool, bytes memory) {
        if (data.length < 2) return (false, bytes(""));

        CollectOutput memory current = abi.decode(data[0], (CollectOutput));
        CollectOutput memory previous = abi.decode(data[1], (CollectOutput));

        // Check liquidation count spike
        if (current.liquidationCount > previous.liquidationCount) {
            uint256 newLiquidations = current.liquidationCount - previous.liquidationCount;
            if (newLiquidations > MAX_LIQUIDATION_COUNT) {
                return (true, bytes("Liquidation cascade detected: count spike"));
            }
        }

        // Check liquidated value spike
        if (current.liquidatedValue > previous.liquidatedValue) {
            uint256 newValue = current.liquidatedValue - previous.liquidatedValue;
            if (newValue > MAX_LIQUIDATED_VALUE) {
                return (true, bytes("Liquidation cascade detected: value spike"));
            }
        }

        return (false, bytes(""));
    }
}
