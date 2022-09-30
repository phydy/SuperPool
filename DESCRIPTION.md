# SuperPool

A Sample Lending pool that accepts liquidity provision through streams.

### problem

Most Lending pool in DeFi accept deposits in ERC20 transfers since most of their incentive methods depend on the contract state updated during deposits. Which means for anyone to Make deposits with realtime streams, they will have to use a third party protocol that accumulates the streams over time, or wait for the streams to accumulate theselves, to make periodic deposits. While this method is okay for anyone used to the conventional Liquidity provision standard, it does not utilize the power of realtime change of value.

### Solution

Create a Lending pool that reacts to streams and manages the state of the pool (user deposits) using supertokens. Which will allow people to Provide Liquidity in the normal way and also through streams. User balances can get querried by getting the realtime balance of the pool. For now, the reward system is raw and incomplete with users having to claim their rewards manually. This can be improved to make automatic distribution at a later stage.

This super pool is just a simple implementation of this module which shows how to manage a lending pool's state in a realtime environment.

### To Improve

Customize the Tokens to disallow sertain features.
Create an automated reward system around it.
