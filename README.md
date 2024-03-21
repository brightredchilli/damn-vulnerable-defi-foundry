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

## Level 5 : Rewarder

This seems more like a 'legal' exploit, leveraging a flashloan to gain get a considerable number of rewards.

## Level 6 : Selfie

Another flashloan like hack, but with a level of indirection. The pool is restricted by actions only by the governance 
contract. A flashloan allows the attacker to get enough governance tokens to control the pool.

## Level 7 : Compromised

Not immediately clear how to backtrack keys from the web response, but eventually used some python to extract a private 
key looking string, and using python utils, converted that to an appropriatte uint256 format.

The exploit then involved resetting the price of a token using the trusted oracles, buying, then reselling again after 
resetting the price.


## Level 8 : Puppet

The crux of this vulnerability is that the 'Oracle' source for a smart contract becomes an unguarded, ignored dependency 
- in this case, the old UniswapV1 endpoint which people seems to have forgotten. Crypto projects expect efficient 
markets, and in this case this was not the case. By manipulating the price of the dependency, the main project was 
compomised to yield an unusually low lending rate - in this case, from 1e23 DVT = 2e23 wei to 1e23 DVT = 1.9e19 wei. The 
swap was at 100 DVT = 9.9e1 wei before, and after depositing DVT into the swap, 100 DVT = 0e0 wei.



## Level 9 : PuppetV2

This exploit is similar to the previous one, in this case manipulating a Uniswap Pair's reserve ratio to then allow a 
favorable borrowing rate. The attacker swaps his available DVT for WETH, putting more DVT into the Swap Pair, diluting 
DVT. In return, attacker gets even more WETH that they can use to borrow.

