# GameBuild Ad Spot Contracts

Smart contracts powering a simple advertising spot NFT and marketplace system.

## Overview
This repo contains two primary Solidity contracts:
- `AdSpotNFT.sol`: ERC-721 token representing an advertising spot. Each token can be time-rented (queue style) via a lightweight draft interface `IERC809` (user/expires/pricePerSecond). Rental payment accounting is externalized to the marketplace for protocol fee sharing.
- `AdSpotMarket.sol`: Marketplace supporting fixed-price listings, simple English auctions, fee distribution, and forwarding of rental payments with protocol fee extraction.

Auxiliary:
- `IERC809.sol`: Draft interface enabling time-based rental semantics (`userOf`, `userExpires`, `pricePerSecond`, and `rent` events/functions).


## Features
- Mint new ad spot NFTs (owner-only)
- Set dynamic `pricePerSecond` per token
- Queueable rentals: new rental starts immediately if expired, else appends after current expiry
- Fixed-price listing & buy flow with fee split
- Simple ascending English auction (+5% min increment) with delayed settlement
- Escrow-less revenue accounting (balances tracked, claim later)
- Reentrancy protection on monetary paths
- Standards compliance: ERC-721, ERC-165, Ownable

## Install & Build
```bash
pnpm install
pnpm hardhat compile
```

## Testing
```bash
pnpm hardhat test
```
(See `test/adspot.test.ts` for examples; extend with edge cases as needed.)

## Deployment
Adjust network settings in `hardhat.config.ts`, then use the script:
```bash
pnpm hardhat run scripts/deploy.ts --network <networkName>
```
The deploy script should deploy `AdSpotNFT` first, then `AdSpotMarket` with desired fee parameters (inspect `deploy.ts` for exact arguments).


## License
MIT
