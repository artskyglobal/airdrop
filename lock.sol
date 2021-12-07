// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../ERC20.sol";
import "../extensions/ERC20Burnable.sol";
import "../extensions/ERC20Pausable.sol";
import "../../../access/AccessControlEnumerable.sol";
import "../../../utils/Context.sol";

/**
 * @dev {ERC20} token, including:
 *
 *  - ability for holders to burn (destroy) their tokens
 *  - a minter role that allows for token minting (creation)
 *  - a pauser role that allows to stop all token transfers
 *
 * This contract uses {AccessControl} to lock permissioned functions using the
 * different roles - head to its documentation for details.
 *
 * The account that deploys the contract will be granted the minter and pauser
 * roles, as well as the default admin role, which will let it grant both minter
 * and pauser roles to other accounts.
 */
contract ERC20PresetMinterPauser is Context, AccessControlEnumerable, ERC20Burnable, ERC20Pausable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /**
     * @dev Grants `DEFAULT_ADMIN_ROLE`, `MINTER_ROLE` and `PAUSER_ROLE` to the
     * account that deploys the contract.
     *
     * See {ERC20-constructor}.
     */
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(MINTER_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, _msgSender());
    }

    /**
     * @dev Creates `amount` new tokens for `to`.
     *
     * See {ERC20-_mint}.
     *
     * Requirements:
     *
     * - the caller must have the `MINTER_ROLE`.
     */
    function mint(address to, uint256 amount) public virtual {
        require(hasRole(MINTER_ROLE, _msgSender()), "ERC20PresetMinterPauser: must have minter role to mint");
        _mint(to, amount);
    }

    /**
     * @dev Pauses all token transfers.
     *
     * See {ERC20Pausable} and {Pausable-_pause}.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function pause() public virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "ERC20PresetMinterPauser: must have pauser role to pause");
        _pause();
    }

    /**
     * @dev Unpauses all token transfers.
     *
     * See {ERC20Pausable} and {Pausable-_unpause}.
     *
     * Requirements:
     *
     * - the caller must have the `PAUSER_ROLE`.
     */
    function unpause() public virtual {
        require(hasRole(PAUSER_ROLE, _msgSender()), "ERC20PresetMinterPauser: must have pauser role to unpause");
        _unpause();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20, ERC20Pausable) {
        super._beforeTokenTransfer(from, to, amount);
    }
}

pragma solidity ^0.8.0;
/** Locks an existing token then creates a new share token from the locked token
  * 1:1 backed token
  * Inspired by https://blog.openzeppelin.com/bypassing-smart-contract-timelocks/
  * https://www.bscscan.com/address/0x26b5bb09502174f3a2ed4c2d87db1197dee48396#contracts
  * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/TokenTimelock.sol
 */
contract ShareLocker {

    struct ShareTokenInfo {
        address baseTokenAddress;
        address shareTokenAddress;
        uint256 amount;
        uint256 releaseTime;
        address admin;
        bool isSet;
    }
    // token address => share token id list
    mapping(address => uint256[]) private tokenLockers;
    ShareTokenInfo[] private shareTokenList;
    uint256 private shareTokenCount;
    mapping(address => uint256) private shareTokenIndex;

    /** @notice Locks a base token until a specified time and creates a share token with 1:1 peg.
     */
    function lock(address _tokenAddress, uint256 _amount, uint256 _releaseTime) public returns(uint256){
        // input checks
        require(_amount > 0, "ShareLocker: Token amount is zero.");
        require(_releaseTime < 10000000000, "ShareLocker: Enter an unix timestamp in seconds, not miliseconds.");

        // check approve
        ERC20 baseToken = ERC20(_tokenAddress);
        //require(token.approve(address(this), _amount), "Approve tokens failed");
        require(baseToken.transferFrom(msg.sender, address(this), _amount), "ShareLocker: transferFrom failed.");

        // generate new ERC-20 token
        string memory newTokenName = string(abi.encodePacked(baseToken.name(), " Locked Share ", uint2str(shareTokenCount)));
        string memory newTokenSymbol = string(abi.encodePacked(baseToken.symbol(), "-", uint2str(shareTokenCount)));
        ERC20PresetMinterPauser newShareToken = new ERC20PresetMinterPauser(newTokenName, baseToken.symbol());
        newShareToken.mint(msg.sender, _amount);
        ShareTokenInfo memory tokenInfo = ShareTokenInfo(_tokenAddress, address(newShareToken), _amount, _releaseTime, msg.sender, true);
        shareTokenList.push(tokenInfo);
        tokenLockers[_tokenAddress].push(shareTokenCount);
        shareTokenIndex[address(newShareToken)] = shareTokenCount;
        shareTokenCount ++;

        return shareTokenIndex[address(newShareToken)];
    }

    /** @notice Release the base token by burning the share token. The user will receive the base token.
     */
    function release(address _shareTokenAddress, uint256 _amount) public {
        // input checks
        require(_amount > 0, "ShareLocker: Token amount is zero.");
        ShareTokenInfo storage tokenInfo = shareTokenList[shareTokenIndex[_shareTokenAddress]];
        require(tokenInfo.isSet == true, "ShareLocker: Share Token does not exist.");
        require(block.timestamp >= tokenInfo.releaseTime, "ShareLocker: current time is before release time.");

        // burn the share token
        ERC20PresetMinterPauser shareToken = ERC20PresetMinterPauser(_shareTokenAddress);
        //require(shareToken.burnFrom(msg.sender, _amount), "ShareLocker: Share Token burnFrom failed.");
        shareToken.burnFrom(msg.sender, _amount);
        tokenInfo.amount = tokenInfo.amount - _amount;

        // release the locked token
        ERC20 baseToken = ERC20(tokenInfo.baseTokenAddress);
        require(baseToken.transfer(msg.sender, _amount), "ShareLocker: Base Token transfer failed.");

    }

    // Getters
    function getShareTokenInfo(uint256 _id) public view returns(ShareTokenInfo memory){
        return shareTokenList[_id];
    }

    // Helpers
    // Convert uint to string https://stackoverflow.com/a/65715388
    function uint2str(uint256 _i) internal pure returns (string memory str){
        if (_i == 0)
        {
            return "0";
        }
        uint256 j = _i;
        uint256 length;
        while (j != 0)
        {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0)
        {
            bstr[--k] = bytes1(uint8(48 + j % 10));
            j /= 10;
        }
        str = string(bstr);
    }

}
