// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "./dependencies/Ownable.sol";
import "./interfaces/IZap.sol";
import "./interfaces/IZapHandler.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

/**
 * @notice The ZapHandlerV1 is the first implementation of the Violin Zap protocol.
 * @notice It allows the owner to define routes that span over multiple uniswap factories.
 * @notice Furthermore, individual hops in the route can set the zero factory to indicate that this hop should be subroutes by an existing route in the handler.
 * @notice All though routes need to be added manually, swaps from token a to token b will create the route [a, main, b] if the main token is set.
 * @notice The ZapHandlerV1 supports token->token, pair->token and token->pair swaps.
 * @notice For pair->token swaps, the pair will first be burned and then two swaps to token are made.
 * @notice For token->pair swaps, two swaps to each subtoken are made and then the pair is minted.
 */
contract ZapHandlerV1 is Ownable, IZapHandler, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;
    
    /// @dev A list of ways the swap can occur, each way has distinct logic in the algorithm.
    enum SwapType {
        UNDEFINED,
        TOKEN_TO_TOKEN,
        TOKEN_TO_PAIR,
        PAIR_TO_TOKEN,
        PAIR_TO_PAIR
    }

    /// @dev represents the swap type of the route from token0 to token1, for example TOKEN_TO_PAIR.
    mapping(IERC20 => mapping(IERC20 => SwapType)) public tokenSwapType;

    /// @dev Represents the token composition of an LP pair. Used for minting and burning LPs.
    struct PairInfo {
        IERC20 token0;
        IERC20 token1;
    }

    /// @dev The token0 and token1 of the pair if the pair has been registered.
    mapping(IERC20 => PairInfo) public pairInfo;

    /// @dev Represents a UniswapV2Factory compatible factory.
    struct Factory {
        /// @dev The address of the factory.
        address factory;
        /// @dev The fee nominator of the AMM, usually set to 997 for a 0.3% fee.
        uint32 amountsOutNominator;
        /// @dev The fee denominator of the AMM, usually set to 1000.
        uint32 amountsOutDenominator;
    }
    /// @dev An enumerable list of all registered factories.
    EnumerableSet.AddressSet factorySet;
    /// @dev Factory address to the specification of the factory including it's fee structure.
    mapping(address => Factory) public factories;


    /// @dev Represents a single step in a swap route.
    /// @dev Within the algorithm, two special steps are employed: The getFromZapperStep and getFromThisContractStep.
    struct RouteStep {
        /// @dev The token to swap from.
        /// @dev address(0) to indicate that the to token can be pulled from the Zap (msg.sender) contract.
        /// @dev address(1) to indicate that the `to` token can be pulled from this contract.
        IERC20 from;
        /// @dev The token to swap to.
        IERC20 to;
        /// @dev The UniswapV2 compatible pair address to swap over. 
        IUniswapV2Pair pair;
        /// @dev The fee nominator of the AMM, usually set to 997 for a 0.3% fee.
        uint32 amountsOutNominator;
        /// @dev The fee denominator of the AMM, usually set to 1000.
        uint32 amountsOutDenominator;
    }

    /// @dev For any registered from and to pair, provide a route used by the algorithm to execute the swap.
    mapping(IERC20 => mapping(IERC20 => RouteStep[])) public routes;

    /// @dev The main token most AMMs and pairs use, eg. WETH.
    IERC20 public mainToken;


    event FactorySet(
        address indexed factory,
        bool indexed alreadyExists,
        uint32 amountsOutNominator,
        uint32 amountsOutDenominator
    );
    event FactoryRemoved(address indexed factory);
    event RouteAdded(
        IERC20 indexed from,
        IERC20 indexed to,
        bool indexed alreadyExists
    );
    event MainTokenSet(IERC20 indexed mainToken);

    //** ROUTING **/

    /**
    * @notice Swap `amount` of `fromToken` to `toToken` and send them to the recipient.
    * @notice The `fromToken` and `toToken` arguments can be AMM pairs.
    * @notice Requires `msg.sender` to be a Zap instance.
    * @dev Switches over the different routing types to let the specific handler functions take care of them.
    * @param fromToken The token to take from `msg.sender` and exchange for `toToken`.
    * @param toToken The token that will be bought and sent to the recipient.
    * @param recipient The destination address to receive the `toToken`.
    * @param amount The amount that the zapper should take from the `msg.sender` and swap.
    */
    function convertERC20(
        IERC20 fromToken,
        IERC20 toToken,
        address recipient,
        uint256 amount
    ) external override {
        // Fetch the type of swap or discover it if it's not cached yet.
        SwapType edgeType = tokenSwapType[fromToken][toToken];
        if (edgeType == SwapType.UNDEFINED)
            edgeType = generateSwapType(fromToken, toToken);

        // Execute the swap according to its type.
        if (edgeType == SwapType.TOKEN_TO_TOKEN) {
            handleTokenToToken(fromToken, toToken, recipient, amount);
        } else if (edgeType == SwapType.TOKEN_TO_PAIR) {
            handleTokenToPair(fromToken, toToken, recipient, amount);
        } else if (edgeType == SwapType.PAIR_TO_TOKEN) {
            handlePairToToken(fromToken, toToken, recipient, amount);
        } else if (edgeType == SwapType.PAIR_TO_PAIR) {
            handlePairToPair(fromToken, toToken, recipient, amount);
        }
    }

    /// @notice Swap a token to another token, both tokens are not LPs. This is the most simple swap type.
    /// @param fromToken The token to take from `msg.sender` and exchange for `toToken`.
    /// @param toToken The token that will be bought and sent to the recipient.
    /// @param recipient The destination address to receive the `toToken`.
    /// @param amount The amount that the zapper should take from the `msg.sender` and swap.
    function handleTokenToToken(
        IERC20 fromToken,
        IERC20 toToken,
        address recipient,
        uint256 amount
    ) private {
        // Swap along the route from the `fromToken` to the `toToken`
        // The initial step is set to the dummy to take the tokens out of the Zap contract.
        RouteStep memory lastStep = handleRoute(
            getFromZapperStep(),
            fromToken,
            toToken,
            amount
        );
        // Take the tokens out of the last step and forward them to the recipient. The last amount parameter is only used for the dummies so is set to zero.
        handleSwap(lastStep, recipient, 0);
    }

    /// @notice Swap an LP pair to a token. This is done by burning the LP pair into token0 and token1, temporarily stored inside this contract.
    /// @notice Then, token0 and token1 are both swapped to the `toToken` as if they were TOKEN_TO_TOKEN.
    /// @param fromToken The token to take from `msg.sender` and exchange for `toToken`.
    /// @param toToken The token that will be bought and sent to the `recipient` address.
    /// @param recipient The destination address to receive the `toToken`.
    /// @param amount The amount that the zapper should take from the `msg.sender` and swap.
    function handlePairToToken(
        IERC20 fromToken,
        IERC20 toToken,
        address recipient,
        uint256 amount
    ) private {
        // Get the token0 and token1 pair info of the from token, this has already been generated.
        PairInfo memory fromInfo = pairInfo[fromToken];

        // Pull all LP tokens into the LP contract and burn them to receive the underlying tokens inside of this address.
        IZap(msg.sender).pullAmountTo(address(fromToken), amount);
        IUniswapV2Pair(address(fromToken)).burn(address(this));
        
        /// Executes a swap from `token0` to the `toToken` and sends them to the recipient`.
        uint256 token0bal = fromInfo.token0.balanceOf(address(this));
        if (fromInfo.token0 == toToken) {
            toToken.safeTransfer(recipient, token0bal);
        } else {
            RouteStep memory lastStepToken0 = handleRoute(
                getFromThisContractStep(fromInfo.token0),
                fromInfo.token0,
                toToken,
                token0bal
            );
            handleSwap(lastStepToken0, recipient, 0);
        }

        /// Executes a swap from `token1` to the `toToken` and sends them to the recipient`.
        uint256 token1bal = fromInfo.token1.balanceOf(address(this));
        if (fromInfo.token1 == toToken) {
            toToken.safeTransfer(recipient, token1bal);
        } else {
            RouteStep memory lastStepToken1 = handleRoute(
                getFromThisContractStep(fromInfo.token1),
                fromInfo.token1,
                toToken,
                token1bal
            );
            handleSwap(lastStepToken1, recipient, 0);
        }
    }

    /// @notice Swap a token to an LP pair. This is done by swapping half of the token `amount` to token0 and the other half to token1.
    /// @notice Finally, token0 and token1, stored inside the contract, are forwarded to the LP pair and the LP pair tokens are minted and sent to the recipient.
    /// @param fromToken The token to take from `msg.sender` and exchange for `toToken`.
    /// @param toToken The token that will be bought and sent to the `recipient` address.
    /// @param recipient The destination address to receive the `toToken`.
    /// @param amount The amount that the zapper should take from the `msg.sender` and swap.
    function handleTokenToPair(
        IERC20 fromToken,
        IERC20 toToken,
        address recipient,
        uint256 amount
    ) private {
        // Get the token0 and token1 pair info of the from token, this has already been generated.
        PairInfo memory toInfo = pairInfo[toToken];

        uint256 amount0 = amount / 2;
        uint256 amount1 = amount - amount0;

        /// Swap amount0 (half of amount) to token0 and store it in this contract.
        if (fromToken == toInfo.token0) {
            IZap(msg.sender).pullAmountTo(address(this), amount0);
        } else {
            RouteStep memory lastStepToken0 = handleRoute(
                getFromZapperStep(),
                fromToken,
                toInfo.token0,
                amount0
            );

            handleSwap(lastStepToken0, address(this), amount0);
        }

        /// Swap amount1 (half of amount) to token1 and store it in this contract.
        if (fromToken == toInfo.token1) {
            IZap(msg.sender).pullAmountTo(address(this), amount1);
        } else {
            RouteStep memory lastStepToken1 = handleRoute(
                getFromZapperStep(),
                fromToken,
                toInfo.token1,
                amount1
            );
            handleSwap(lastStepToken1, address(this), amount1);
        }
        // Calculate the correct amounts to add to the AMM pair, similar to the uniswap router, there's some inefficiency for transfer-tax tokens.
        uint256 balance0 = toInfo.token0.balanceOf(address(this));
        uint256 balance1 = toInfo.token1.balanceOf(address(this));
        (uint256 res0, uint256 res1, ) = IUniswapV2Pair(address(toToken))
            .getReserves();
        uint256 amount0ToPair = balance0;
        uint256 amount1ToPair = (balance0 * res1) / res0;

        if (amount1ToPair > balance1) {
            amount0ToPair = (balance1 * res0) / res1;
            amount1ToPair = balance1;
        }
        
        // Transfer the ideal amount of tokens to the LP pair.
        toInfo.token0.safeTransfer(address(toToken), amount0ToPair);
        toInfo.token1.safeTransfer(address(toToken), amount1ToPair);
        
        // The dust is transfered to the owner as this is otherwise lost and `to` will not handle this for our contracts.
        if (amount0ToPair < balance0) {
            toInfo.token0.safeTransfer(owner(), balance0 - amount0ToPair);
        }
        if (amount1ToPair < balance1) {
            toInfo.token1.safeTransfer(owner(), balance1 - amount1ToPair);
        }

        // Finally the LP pair is minted.
        IUniswapV2Pair(address(toToken)).mint(recipient);
    }

    /// @dev This iteration of the zap handler does not support Pair->Pair swaps yet. If needed, this could be done by two pair->token swaps.
    function handlePairToPair(
        IERC20 /**fromToken*/,
        IERC20 /**toToken*/,
        address /**recipient*/,
        uint256 /**amount*/
    ) private pure {
        // TODO: PAIR TO PAIR IMPLEMENTATION
        revert("unimplemented feature: pair to pair routing");
    }

    //** ROUTE HANDLERS **/

    /**
     * @dev Swaps tokens along the saved route between `from` and `to`. The last swap step is not yet handled (swapped) to allow the caller to chose a destination for it.
     * @dev This pull mechanism (using lastStep) is done to allow the wildcard (zero factory) notation to function efficiently. Eg. routes like [token0, 0, wmatic, 0, token1].
     * @dev handleRoute goes through all steps along the route and recurses through subroutes to do the same. It pulls funds from the previous step pairs into the current step pairs.
     * @dev If a route does not exist yet, it attempts to tunnel a route over the main token. This will revert if there is no such route possible.
     * @param from The token to swap from.
     * @param to The token to swap to.
     * @param firstAmount The amount of tokens to pull from the Zap, will only be used if the previousStep is set to the from-zap dummy.
     * @return lastStep The last swap step that still needs to be handled. This needs to be handled to actually send the to tokens to a location.
     */
    function handleRoute(
        RouteStep memory previousStep,
        IERC20 from,
        IERC20 to,
        uint256 firstAmount
    ) private returns (RouteStep memory lastStep) {
        RouteStep[] memory route = routes[from][to];
        if (route.length == 0) {
            generateAutomaticRoute(from, to);
            route = routes[from][to];
        }

        for (uint256 i = 0; i < route.length; i++) {
            RouteStep memory step = route[i];
            // Zero pair indicates nested routing.
            if (address(step.pair) == address(0)) {
                previousStep = handleRoute(
                    previousStep,
                    step.from,
                    step.to,
                    firstAmount
                );
            } else {
                handleSwap(previousStep, address(step.pair), firstAmount);
                previousStep = step;
            }
        }
        return (previousStep);
    }

    /**
     * @dev handleSwap executes a swap on the provided `step` pair. It requires that there are already `from` tokens deposited into this pair.
     * @dev As many `to` tokens will then be sent to the recipient as is allowed by the pair curve.
     * @dev It thus executes a swap on a pair given the pre-existing deposit, and forwards the result to recipient.
     * @dev Dummy steps can be provided to pull tokens from either the Zap contract or from this contract.
     * @param step The step to swap in and transfer from.
     * @param recipient The recipient to sent the swap result to.
     * @param amountIn The amount of tokens to pull from the Zap. Should only be set if ussing a from zap dummy (otherwise it's ignored).
     */
    function handleSwap(
        RouteStep memory step,
        address recipient,
        uint256 amountIn
    ) private {
        // We first handle the dummy step cases.
        // from=address(0): Transfer `amountIn` from the zap contract to the recipient. This is used as the first step in the route.
        // from=addres(1): Transfer all tokens in this contract to the recipient. This is used for the LP related functionality.
        if (address(step.from) == address(0)) {
            IZap(msg.sender).pullAmountTo(recipient, amountIn);
        } else if (address(step.from) == address(1)) {
            step.to.safeTransfer(recipient, step.to.balanceOf(address(this)));
        } else {
            // If the step is not a dummy, this means an actual AMM swap has to occur.
            // For gas optimization, we write out the two cases fully (where from is token0 and where from is token1).
            if (address(step.from) < address(step.to)) {
                (uint256 reserveIn, uint256 reserveOut, ) = step
                    .pair
                    .getReserves();
                amountIn = step.from.balanceOf(address(step.pair)) - reserveIn;
                uint256 amountOut = getAmountOut(
                    amountIn,
                    reserveIn,
                    reserveOut,
                    step.amountsOutNominator,
                    step.amountsOutDenominator
                );
                step.pair.swap(0, amountOut, recipient, "");
            } else {
                (uint256 reserveOut, uint256 reserveIn, ) = step
                    .pair
                    .getReserves();
                amountIn = step.from.balanceOf(address(step.pair)) - reserveIn;
                uint256 amountOut = getAmountOut(
                    amountIn,
                    reserveIn,
                    reserveOut,
                    step.amountsOutNominator,
                    step.amountsOutDenominator
                );
                step.pair.swap(amountOut, 0, recipient, "");
            }
        }
    }

    //** CONFIGURATION **/
    /// @dev Attempts to tunnel a route over the main token and save it.
    /// @dev This route is of the form [from, 0, main, 0, to]
    function generateAutomaticRoute(IERC20 from, IERC20 to) private {
        IERC20 main = mainToken;
        require(from != main && to != main, "!no route found");
        address[] memory route = new address[](5);
        route[0] = address(from);
        route[1] = address(0);
        route[2] = address(main);
        route[3] = address(0);
        route[4] = address(to);
        _setRoute(from, to, route);
    }

    /// @dev Adds a factory to the list of registered factories that can be used within RouteSpec.
    function setFactory(
        address factory,
        uint32 amountsOutNominator,
        uint32 amountsOutDenominator
    ) external onlyOwner {
        require(amountsOutDenominator >= amountsOutNominator, "!nom > denom");
        require(amountsOutNominator != 0, "!zero");
        assert(amountsOutNominator != 0);
        require(factory != address(0), "!zero factory"); // reserved for subroutes
        bool alreadyExists = factorySet.contains(factory); // for event

        factories[factory] = Factory({
            factory: factory,
            amountsOutNominator: amountsOutNominator,
            amountsOutDenominator: amountsOutDenominator
        });
        factorySet.add(factory);

        emit FactorySet(
            factory,
            alreadyExists,
            amountsOutNominator,
            amountsOutDenominator
        );
    }
    /// @notice Removes a factory from the list of registered factories.
    function removeFactory(address factory) external onlyOwner {
        require(factorySet.contains(factory), "!exists");
        factorySet.remove(factory);
        delete factories[factory];

        emit FactoryRemoved(factory);
    }

    /**
     * @notice Generates and saves a route (and inverse of this route) based on the RouteSpec encoded `inputRoute`.
     * @param from the token to swap from.
     * @param to the token to swap to.
     * @param inputRoute A route in RouteSpec notation indicating the swap steps and the uniswap like factories these swaps should be made.
     */
    function setRoute(
        IERC20 from,
        IERC20 to,
        address[] memory inputRoute
    ) external onlyOwner {
        _setRoute(from, to, inputRoute);
    }

    /**
     * @dev Generates a route based on the RouteSpec encoded `inputRoute` and saves it under routes.
     * @dev A route is denoted as a list of RouteSteps.
     * @dev Also generates and saves the inverse of the route.
     */
    function _setRoute(
        IERC20 from,
        IERC20 to,
        address[] memory inputRoute
    ) private {
        bool alreadyExists = routes[from][to].length > 0;

        generateRoute(from, to, inputRoute);
        emit RouteAdded(from, to, alreadyExists);

        generateInvertedRoute(from, to);
        emit RouteAdded(to, from, alreadyExists);
    }

    /// @dev Updates the main token, this is used for automatic route tunneling.
    function setMainToken(IERC20 _mainToken) external onlyOwner {
        mainToken = _mainToken;
        emit MainTokenSet(_mainToken);
    }

    //** ROUTE GENERATION **/

    /**
     * @dev Generates a new route from token0 and token1 using RouteSpec notation.
     */
    function generateRoute(
        IERC20 token0,
        IERC20 token1,
        address[] memory route
    ) private {
        require(route.length >= 3, "!route too short");
        require(route.length % 2 == 1, "!route has even length");
        require(route[0] == address(token0), "!token0 not route beginning");
        require(
            route[route.length - 1] == address(token1),
            "!token1 not route ending"
        );
        delete routes[token0][token1];

        IERC20 from = IERC20(route[0]);
        from.balanceOf(address(this)); // validate from

        for (uint256 i = 1; i < route.length; i += 2) {
            address factory = route[i];
            IERC20 to = IERC20(route[i + 1]);
            if (factory == address(0)) {
                require(
                    routes[from][to].length > 0,
                    "!swap subroute not created yet"
                );
                routes[token0][token1].push(
                    RouteStep({
                        from: from,
                        pair: IUniswapV2Pair(address(0)),
                        to: to,
                        amountsOutNominator: 0,
                        amountsOutDenominator: 0
                    })
                );
            } else {
                require(
                    factorySet.contains(factory),
                    "!factory does not exist"
                );
                address pairAddress = IUniswapV2Factory(factory).getPair(
                    address(from),
                    address(to)
                );
                require(pairAddress != address(0), "pair does not exist");
                routes[token0][token1].push(
                    RouteStep({
                        from: from,
                        pair: IUniswapV2Pair(pairAddress),
                        to: to,
                        amountsOutNominator: factories[factory]
                            .amountsOutNominator,
                        amountsOutDenominator: factories[factory]
                            .amountsOutDenominator
                    })
                );
            }

            from = to;
        }
    }

    /// @dev Inverts the stored [`from`, `to`] route and stores this as a new route.
    function generateInvertedRoute(IERC20 from, IERC20 to) private {
        delete routes[to][from];
        uint256 length = routes[from][to].length;
        uint256 index;
        RouteStep memory step;
        for (uint256 i = 0; i < length; i++) {
            index = length - 1 - i;
            step = routes[from][to][index];
            routes[to][from].push(
                RouteStep({
                    from: step.to,
                    pair: step.pair,
                    to: step.from,
                    amountsOutNominator: step.amountsOutNominator,
                    amountsOutDenominator: step.amountsOutDenominator
                })
            );
        }
    }

    //** TOKEN INFO GENERATION **/

    /// @dev Figures out the SwapType (eg. TOKEN_TO_TOKEN) for the token pair and stores it.
    /// @dev Calls common UniswapV2Pair functions to guess that the tokens are a pair or not.
    function generateSwapType(IERC20 from, IERC20 to)
        private
        returns (SwapType)
    {
        bool fromPair = getPair(from);
        bool toPair = getPair(to);
        SwapType swapType;
        if (fromPair) {
            swapType = toPair
                ? SwapType.PAIR_TO_PAIR
                : SwapType.PAIR_TO_TOKEN;
        } else {
            swapType = toPair
                ? SwapType.TOKEN_TO_PAIR
                : SwapType.TOKEN_TO_TOKEN;
        }
        tokenSwapType[from][to] = swapType;
        return swapType;
    }

    /// @dev Returns whether `token` is a pair or not. If it is a pair, stores the pairInfo.
    function getPair(IERC20 token) private returns (bool) {
        IUniswapV2Pair pair = IUniswapV2Pair(address(token));
        try pair.getReserves() {
            // get token0
            try pair.token0() returns (address token0) {
                // get token1
                try pair.token1() returns (address token1) {
                    pairInfo[token].token0 = IERC20(token0);
                    pairInfo[token].token1 = IERC20(token1);
                    return true;
                } catch {}
            } catch {}
        } catch {}
        return false;
    }

    //** UTILITIES **/
    
    /// @dev Uses the Uniswap formula to calculate how many tokens can be taken out given `amountIn`.
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        uint256 feeNom,
        uint256 feeDenom
    ) private pure returns (uint256 amountOut) {
        uint256 amountInWithFee = amountIn * feeNom;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * feeDenom + amountInWithFee;
        unchecked {
            return denominator == 0 ? 0 : numerator / denominator;
        }
    }

    /// @dev Returns a dummy step that indactes the token should be pulled from the zapper.
    function getFromZapperStep()
        private
        pure
        returns (RouteStep memory)
    {
        RouteStep memory fromZapper;
        return fromZapper;
    }

    /// @dev Returns a dummy step that indactes the `token` should be pulled from this contract.
    function getFromThisContractStep(IERC20 token)
        private
        pure
        returns (RouteStep memory)
    {
        RouteStep memory fromZapper;
        fromZapper.from = IERC20(address(1));
        fromZapper.to = token;
        return fromZapper;
    }

    /// @notice Gets a registered factory at a specific index, use factoryLength() for the upper bound.
    function getFactory(uint256 index) external view returns (address) {
        return factorySet.at(index);
    }

    /// @notice Returns the total number of registered factories.
    function factoryLength() external view returns (uint256) {
        return factorySet.length();
    }

    /// @notice Returns the number of steps on the route from token0 to token1.
    function routeLength(IERC20 token0, IERC20 token1)
        external
        view
        returns (uint256)
    {
        return routes[token0][token1].length;
    }
}
