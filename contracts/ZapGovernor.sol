// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "./ZapHandlerV1.sol";

contract ZapGovernor is AccessControlEnumerable {
    /// @dev The underlying vaultChef to administer.
    ZapHandlerV1 public zapHandler;

    /// @dev Can add new vaults to the vaultChef.
    bytes32 public constant SET_FACTORY_ROLE = keccak256("SET_FACTORY_ROLE");
    bytes32 public constant SET_ROUTE_ROLE = keccak256("SET_ROUTE_ROLE");

    constructor(ZapHandlerV1 _zapHandler, address _owner) {
        zapHandler = _zapHandler;
        /// @dev Make msg.sender the default admin
        _setupRole(DEFAULT_ADMIN_ROLE, _owner);
        _grantAllRoles(_owner);
    }

    /// @notice Grants an account all roles. Must be called from a DEFAULT_ADMIN.
    function grantAllRoles(address account)
        public
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        _grantAllRoles(account);
    }

    function _grantAllRoles(address account) internal {
        _setupRole(DEFAULT_ADMIN_ROLE, account);
        _setupRole(SET_FACTORY_ROLE, account);
        _setupRole(SET_ROUTE_ROLE, account);
    }

    function transferOwnership() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _transferOwnership();
    }
    
    function _transferOwnership() internal {
        zapHandler.transferOwnership();
    }

    function setMainToken(IERC20 _mainToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        zapHandler.setMainToken(_mainToken);
    }

    function setFactory(
        address factory,
        uint32 amountsOutNominator,
        uint32 amountsOutDenominator
    ) external onlyRole(SET_FACTORY_ROLE) {
        zapHandler.setFactory(factory, amountsOutNominator, amountsOutDenominator);
    }

    function removeFactory(address factory) external onlyRole(SET_FACTORY_ROLE) {
        zapHandler.removeFactory(factory);
    }

    function setRoute(
        IERC20 from,
        IERC20 to,
        address[] memory inputRoute
    ) external onlyRole(SET_ROUTE_ROLE) {
        zapHandler.setRoute(from, to, inputRoute);
    }

    /// @notice Generic function proxy, only callable by the DEFAULT_ADMIN.
    function executeTransaction(
        address target,
        uint256 value,
        bytes memory data
    ) external payable onlyRole(DEFAULT_ADMIN_ROLE) returns (bytes memory) {
        (bool success, bytes memory returnData) = target.call{value: value}(
            data
        );
        require(success, "!reverted");
        return returnData;
    }


    function setPendingOwner(address newPendingOwner)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        zapHandler.setPendingOwner(newPendingOwner);
    }
    function setZapHandler(ZapHandlerV1 _zapHandler)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        zapHandler = _zapHandler;
    }
}