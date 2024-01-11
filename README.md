# Damn Vulnerable DeFi - Foundry Version ⚒️

A fork of https://github.com/nicolasgarcia214/damn-vulnerable-defi-foundry


## Level 1 : Unstoppable

UnstoppableLender assumes that poolBalance is held in sync with the balance of its address in the ERC20 token, and 
reverts the transaction if this guard is not met. To break the contract, attacker transfers tokens to the lender 
contract outside of the depositTokens method.

## Level 2 : NaiveReceiver

NaiveReceiver doesn't check that the borrower is not the message sender, and therefore the attacker can borrow on the 
victim contract's behalf, draining the contract balance.


## Level 3 : Truster

The suspcicious line in this contract is the functionCall in TrusterLenderPool. Since the target address can be 
specified, a malicious actor can act in the capacity of the borrowing contract. This can then be used to approve the 
transfer of ERC20 tokens to a target account, which is the exploit that drains the pool.

## Level 4 : Side Entrance

This exploit is reminiscent of The UnstoppableLender contract, where there is a discrepancy between an internal 
'balances' variable and the remaining ether in an account.
