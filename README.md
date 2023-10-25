# Proveably random raffle contracts.

## About
This is my first project using Chainlink VRF for true randomness.

## What does it do?

1. Users can enter the lottery by paying for a ticket
   1. The ticket fees go to the winner of the draw
2. After X period of time, the lottery automatically draws a winner programatically
3. This lottery uses Chainlink VRF & Chainlink Automation
   1. Chainlink VRF -> Randomness
   2. Chainlin Automatique -> Time based trigger

## Tests
1. Write deploy scripts
2. Write tests:
   1. Work on Anvil
   2. Forked Testnet
   3. Forked Mainnet
