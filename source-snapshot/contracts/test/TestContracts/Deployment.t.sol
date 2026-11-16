// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "src/AddressesRegistry.sol";
import "src/ActivePool.sol";
import "src/JpydfToken.sol";
import "src/BorrowerOperations.sol";
import "src/CollSurplusPool.sol";
import "src/DefaultPool.sol";
import "src/GasPool.sol";
import "src/HintHelpers.sol";
import "src/MultiTroveGetter.sol";
import "src/SortedTroves.sol";
import "src/DFStabilityPool.sol";
import "./BorrowerOperationsTester.t.sol";
import "./TroveManagerTester.t.sol";
import "./CollateralRegistryTester.sol";
import "src/JPYdfTroveNFT.sol";
import "src/NFTMetadata/JPYdfMetadataNFT.sol";
import "src/CollateralRegistry.sol";
import "src/Interfaces/IMetadataNFT.sol";
import "./MockInterestRouter.sol";
import "./PriceFeedTestnet.sol";
import "./MetadataDeployment.sol";
import {WETHTester} from "./WETHTester.sol";
import {ERC20Faucet} from "./ERC20Faucet.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

import "forge-std/console2.sol";

contract TestBridgeRoleHolder {}

// TODO: Split dev and mainnet
contract TestDeployer is MetadataDeployment {
    using Strings for uint256;

    bytes32 constant SALT = keccak256("LiquityV2");
    address public riskParamsFinalizer;

    function setRiskParamsFinalizer(address _riskParamsFinalizer) external {
        riskParamsFinalizer = _riskParamsFinalizer;
    }

    struct LiquityContractsDevPools {
        IDefaultPool defaultPool;
        ICollSurplusPool collSurplusPool;
        GasPool gasPool;
    }

    struct LiquityContractsDev {
        IAddressesRegistry addressesRegistry;
        IBorrowerOperationsTester borrowerOperations; // Tester
        ISortedTroves sortedTroves;
        IActivePool activePool;
        IStabilityPool stabilityPool;
        ITroveManagerTester troveManager; // Tester
        ITroveNFT troveNFT;
        IPriceFeedTestnet priceFeed; // Tester
        IInterestRouter interestRouter;
        IERC20Metadata collToken;
        LiquityContractsDevPools pools;
    }

    struct LiquityContracts {
        IAddressesRegistry addressesRegistry;
        IActivePool activePool;
        IBorrowerOperations borrowerOperations;
        ICollSurplusPool collSurplusPool;
        IDefaultPool defaultPool;
        ISortedTroves sortedTroves;
        IStabilityPool stabilityPool;
        ITroveManager troveManager;
        ITroveNFT troveNFT;
        IPriceFeed priceFeed;
        GasPool gasPool;
        IInterestRouter interestRouter;
        IERC20Metadata collToken;
    }

    struct Zappers {
        bool unused;
    }

    struct LiquityContractAddresses {
        address activePool;
        address borrowerOperations;
        address collSurplusPool;
        address defaultPool;
        address sortedTroves;
        address stabilityPool;
        address troveManager;
        address troveNFT;
        address metadataNFT;
        address priceFeed;
        address gasPool;
        address interestRouter;
    }

    uint256 public collGasCompensationCap = COLL_GAS_COMPENSATION_CAP;

    function setCollGasCompensationCap(uint256 _cap) external {
        collGasCompensationCap = _cap;
    }

    struct TroveManagerParams {
        uint256 CCR;
        uint256 MCR;
        uint256 BCR;
        uint256 SCR;
        uint256 LIQUIDATION_PENALTY_SP;
        uint256 LIQUIDATION_PENALTY_REDISTRIBUTION;
    }

    struct DeploymentVarsDev {
        uint256 numCollaterals;
        IERC20Metadata[] collaterals;
        IAddressesRegistry[] addressesRegistries;
        ITroveManager[] troveManagers;
        bytes bytecode;
        address jpydfTokenAddress;
        uint256 i;
    }

    // See: https://solidity-by-example.org/app/create2/
    function getBytecode(bytes memory _creationCode, address _addressesRegistry) public pure returns (bytes memory) {
        return abi.encodePacked(_creationCode, abi.encode(_addressesRegistry));
    }

    function getAddress(address _deployer, bytes memory _bytecode, bytes32 _salt) public pure returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), _deployer, _salt, keccak256(_bytecode)));

        // NOTE: cast last 20 bytes of hash to address
        return address(uint160(uint256(hash)));
    }

    function deployAndConnectContracts()
        external
        returns (
            LiquityContractsDev memory contracts,
            ICollateralRegistry collateralRegistry,
            IJpydfToken jpydfToken,
            HintHelpers hintHelpers,
            MultiTroveGetter multiTroveGetter,
            IWETH WETH, // for gas compensation
            Zappers memory zappers
        )
    {
        return deployAndConnectContracts(TroveManagerParams(150e16, 110e16, 10e16, 110e16, 5e16, 10e16));
    }

    function deployAndConnectContracts(TroveManagerParams memory troveManagerParams)
        public
        returns (
            LiquityContractsDev memory contracts,
            ICollateralRegistry collateralRegistry,
            IJpydfToken jpydfToken,
            HintHelpers hintHelpers,
            MultiTroveGetter multiTroveGetter,
            IWETH WETH, // for gas compensation
            Zappers memory zappers
        )
    {
        LiquityContractsDev[] memory contractsArray;
        TroveManagerParams[] memory troveManagerParamsArray = new TroveManagerParams[](1);
        Zappers[] memory zappersArray;

        troveManagerParamsArray[0] = troveManagerParams;

        (contractsArray, collateralRegistry, jpydfToken, hintHelpers, multiTroveGetter, WETH, zappersArray) =
            deployAndConnectContractsMultiColl(troveManagerParamsArray);
        contracts = contractsArray[0];
        zappers = zappersArray[0];
    }

    function deployAndConnectContractsMultiColl(TroveManagerParams[] memory troveManagerParamsArray)
        public
        returns (
            LiquityContractsDev[] memory contractsArray,
            ICollateralRegistry collateralRegistry,
            IJpydfToken jpydfToken,
            HintHelpers hintHelpers,
            MultiTroveGetter multiTroveGetter,
            IWETH WETH, // for gas compensation
            Zappers[] memory zappersArray
        )
    {
        // used for gas compensation and as collateral of the first branch
        WETH = new WETHTester(
            100 ether, //     _tapAmount
            1 days //         _tapPeriod
        );
        (contractsArray, collateralRegistry, jpydfToken, hintHelpers, multiTroveGetter, zappersArray) =
            deployAndConnectContracts(troveManagerParamsArray, WETH);
    }

    function _nameToken(uint256 _index) internal pure returns (string memory) {
        return string.concat("Test Collateral ", uint256(_index).toString());
    }

    function _symboltoken(uint256 _index) internal pure returns (string memory) {
        return string.concat("COL", uint256(_index).toString());
    }

    function _newBridgeRoleHolder() internal returns (address) {
        return address(new TestBridgeRoleHolder());
    }

    function deployAndConnectContracts(TroveManagerParams[] memory troveManagerParamsArray, IWETH _WETH)
        public
        returns (
            LiquityContractsDev[] memory contractsArray,
            ICollateralRegistry collateralRegistry,
            IJpydfToken jpydfToken,
            HintHelpers hintHelpers,
            MultiTroveGetter multiTroveGetter,
            Zappers[] memory zappersArray
        )
    {
        DeploymentVarsDev memory vars;
        vars.numCollaterals = troveManagerParamsArray.length;
        // Deploy Bold
        address bridgeAdmin = _newBridgeRoleHolder();
        vars.bytecode = abi.encodePacked(type(JpydfToken).creationCode, abi.encode(address(this), bridgeAdmin));
        vars.jpydfTokenAddress = getAddress(address(this), vars.bytecode, SALT);
        jpydfToken = new JpydfToken{salt: SALT}(address(this), bridgeAdmin);
        assert(address(jpydfToken) == vars.jpydfTokenAddress);

        contractsArray = new LiquityContractsDev[](vars.numCollaterals);
        zappersArray = new Zappers[](vars.numCollaterals);
        vars.collaterals = new IERC20Metadata[](vars.numCollaterals);
        vars.addressesRegistries = new IAddressesRegistry[](vars.numCollaterals);
        vars.troveManagers = new ITroveManager[](vars.numCollaterals);

        // Deploy the first branch with WETH collateral
        vars.collaterals[0] = _WETH;
        (IAddressesRegistry addressesRegistry, address troveManagerAddress) =
            _deployAddressesRegistryDev(troveManagerParamsArray[0]);
        vars.addressesRegistries[0] = addressesRegistry;
        vars.troveManagers[0] = ITroveManager(troveManagerAddress);
        for (vars.i = 1; vars.i < vars.numCollaterals; vars.i++) {
            IERC20Metadata collToken = new ERC20Faucet(
                _nameToken(vars.i), // _name
                _symboltoken(vars.i), // _symbol
                100 ether, //     _tapAmount
                1 days //         _tapPeriod
            );
            vars.collaterals[vars.i] = collToken;
            // Addresses registry and TM address
            (addressesRegistry, troveManagerAddress) = _deployAddressesRegistryDev(troveManagerParamsArray[vars.i]);
            vars.addressesRegistries[vars.i] = addressesRegistry;
            vars.troveManagers[vars.i] = ITroveManager(troveManagerAddress);
        }

        collateralRegistry = new CollateralRegistry(jpydfToken, vars.collaterals, vars.troveManagers);
        hintHelpers = new HintHelpers(collateralRegistry);
        multiTroveGetter = new MultiTroveGetter(collateralRegistry);

        (contractsArray[0], zappersArray[0]) = _deployAndConnectCollateralContractsDev(
            _WETH,
            jpydfToken,
            collateralRegistry,
            _WETH,
            vars.addressesRegistries[0],
            address(vars.troveManagers[0]),
            hintHelpers,
            multiTroveGetter
        );

        // Deploy the remaining branches with generic test collateral
        for (vars.i = 1; vars.i < vars.numCollaterals; vars.i++) {
            (contractsArray[vars.i], zappersArray[vars.i]) = _deployAndConnectCollateralContractsDev(
                vars.collaterals[vars.i],
                jpydfToken,
                collateralRegistry,
                _WETH,
                vars.addressesRegistries[vars.i],
                address(vars.troveManagers[vars.i]),
                hintHelpers,
                multiTroveGetter
            );
        }

        jpydfToken.setCollateralRegistry(address(collateralRegistry));
    }

    function _deployAddressesRegistryDev(TroveManagerParams memory _troveManagerParams)
        internal
        returns (IAddressesRegistry, address)
    {
        IAddressesRegistry addressesRegistry = new AddressesRegistry(
            address(this),
            _troveManagerParams.CCR,
            _troveManagerParams.MCR,
            _troveManagerParams.BCR,
            _troveManagerParams.SCR,
            _troveManagerParams.LIQUIDATION_PENALTY_SP,
            _troveManagerParams.LIQUIDATION_PENALTY_REDISTRIBUTION,
            riskParamsFinalizer
        );
        address troveManagerAddress = getAddress(
            address(this), abi.encodePacked(type(TroveManagerTester).creationCode, abi.encode(addressesRegistry, collGasCompensationCap)), SALT
        );

        return (addressesRegistry, troveManagerAddress);
    }

    function _deployAndConnectCollateralContractsDev(
        IERC20Metadata _collToken,
        IJpydfToken _jpydfToken,
        ICollateralRegistry _collateralRegistry,
        IWETH _weth,
        IAddressesRegistry _addressesRegistry,
        address _troveManagerAddress,
        IHintHelpers _hintHelpers,
        IMultiTroveGetter _multiTroveGetter
    ) internal returns (LiquityContractsDev memory contracts, Zappers memory zappers) {
        LiquityContractAddresses memory addresses;
        contracts.collToken = _collToken;

        // Deploy all contracts, using testers for TM and PriceFeed
        contracts.addressesRegistry = _addressesRegistry;
        contracts.priceFeed = new PriceFeedTestnet();
        contracts.interestRouter = new MockInterestRouter();

        // Deploy Metadata
        JPYdfMetadataNFT metadataNFT = deployJPYdfMetadata(SALT);
        addresses.metadataNFT = getAddress(
            address(this), getBytecode(type(JPYdfMetadataNFT).creationCode, address(initializedFixedAssetReader)), SALT
        );
        assert(address(metadataNFT) == addresses.metadataNFT);

        // Pre-calc addresses
        addresses.borrowerOperations = getAddress(
            address(this),
            getBytecode(type(BorrowerOperationsTester).creationCode, address(contracts.addressesRegistry)),
            SALT
        );
        addresses.troveManager = _troveManagerAddress;
        addresses.troveNFT = getAddress(
            address(this), getBytecode(type(JPYdfTroveNFT).creationCode, address(contracts.addressesRegistry)), SALT
        );
        addresses.stabilityPool = getAddress(
            address(this), getBytecode(type(DFStabilityPool).creationCode, address(contracts.addressesRegistry)), SALT
        );
        addresses.activePool = getAddress(
            address(this), getBytecode(type(ActivePool).creationCode, address(contracts.addressesRegistry)), SALT
        );
        addresses.defaultPool = getAddress(
            address(this), getBytecode(type(DefaultPool).creationCode, address(contracts.addressesRegistry)), SALT
        );
        addresses.gasPool = getAddress(
            address(this), getBytecode(type(GasPool).creationCode, address(contracts.addressesRegistry)), SALT
        );
        addresses.collSurplusPool = getAddress(
            address(this), getBytecode(type(CollSurplusPool).creationCode, address(contracts.addressesRegistry)), SALT
        );
        addresses.sortedTroves = getAddress(
            address(this), getBytecode(type(SortedTroves).creationCode, address(contracts.addressesRegistry)), SALT
        );

        // Deploy contracts
        IAddressesRegistry.AddressVars memory addressVars = IAddressesRegistry.AddressVars({
            collToken: _collToken,
            borrowerOperations: IBorrowerOperations(addresses.borrowerOperations),
            troveManager: ITroveManager(addresses.troveManager),
            troveNFT: ITroveNFT(addresses.troveNFT),
            metadataNFT: IMetadataNFT(addresses.metadataNFT),
            stabilityPool: IStabilityPool(addresses.stabilityPool),
            priceFeed: contracts.priceFeed,
            activePool: IActivePool(addresses.activePool),
            defaultPool: IDefaultPool(addresses.defaultPool),
            gasPoolAddress: addresses.gasPool,
            collSurplusPool: ICollSurplusPool(addresses.collSurplusPool),
            sortedTroves: ISortedTroves(addresses.sortedTroves),
            interestRouter: contracts.interestRouter,
            hintHelpers: _hintHelpers,
            multiTroveGetter: _multiTroveGetter,
            collateralRegistry: _collateralRegistry,
            jpydfToken: _jpydfToken,
            WETH: _weth
        });
        contracts.addressesRegistry.setAddresses(addressVars);

        contracts.borrowerOperations = new BorrowerOperationsTester{salt: SALT}(contracts.addressesRegistry);
        contracts.troveManager = new TroveManagerTester{salt: SALT}(contracts.addressesRegistry, collGasCompensationCap);
        contracts.troveNFT = new JPYdfTroveNFT{salt: SALT}(contracts.addressesRegistry);
        contracts.stabilityPool = new DFStabilityPool{salt: SALT}(contracts.addressesRegistry);
        contracts.activePool = new ActivePool{salt: SALT}(contracts.addressesRegistry);
        contracts.pools.defaultPool = new DefaultPool{salt: SALT}(contracts.addressesRegistry);
        contracts.pools.gasPool = new GasPool{salt: SALT}(contracts.addressesRegistry);
        contracts.pools.collSurplusPool = new CollSurplusPool{salt: SALT}(contracts.addressesRegistry);
        contracts.sortedTroves = new SortedTroves{salt: SALT}(contracts.addressesRegistry);

        assert(address(contracts.borrowerOperations) == addresses.borrowerOperations);
        assert(address(contracts.troveManager) == addresses.troveManager);
        assert(address(contracts.troveNFT) == addresses.troveNFT);
        assert(address(contracts.stabilityPool) == addresses.stabilityPool);
        assert(address(contracts.activePool) == addresses.activePool);
        assert(address(contracts.pools.defaultPool) == addresses.defaultPool);
        assert(address(contracts.pools.gasPool) == addresses.gasPool);
        assert(address(contracts.pools.collSurplusPool) == addresses.collSurplusPool);
        assert(address(contracts.sortedTroves) == addresses.sortedTroves);

        // Connect contracts
        _jpydfToken.setBranchAddresses(
            address(contracts.troveManager),
            address(contracts.stabilityPool),
            address(contracts.borrowerOperations),
            address(contracts.activePool)
        );

        // deploy zappers
        _deployZappers(contracts.addressesRegistry, contracts.collToken, _jpydfToken, _weth, false, zappers);
    }

    function _deployZappers(
        IAddressesRegistry _addressesRegistry,
        IERC20 _collToken,
        IJpydfToken _jpydfToken,
        IWETH _weth,
        bool _mainnet,
        Zappers memory zappers // result
    ) internal pure {
        _addressesRegistry;
        _collToken;
        _jpydfToken;
        _weth;
        _mainnet;
        zappers;
    }
}
