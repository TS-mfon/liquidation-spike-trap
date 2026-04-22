# Liquidation Spike Trap

A Drosera trap that detects coordinated liquidation cascades by monitoring liquidation count and liquidated value spikes on lending protocols.

## Real-World Hack: Euler Finance ($197M Loss)

In March 2023, Euler Finance suffered a **$197 million** exploit that involved artificially triggering massive liquidation events. The attacker used flash loans and a vulnerability in the `donateToReserves` function to create bad debt positions that cascaded into a wave of liquidations. The attack resulted in over 50 liquidation events in rapid succession, each draining significant protocol value -- a pattern that would never occur under normal market conditions.

Coordinated liquidation cascades are a hallmark of many DeFi exploits. During the Mango Markets attack ($114M, October 2022) and the BonqDAO attack ($120M, February 2023), attackers also triggered unnatural liquidation spikes to extract value. Detecting an abnormal surge in liquidation volume early enough to pause the protocol could prevent the bulk of the damage.

## Attack Vector: Liquidation Cascades

Liquidation cascades follow this pattern:

1. **Attacker manipulates collateral prices** -- using oracle manipulation, flash loans, or large market sells to drive down the value of collateral assets.
2. **Positions become undercollateralized** -- the price drop pushes many borrowers below their liquidation threshold simultaneously.
3. **Attacker liquidates positions** -- calling the protocol's liquidation function repeatedly to seize collateral at a discount. The liquidation itself further depresses prices, triggering more liquidations.
4. **Cascade amplifies** -- each liquidation reduces protocol reserves, potentially making more positions liquidatable, creating a feedback loop.
5. **Protocol is drained** -- the cascading liquidations extract far more value than any organic market downturn would allow.

The key signal: an **abnormal spike** in both liquidation count and total liquidated value within a short block window.

## How the Trap Works

### Data Collection (`collect()`)

Every block, the trap reads two metrics from the monitored protocol (`0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2`):

- **`liquidationCount`** -- The cumulative total number of liquidations from `totalLiquidations()`
- **`liquidatedValue`** -- The cumulative total value liquidated (in 18-decimal notation) from `totalLiquidatedValue()`
- **`blockNumber`** -- The current block number

If either call reverts, the value defaults to zero.

### Trigger Logic (`shouldRespond()`)

The trap compares current and previous block data and triggers on two independent conditions:

**Condition 1: Liquidation Count Spike > 50**

```
new_liquidations = current_liquidationCount - previous_liquidationCount
TRIGGER if new_liquidations > 50
```

50 liquidations between consecutive samples is far beyond normal operation for any lending protocol. Even during major market events like the March 2020 "Black Thursday," liquidations were spread over many minutes and blocks.

**Condition 2: Liquidated Value Spike > $500K**

```
new_value = current_liquidatedValue - previous_liquidatedValue
TRIGGER if new_value > 500,000e18 ($500K)
```

A half-million dollar surge in liquidated value between blocks signals an organized attack rather than normal market-driven liquidations.

## Threshold Values

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| `MAX_LIQUIDATION_COUNT` | 50 | Normal protocols see single-digit liquidations per block even in volatile markets. 50+ liquidations in one sample window indicates a coordinated attack or cascading exploit. |
| `MAX_LIQUIDATED_VALUE` | 500,000e18 ($500K) | Organic liquidations are typically smaller and distributed. A $500K+ liquidated value spike in a single sample window is an extreme outlier that warrants immediate investigation. |
| `block_sample_size` | 10 | Covers 10 consecutive blocks, capturing attacks that may execute across multiple transactions in adjacent blocks. |

## Configuration (`drosera.toml`)

```toml
ethereum_rpc = "https://ethereum-hoodi-rpc.publicnode.com"
drosera_rpc = "https://relay.hoodi.drosera.io"
eth_chain_id = 560048
drosera_address = "0x91cB447BaFc6e0EA0F4Fe056F5a9b1F14bb06e5D"

[traps.liquidation_spike_trap]
path = "out/LiquidationSpikeTrap.sol/LiquidationSpikeTrap.json"
response_contract = "0x0000000000000000000000000000000000000000"
response_function = "emergencyPause()"
cooldown_period_blocks = 33
min_number_of_operators = 1
max_number_of_operators = 2
block_sample_size = 10
private_trap = false
whitelist = []
```

| Field | Description |
|-------|-------------|
| `ethereum_rpc` | RPC endpoint for the Ethereum chain being monitored (Hoodi testnet) |
| `drosera_rpc` | RPC endpoint for the Drosera relay network |
| `eth_chain_id` | Chain ID of the target network |
| `drosera_address` | Address of the Drosera protocol contract |
| `path` | Path to the compiled trap artifact (produced by `forge build`) |
| `response_contract` | Address of the contract to call when the trap triggers (set to zero address as placeholder) |
| `response_function` | Function signature to call on the response contract |
| `cooldown_period_blocks` | Minimum blocks between consecutive responses (prevents spam) |
| `min_number_of_operators` | Minimum Drosera operators required to reach consensus |
| `max_number_of_operators` | Maximum operators that can participate |
| `block_sample_size` | Number of consecutive blocks to collect data for |
| `private_trap` | Whether this trap is restricted to whitelisted operators |

## Architecture

```
+---------------------------------------------+
|         Monitored Lending Protocol           |
|         0x87870Bca3F3fD6335C3F...            |
|                                              |
|  totalLiquidations() -> liquidation count    |
|  totalLiquidatedValue() -> value liquidated  |
+----------------------+-----------------------+
                       |
                       | read each block
                       v
+----------------------+-----------------------+
|           LiquidationSpikeTrap               |
|                                              |
|  collect():                                  |
|  - liquidationCount (cumulative)             |
|  - liquidatedValue  (cumulative)             |
|  - blockNumber                               |
+----------------------+-----------------------+
                       |
                       v
+----------------------+-----------------------+
|           shouldRespond()                    |
|                                              |
|  Delta between blocks:                       |
|  - Count spike > 50?       --> TRIGGER       |
|  - Value spike > $500K?    --> TRIGGER       |
+----------------------+-----------------------+
                       |
                       | if triggered
                       v
            +----------+----------+
            |  Response Contract   |
            |  emergencyPause()    |
            +---------------------+
```

## Build

```bash
npm install && forge build
```

## Test

```bash
forge test
```

## Dry Run

```bash
drosera dryrun
```

## Deploy

```bash
export DROSERA_PRIVATE_KEY=<your-private-key>
drosera apply
```

## License

MIT
