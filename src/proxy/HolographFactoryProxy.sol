HOLOGRAPH_LICENSE_HEADER

pragma solidity 0.8.11;

import "../abstract/Admin.sol";
import "../abstract/Initializable.sol";

import "../interface/IInitializable.sol";

contract HolographFactoryProxy is Admin, Initializable {

    constructor() Admin(false) {}

    function init(bytes memory data) external override returns (bytes4) {
        require(!_isInitialized(), "HOLOGRAPH: already initialized");
        (address factory) = abi.decode(data, (address));
        assembly {
            sstore(precomputeslot('eip1967.Holograph.Bridge.factory'), factory)
        }
        _setInitialized();
        return IInitializable.init.selector;
    }

    function getFactory() external view returns (address factory) {
        // The slot hash has been precomputed for gas optimizaion
        // bytes32 slot = bytes32(uint256(keccak256('eip1967.Holograph.Bridge.factory')) - 1);
        assembly {
            factory := sload(/* slot */precomputeslot('eip1967.Holograph.Bridge.factory'))
        }
    }

    function setFactory(address factory) external onlyAdmin {
        // The slot hash has been precomputed for gas optimizaion
        // bytes32 slot = bytes32(uint256(keccak256('eip1967.Holograph.Bridge.factory')) - 1);
        assembly {
            sstore(/* slot */precomputeslot('eip1967.Holograph.Bridge.factory'), factory)
        }
    }

    receive() external payable {
    }

    fallback() external payable {
        assembly {
            let factory := sload(precomputeslot('eip1967.Holograph.Bridge.factory'))
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), factory, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

}
