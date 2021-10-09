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

contract ZapHandlerV1 is Ownable, IZapHandler, ReentrancyGuard {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    struct Factory {
        address factory;
        uint32 amountsOutNominator;
        uint32 amountsOutDenominator;
    }

    struct RouteStep {
        IERC20 from;
        IERC20 to;
        IUniswapV2Pair pair;
        uint32 amountsOutNominator;
        uint32 amountsOutDenominator;
    }
    struct PairInfo {
        IERC20 token0;
        IERC20 token1;
    }
    enum TokenEdgeType {
        UNDEFINED,
        TOKEN_TO_TOKEN,
        PAIR_TO_TOKEN,
        TOKEN_TO_PAIR,
        PAIR_TO_PAIR
    }

    IERC20 public mainToken;

    mapping(IERC20 => mapping(IERC20 => TokenEdgeType)) public tokenEdgeTypes;

    mapping(IERC20 => PairInfo) public pairInfo;

    EnumerableSet.AddressSet factorySet;
    mapping(address => Factory) public factories;

    mapping(IERC20 => mapping(IERC20 => RouteStep[])) public routes;

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
    function convertERC20(
        IERC20 fromToken,
        IERC20 toToken,
        address recipient,
        uint256 amount
    ) external override {
        TokenEdgeType edgeType = tokenEdgeTypes[fromToken][toToken];
        if (edgeType == TokenEdgeType.UNDEFINED)
            edgeType = generateEdgeType(fromToken, toToken);

        if (edgeType == TokenEdgeType.TOKEN_TO_TOKEN) {
            handleTokenToToken(fromToken, toToken, recipient, amount);
        } else if (edgeType == TokenEdgeType.PAIR_TO_TOKEN) {
            handlePairToToken(fromToken, toToken, recipient, amount);
        } else if (edgeType == TokenEdgeType.TOKEN_TO_PAIR) {
            handleTokenToPair(fromToken, toToken, recipient, amount);
        } else if (edgeType == TokenEdgeType.PAIR_TO_PAIR) {
            handlePairToPair(fromToken, toToken, recipient, amount);
        }
    }

    function handleTokenToToken(
        IERC20 fromToken,
        IERC20 toToken,
        address recipient,
        uint256 amount
    ) private {
        RouteStep memory lastStep = handleRoute(
            getFromZapperStep(fromToken),
            fromToken,
            toToken,
            amount
        );

        handleSwap(lastStep, recipient, 0);
    }

    function handlePairToToken(
        IERC20 fromToken,
        IERC20 toToken,
        address recipient,
        uint256 amount
    ) private {
        PairInfo memory fromInfo = pairInfo[fromToken];

        IZap(msg.sender).pullAmountTo(address(fromToken), amount);
        IUniswapV2Pair(address(fromToken)).burn(address(this));

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

    function handleTokenToPair(
        IERC20 fromToken,
        IERC20 toToken,
        address recipient,
        uint256 amount
    ) private {
        PairInfo memory toInfo = pairInfo[toToken];
        uint256 amount0 = amount / 2;
        uint256 amount1 = amount - amount0;

        RouteStep memory lastStepToken0;
        if (fromToken == toInfo.token0) {
            lastStepToken0 = getFromZapperStep(fromToken);
        } else {
            lastStepToken0 = handleRoute(
                getFromZapperStep(fromToken),
                fromToken,
                toInfo.token0,
                amount0
            );
            handleSwap(lastStepToken0, address(this), 0);
            lastStepToken0 = getFromThisContractStep(toInfo.token0);
        }

        RouteStep memory lastStepToken1;
        if (fromToken == toInfo.token1) {
            lastStepToken1 = getFromZapperStep(fromToken);
        } else {
            lastStepToken1 = handleRoute(
                getFromZapperStep(fromToken),
                fromToken,
                toInfo.token1,
                amount1
            );
            handleSwap(lastStepToken1, address(this), 0);
            lastStepToken1 = getFromThisContractStep(toInfo.token1);
        }

        handleSwap(lastStepToken0, address(this), amount0);
        handleSwap(lastStepToken1, address(this), amount1);
        uint256 balance0 = toInfo.token0.balanceOf(address(this));
        uint256 balance1 = toInfo.token1.balanceOf(address(this));
        (uint256 res0, uint256 res1, ) = IUniswapV2Pair(address(toToken)).getReserves();
        uint256 amount0ToPair = balance0;
        uint256 amount1ToPair = balance0 * res1 / res0;

        if(amount1ToPair > balance1) {
            amount0ToPair = balance1 * res0 / res1;
            amount1ToPair = balance1;
        }
        toInfo.token0.safeTransfer(address(toToken), amount0ToPair);
        toInfo.token1.safeTransfer(address(toToken), amount1ToPair);
        
        if (amount0ToPair < balance0) {
            toInfo.token0.safeTransfer(owner(), balance0 - amount0ToPair);
        }
        if (amount1ToPair < balance1) {
            toInfo.token1.safeTransfer(owner(), balance1 - amount1ToPair);
        }

        IUniswapV2Pair(address(toToken)).mint(recipient);
    }

    function handlePairToPair(
        IERC20 fromToken,
        IERC20 toToken,
        address recipient,
        uint256 amount
    ) private {
        PairInfo memory fromToken = pairInfo[fromToken];
        PairInfo memory toInfo = pairInfo[toToken];
        // TODO: PAIR TO PAIR IMPLEMENTAITON
        revert("unimplemented feature: pair to pair routing");
    }

    //** ROUTE HANDLERS **/

    // returns lastPair to take out
    function handleRoute(
        RouteStep memory previousStep,
        IERC20 from,
        IERC20 to,
        uint256 previousAmount
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
                    previousAmount
                );
            } else {
                handleSwap(previousStep, address(step.pair), previousAmount);
                previousStep = step;
            }
        }
        return (previousStep);
    }

    // slightly more gas optimal then the shorter version
    function handleSwap(
        RouteStep memory step,
        address recipient,
        uint256 amountIn
    ) private {
        if (address(step.from) == address(0)) {
            IZap(msg.sender).pullAmountTo(recipient, amountIn);
        } else if (address(step.from) == address(1)) {
            step.to.safeTransfer(recipient, step.to.balanceOf(address(this)));
        } else {
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

    function generateAutomaticRoute(
        IERC20 from,
        IERC20 to
    ) private {
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

    function removeFactory(address factory) external onlyOwner {
        require(factorySet.contains(factory), "!exists");
        factorySet.remove(factory);
        delete factories[factory];

        emit FactoryRemoved(factory);
    }

    function setRoute(
        IERC20 from,
        IERC20 to,
        address[] memory inputRoute
    ) external onlyOwner {
        _setRoute(from, to, inputRoute);
    }

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

    function setMainToken(IERC20 _mainToken) external onlyOwner {
        mainToken = _mainToken;
        emit MainTokenSet(_mainToken);
    }

    //** ROUTE GENERATION **/

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
                require(routes[from][to].length > 0, "!swap subroute not created yet");
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

    function generateEdgeType(IERC20 from, IERC20 to)
        private
        returns (TokenEdgeType)
    {
        bool fromPair = getPair(from);
        bool toPair = getPair(to);
        TokenEdgeType edgeType;
        if (fromPair) {
            edgeType = toPair
                ? TokenEdgeType.PAIR_TO_PAIR
                : TokenEdgeType.PAIR_TO_TOKEN;
        } else {
            edgeType = toPair
                ? TokenEdgeType.TOKEN_TO_PAIR
                : TokenEdgeType.TOKEN_TO_TOKEN;
        }
        tokenEdgeTypes[from][to] = edgeType;
        return edgeType;
    }

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

    function getFromZapperStep(IERC20 token)
        private
        pure
        returns (RouteStep memory)
    {
        RouteStep memory fromZapper;
        fromZapper.to = token;
        return fromZapper;
    }

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

    function getFactory(uint256 index) external view returns (address) {
        return factorySet.at(index);
    }

    function factoryLength() external view returns (uint256) {
        return factorySet.length();
    }

    function routeLength(IERC20 token0, IERC20 token1)
        external
        view
        returns (uint256)
    {
        return routes[token0][token1].length;
    }
}
