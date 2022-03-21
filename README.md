an optimistic rollup secured by interactive fraud proofs to retrive historical blockhashes\
if the claimed blockhash is from n blocks ago, the fraud proof will take O(log(n)) 

you could store the merkle root of all blockhashes up till a certain block number\
(for users to verfiy before using your app), but this cannot be updated trustlessly so\
it wouldn't work for recent blockhashes after the block number the snapshot was taken.\

this is useful if you want ANY past blockhash, but only a a query by query basis\
if you want every blockhash with eth security, you prob have to store all of them, or get\
validators to store and update a merkle root of all of them see [this](https://ethereum-magicians.org/t/eip-2935-save-historical-block-hashes-in-state/4565)

this method uses 6 SSTOREs per claim, although you could (and should) realistically just store the hash\
and verify against the preimage when desired, I should probably code that up\
(along with tests, and making sure this works, amongst other things)