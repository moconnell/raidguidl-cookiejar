// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "../interfaces/IBAAL.sol";

/// @notice Shamom administers the cookie jar
contract ShamomV1 is
    ReentrancyGuard,
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable
{
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

    event CookiesClaimed(
        address account,
        uint256 timestamp,
        uint256 amount,
        string comment
    );

    /*******************
     * DEPLOY
     ******************/

    /// @notice Contract constructor logic
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Contract initialization logic
    function initialize(
        address _moloch,
        address payable _token,
        uint256 _cookieTokenValue,
        uint256 _maxCookiesPerPeriod,
        uint256 _period
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        baal = IBAAL(_moloch);
        token = IERC20(_token);
        cookieTokenValue = _cookieTokenValue;
        period = _period;
        maxCookiesPerPeriod = _maxCookiesPerPeriod;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MEMBER_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    /// @notice Grant membership to the specified address
    /// @param applicant New member address
    function grantMembership(
        address applicant
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MEMBER_ROLE, applicant);
    }

    /// @notice Can be called by members to claim up to maxCookiesPerPeriod cookies in any period
    /// @param amount Amount of cookies claimed
    /// @param comment Reason for the claim
    function claimCookies(
        uint256 amount,
        string calldata comment
    ) public payable virtual onlyRole(MEMBER_ROLE) {
        require(
            amount <= remainingAllowance(),
            "Amount greater than remaining allowance"
        );
        require(amount <= getCookieBalance(), "Not enough cookies in the jar");
        require(bytes(comment).length > 0, "No comment provided");

        token.transferFrom(
            address(this),
            msg.sender,
            amount * cookieTokenValue
        );

        claims[msg.sender].push(Claim(block.timestamp, amount));

        emit CookiesClaimed(msg.sender, block.timestamp, amount, comment);
    }

    /// @notice Deposit tokens in the jar to fund cookies
    /// @param amount Amount of token to deposit
    function deposit(uint amount) public payable {
        token.transferFrom(msg.sender, address(this), amount);
    }

    /// @notice Gets the total token balance of the contract
    function getTokenBalance()
        public
        view
        onlyRole(MEMBER_ROLE)
        returns (uint)
    {
        return token.balanceOf(address(this));
    }

    /// @notice Gets the total balance of the contract expressed in cookies
    function getCookieBalance()
        public
        view
        onlyRole(MEMBER_ROLE)
        returns (uint)
    {
        return getTokenBalance() / cookieTokenValue;
    }

    /// @notice Gets the total number of cookies claimed by sender in the current period
    function totalCookiesThisPeriod()
        public
        virtual
        onlyRole(MEMBER_ROLE)
        returns (uint256 total)
    {
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
    function remainingAllowance()
        public
        virtual
        onlyRole(MEMBER_ROLE)
        returns (uint256)
    {
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

// contract ShamomSummonerV1 {
//     address payable public template;

//     event SummonComplete(address indexed baal, address shamom);

//     constructor(address payable _template) {
//         template = _template;
//     }

//     function summonShamom(
//         address _moloch,
//         address payable _token,
//         uint256 _cookieTokenValue,
//         uint256 _maxCookiesPerPeriod,
//         uint256 _period
//     ) public returns (address) {
//         ShamomV1 shamom = ShamomV1(payable(Clones.clone(template)));

//         shamom.initialize(
//             _moloch,
//             _token,
//             _cookieTokenValue,
//             _maxCookiesPerPeriod,
//             _period
//         );

//         emit SummonComplete(_moloch, address(shamom));

//         return address(shamom);
//     }
// }
