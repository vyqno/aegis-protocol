# AEGIS Protocol

> AI-Enhanced Guardian for Intelligent Staking — Autonomous DeFi Position Manager

AEGIS Protocol is an institutional-grade DeFi position manager that uses **Chainlink CRE** (Chainlink Runtime Environment) to autonomously optimize yields, monitor risk in real-time, and manage vault operations with sybil-resistant access control via World ID.

Built for the **Chainlink Convergence Hackathon 2026** (Feb 6 - Mar 1).

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   CRE Workflows                      │
│  ┌──────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  Yield   │  │    Risk      │  │    Vault     │  │
│  │ Scanner  │  │  Sentinel    │  │   Manager    │  │
│  │ (Cron)   │  │ (Log Trigger)│  │ (HTTP Trig.) │  │
│  └────┬─────┘  └──────┬───────┘  └──────┬───────┘  │
│       │               │                  │           │
│  ┌────▼───────────────▼──────────────────▼───────┐  │
│  │          Groq AI (NodeMode + Consensus)        │  │
│  └────────────────────┬──────────────────────────┘  │
└───────────────────────┼─────────────────────────────┘
                        │ Signed CRE Reports
┌───────────────────────▼─────────────────────────────┐
│              Smart Contracts (Foundry)                │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │
│  │ AegisVault  │  │RiskRegistry │  │StrategyRouter│ │
│  │ (IReceiver) │  │(CircuitBrkr)│  │ (CCIP+1inch) │ │
│  └──────┬──────┘  └─────────────┘  └─────────────┘ │
│  ┌──────▼──────┐                                     │
│  │WorldIdGate  │                                     │
│  │(Sybil Proof)│                                     │
│  └─────────────┘                                     │
│  Chains: Ethereum Sepolia | Base Sepolia             │
└─────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────┐
│            Frontend (Next.js 14 + Thirdweb)          │
│  Dashboard | Monitor | History | Admin               │
└─────────────────────────────────────────────────────┘
```

## Chainlink Services Used

| Service | Integration | Files |
|---------|-------------|-------|
| **CRE Workflows** | 3 autonomous workflows (Cron, Log, HTTP triggers) | [`yield-scanner/`](./yield-scanner/), [`risk-sentinel/`](./risk-sentinel/), [`vault-manager/`](./vault-manager/) |
| **CCIP** | Cross-chain capital routing (Sepolia ↔ Base Sepolia) | [`StrategyRouter.sol`](./contracts/src/core/StrategyRouter.sol) |
| **Data Feeds** | On-chain vault state reads in CRE workflows | [`cronCallback.ts`](./yield-scanner/cronCallback.ts), [`logCallback.ts`](./risk-sentinel/logCallback.ts) |
| **AI Integration** | Groq Cloud (llama-3.3-70b) via CRE NodeMode + consensus | [`groqAi.ts`](./yield-scanner/groqAi.ts), [`groqRisk.ts`](./risk-sentinel/groqRisk.ts) |
| **World ID** | Sybil-resistant vault access (one human = one account) | [`WorldIdGate.sol`](./contracts/src/access/WorldIdGate.sol) |

## Tech Stack

- **Smart Contracts**: Solidity 0.8.24 + Foundry (4 contracts, 223 tests)
- **CRE Workflows**: TypeScript + `@chainlink/cre-sdk` v1.0.1
- **AI**: Groq Cloud (llama-3.3-70b-versatile) with consensus aggregation
- **Frontend**: Next.js 14 (App Router) + Thirdweb SDK v5 + Tailwind CSS
- **Cross-Chain**: Chainlink CCIP (Sepolia ↔ Base Sepolia)
- **Identity**: World ID (Orb verification level)
- **Charts**: Recharts (SVG-based, XSS-safe)

## CRE Workflows

### 1. Yield Scanner (`yield-scanner/`)
- **Trigger**: Cron (every 5 minutes)
- **Action**: Reads vault state → Queries Groq AI for yield analysis → Writes signed report (prefix `0x01`) to AegisVault
- **AI Model**: llama-3.3-70b with consensus aggregation

### 2. Risk Sentinel (`risk-sentinel/`)
- **Trigger**: EVM Log (`RiskAlertCreated` event from RiskRegistry)
- **Action**: Decodes risk event → Idempotency check → Groq AI risk assessment → Activates circuit breaker if score > 7000 bps
- **Safety**: HOLD default fallback on all errors, rate-limited circuit breaker (3/hour)

### 3. Vault Manager (`vault-manager/`)
- **Trigger**: HTTP (frontend calls for deposit/withdraw)
- **Action**: Zod payload validation → On-chain preflight checks → Writes vault operation report (prefix `0x03`)
- **Security**: Address checksumming, World ID proof validation, circuit breaker check

## Smart Contracts

| Contract | Size | Tests | Key Features |
|----------|------|-------|-------------|
| **AegisVault** | 9.6 KB | 39 unit + 8 fuzz + 5 invariant | Virtual shares (anti-inflation), circuit breaker, CRE report routing, World ID gated |
| **RiskRegistry** | 5.5 KB | 40 unit + 8 fuzz | Rate-limited CB (3/hr), auto-deactivation (72h), threshold bounds |
| **StrategyRouter** | 9.8 KB | 27 unit + 7 fuzz | CCIP source+sender validation, cumulative transfer limits, nonce tracking |
| **WorldIdGate** | - | 37 unit | Signal==msg.sender anti-front-running, TTL staleness, vault-mediated calls |

**Total: 223 tests (unit + fuzz + integration + invariant) — all passing**

## Security Highlights

- Virtual shares offset prevents first-depositor inflation attack
- Circuit breaker rate-limited to 3 activations per hour with 72h auto-deactivation
- Workflow-to-prefix binding prevents unauthorized report types
- Cross-chain replay protection via `block.chainid` in report dedup
- CCIP source chain + sender validation on all received messages
- AI prompt injection defense in all system prompts ("UNTRUSTED data" labeling)
- HOLD default fallback — AI errors never trigger unsafe actions
- Deploy-paused pattern: `initialSetupComplete` flag prevents premature interaction
- No `dangerouslySetInnerHTML` in frontend (React auto-escaping only)
- Transaction simulation before every submit

## Quick Start

### Prerequisites
- Node.js >= 18, pnpm >= 8
- Foundry (forge, cast)
- CRE CLI (`cre`)

### Smart Contracts
```bash
cd contracts
forge build          # Compile
forge test           # Run 223 tests
forge test -vvvv     # Verbose output
```

### CRE Workflows
```bash
# Simulate (from project root)
cre workflow simulate yield-scanner
cre workflow simulate risk-sentinel
cre workflow simulate vault-manager
```

### Frontend
```bash
cd frontend
cp .env.local.example .env.local  # Add your Thirdweb client ID
pnpm install
pnpm dev             # http://localhost:3000
pnpm build           # Production build
```

### Deployment
```bash
# Deploy contracts (requires DEPLOYER_PRIVATE_KEY in .env)
cd contracts
source .env && forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC --broadcast --verify

# Deploy CRE workflows
cre workflow deploy yield-scanner --target staging-settings
cre workflow deploy risk-sentinel --target staging-settings
cre workflow deploy vault-manager --target staging-settings
```

## Deployed Contracts

| Contract | Network | Address |
|----------|---------|---------|
| AegisVault | Sepolia | _Deploy pending_ |
| RiskRegistry | Sepolia | _Deploy pending_ |
| StrategyRouter | Sepolia | _Deploy pending_ |
| WorldIdGate | Sepolia | _Deploy pending_ |

## Demo Video

_Recording pending — see [`docs/demo-script.md`](./docs/demo-script.md) for the planned walkthrough._

## Project Structure

```
chainlink/
├── contracts/               # Solidity smart contracts (Foundry)
│   ├── src/core/           # AegisVault, RiskRegistry, StrategyRouter
│   ├── src/access/         # WorldIdGate
│   ├── src/interfaces/     # IAegisVault, IRiskRegistry, etc.
│   ├── src/libraries/      # RiskMath, Errors, Events
│   ├── test/               # 223 tests (unit, fuzz, integration, invariant)
│   └── script/             # Deployment scripts
├── yield-scanner/          # CRE Workflow 1 (Cron trigger)
├── risk-sentinel/          # CRE Workflow 2 (Log trigger)
├── vault-manager/          # CRE Workflow 3 (HTTP trigger)
├── frontend/               # Next.js 14 + Thirdweb SDK v5
│   ├── app/               # Pages (dashboard, monitor, history, admin)
│   ├── components/        # UI components
│   ├── hooks/             # React hooks for contract interaction
│   └── lib/               # Thirdweb client, chains, ABIs
├── scripts/                # Validation and deployment helpers
├── project.yaml            # CRE project configuration
└── phases/                 # Development phase documentation
```

## License

MIT
