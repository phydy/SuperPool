## SuperPool

## reamTime Liquidity Provission and accounting

### Enables users to stream assets into a lending pool as liquidity Provission

### How the project is made

The current progress is just the smart-contract implementation of this idea.
A frontend will come in later.

### How to work with the project

## Requirements

install the latest release

```
$ curl -L https://foundry.paradigm.xyz | bash

```

install foundry

```
$ foundryup
```

```
$ mkdir ProjectName && cd ProjectName
$ git init
$ git add remote origin https://github.com/phydy/SuperPool.git
$ git branch -M main
$ git pull origin main
```

## test the Project

```
$ forge test
```

This runs the contracts through a procee of adding liquidity through streams and through normal ERC20 transfer. I exewcutes a borrow, repay and claiming reawds logic. in the test/TestPlatform.sol

[Demo Video](https://www.loom.com/share/b563a6bf256747eaa8133c66710efe71)
