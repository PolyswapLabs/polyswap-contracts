# 📈 PolySwap Smart Contracts

**Automated DeFi swaps triggered by on-chain prediction market outcomes.**

This repository contains the core smart contracts of **PolySwap**, a protocol that allows users to create conditional swap intents based on prediction markets like [Polymarket](https://polymarket.com/).

## 🛠️ What It Does

PolySwap lets users define CoW Swap orders that become valid only when a specific prediction market condition is met.
The contract checks the status of a Polymarket order and activates the swap only if that order has been fully filled (indicating the prediction condition was reached).

## 🧱 Contract Overview

* `BaseConditionalOrder`: Abstract contract to inherit for compatibility with ComposableCoW.
* `Polyswap`: Main contract that inherits from `BaseConditionalOrder` and verifies if the Polymarket order is filled.
* `PolySwapOrder`: Verifies if the Polyswap order parameters are correct and defines the order struct.

The `Polyswap` contract uses the Polymarket `CTFExchange` contract to check, via the `getOrderStatus()` function, whether:

* the order is filled or cancelled, and
* the remaining amount is `0`.

If both conditions are met, the swap is executed using the Composable CoW Swap protocol.
Both conditions being met means that the limit order has been filled and that the price of the limit order has been achieved.

## 🧪 Stack

* [Solidity](https://soliditylang.org)
* [Foundry](https://book.getfoundry.sh/) for development and testing
* [Polygon PoS](https://polygon.technology) as the initial deployment network

## 🚀 Deployment

All contracts are deployed on **Polygon** for compatibility with Polymarket's on-chain infrastructure.

Contract Address (CTF Exchange): `0xEa8FA1438785b9464f988e3AFa1E464Ba3A110B1`
View on [Polygonscan](https://polygonscan.com/address/0xEa8FA1438785b9464f988e3AFa1E464Ba3A110B1#code)

Contract Address (Neg Risk CTF Exchange): `0x04a7745Ee5c5cCE28aD0A2c956e789415a90EA7D`
View on [Polygonscan](https://polygonscan.com/address/0x04a7745Ee5c5cCE28aD0A2c956e789415a90EA7D#code)

Contract Address PolyswapV2 (Exchange V3): `0xD9296a41dAE154ff47CcC124a77CF5acff4E1F50`
View on [Sourcify](https://repo.sourcify.dev/137/0xD9296a41dAE154ff47CcC124a77CF5acff4E1F50)

## 🧑‍💻 Authors

 | [<img src="https://github.com/Intermarch3.png?size=85" width=85><br><sub>Lucas Leclerc</sub>](https://github.com/Intermarch3) | [<img src="https://github.com/Pybast.png?size=85" width=85><br><sub>Baptiste Florentin</sub>](https://github.com/Pybast)
 | :---: | :---: |