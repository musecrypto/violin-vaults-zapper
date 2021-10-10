# Violin Vaults zap
 The vaults zapper is a dependency of vaults zap to abstract token swapping. 

## Deploy
```
yarn deploy avax    
```

### Testing
```
yarn test hardhat 
```

The testing require a FORK_URI to be set.

### Environment variables
- PRIVATE_KEY
- ETHERSCAN_APIKEY
- FORK_URI

## Contracts
The contracts have been deployed as-is on a variety of chains.

### Staging

| Chain   | Address                                    |
| ------- | ------------------------------------------ |
| Celo    |  |
| Harmony |  |
| Polygon |  |

## Documentation
### RouteSpec notation
To specify routes, we use "routespec". routespec is a simple encoding to easily specify routes and wildflag subroutes.
here are a few examples where `token0` can be interpretted as the contract address of token0. Furthermore `0` can be interpreted as address zero, the wildcard.

- [`usdt`, `quickswap_factory`, `wmatic`]
- [`usdt`, `trader_joe_factory`, `wavax`, `pangolin_factory`, `usdc`]
- [`usdc`, `pancakeswap_factory`, `wbnb`]
- [`safemoon`, `pancakeswap_factory`, `wbnb`]

Once we've defined a few base routes, we can reuse these in further routes. Let's for example create a route from safemoon to usdc:

- [`safemoon`, `0`, `wbnb`, `0`, `usdc`]

In this instance, the previous two routes will be injected dynamically in this route, whenever it is executed. 
This means that over time we can adjust the subroutes and all superroutes that implement them will automatically get rerouted over the new route as well.

That's RouteSpec. Nothing more, nothing less. Our implementation will automatically create the last route if the two previous routes already existed. It can only do this over the main protocol token however.
This feature we call route tunneling.