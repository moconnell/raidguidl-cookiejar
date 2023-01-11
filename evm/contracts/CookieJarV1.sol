// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.7;

// import "@gnosis.pm/safe-contracts/contracts/base/Executor.sol";
// import "@gnosis.pm/safe-contracts/contracts/GnosisSafe.sol";
import "@gnosis.pm/zodiac/contracts/core/Module.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "../interfaces/IBAAL.sol";

/// @notice Shamom administers the cookie jar
contract CookeJarV1 is Module, AccessControlUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    struct Claim {
        uint256 timestamp;
        uint256 amount;
    }

    /// @notice User role required in order to claim cookies
    bytes32 public constant MEMBER_ROLE = keccak256("MEMBER_ROLE");
    /// @notice User role required in order to upgrade the contract
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    /// @notice Current version of the contract
    uint16 internal _version;

    IBAAL public baal;
    IERC20 public token;

    /// @notice Last cookie claims made by members
    /// @dev This is only a cache and claims older than period are deleted
    mapping(address => Claim[]) public claims;
    /// @notice Cookie value in token units
    uint256 public cookieTokenValue;
    /// @notice Length of period in seconds
    uint256 public period;
    /// @notice Maximum amount of cookies claimable per member per period
    uint256 public maxCookiesPerPeriod;

    /*******************
     * EVENTS
     ******************/

    // EVENTS
    event SetupComplete(
        uint256 cookieTokenValue,
        uint256 period,
        uint256 maxCookiesPerPeriod
    ); /*emits after summoning*/

    event CookiesClaimed(address account, uint256 timestamp, uint256 amount, string comment);

    /*******************
     * DEPLOY
     ******************/

    /// @notice Contract constructor logic
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Summon Baal with voting configuration & initial array of `members` accounts with `shares` & `loot` weights.
    /// @param _initializationParams Encoded setup information.
    function setUp(bytes memory _initializationParams) public override(FactoryFriendly) initializer nonReentrant {
        (
            address _moloch,
            address payable _token,
            address _avatar /*Safe contract address*/,
            uint256 _cookieTokenValue,
            uint256 _maxCookiesPerPeriod,
            uint256 _period
        ) = abi.decode(_initializationParams, (address, address, address, uint256, uint256, uint256));

        __Ownable_init();
        __ReentrancyGuard_init();
        transferOwnership(_avatar);

        // Set the Gnosis safe address
        avatar = _avatar;
        target = _avatar; /*Set target to same address as avatar on setup - can be changed later via setTarget, though probably not a good idea*/

        baal = IBAAL(_moloch);
        token = IERC20(_token);
        cookieTokenValue = _cookieTokenValue;
        period = _period;
        maxCookiesPerPeriod = _maxCookiesPerPeriod;

        emit SetupComplete(
            cookieTokenValue,
            period,
            maxCookiesPerPeriod
        );

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MEMBER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    /// @notice Grant membership to the specified address
    /// @param applicant New member address
    function grantMembership(address applicant) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MEMBER_ROLE, applicant);
    }

    /// @notice Can be called by members to claim up to maxCookiesPerPeriod cookies in any period
    /// @param amount Amount of cookies claimed
    /// @param comment Reason for the claim
    function claimCookies(uint256 amount, string calldata comment) public payable virtual onlyRole(MEMBER_ROLE) {
        require(amount <= remainingAllowance(), "Amount greater than remaining allowance");
        require(amount <= getCookieBalance(), "Not enough cookies in the jar");
        require(bytes(comment).length > 0, "No comment provided");

        token.transferFrom(address(this), msg.sender, amount * cookieTokenValue);

        claims[msg.sender].push(Claim(block.timestamp, amount));

        emit CookiesClaimed(msg.sender, block.timestamp, amount, comment);
    }

    /// @notice Deposit tokens in the jar to fund cookies
    /// @param amount Amount of token to deposit
    function deposit(uint amount) public payable {
        token.transferFrom(msg.sender, address(this), amount);
    }

    /// @notice Gets the total token balance of the contract
    function getTokenBalance() public view onlyRole(MEMBER_ROLE) returns (uint) {
        return token.balanceOf(address(this));
    }

    /// @notice Gets the total balance of the contract expressed in cookies
    function getCookieBalance() public view onlyRole(MEMBER_ROLE) returns (uint) {
        return getTokenBalance() / cookieTokenValue;
    }

    /// @notice Gets the total number of cookies claimed by sender in the current period
    function totalCookiesThisPeriod() public virtual onlyRole(MEMBER_ROLE) returns (uint256 total) {
        Claim[] storage claimed = claims[msg.sender];
        for (uint i = 0; i < claimed.length; i++) {
            Claim memory claim = claimed[i];
            if (block.timestamp - claim.timestamp < period) {
                total += claim.amount;
            } else {
                // remove old claim
                for (uint j = i; j < claimed.length - 1; j++) {
                    claimed[j] = claimed[j + 1];
                }
                claimed.pop();
            }
        }
    }

    /// @notice Gets the total number of cookies remaining to be claimed by sender in the current period
    function remainingAllowance() public virtual onlyRole(MEMBER_ROLE) returns (uint256) {
        uint256 totalClaimed = totalCookiesThisPeriod();

        return maxCookiesPerPeriod - totalClaimed;
    }

    /// @notice gets the current version of the contract
    function version() public view virtual returns (uint256) {
        return _version;
    }

    /// @notice Update the contract version number
    /// @notice Only allowed for member of UPGRADER_ROLE
    function updateVersion() external onlyRole(UPGRADER_ROLE) {
        _version += 1;
    }

    /*******************
     * INTERNAL
     ******************/

    /// @notice upgrade authorization logic
    /// @dev adds onlyRole(UPGRADER_ROLE) requirement
    function _authorizeUpgrade(
        address /*newImplementation*/
    )
        internal
        view
        override
        onlyRole(UPGRADER_ROLE) // solhint-disable-next-line no-empty-blocks
    {
        //empty block
    }
}
