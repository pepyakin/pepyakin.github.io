+++
title = "Parachains Consensus Explainer"
date = "2022-11-07T14:11:26+01:00"
author = "pepyakin"
authorTwitter = "pepyakin"
cover = ""
tags = ["polkadot"]
description = "Brief explaination of how Polkadot sharded consensus works."
showFullContent = false
readingTime = true
hideComments = false
+++

This post will briefly explain how Polkadot Consensus enables Parachain validation.

Polkadot is a sharded blockchain. It is composed of parachains and the relay chain. The relay chain is the
main chain, and parachains can be considered shards. Unlike typical sharded chains, in Polkadot shards are entirely programmable.

Here I want to focus on the consensus part of the story.

## Logical View of a Parachain

Just like any blockchain, parachain is defined by a state transition function. The state transition
function specifies how the state of the chain changes after applying a given set of transactions. We
refer to such a function as a parachain validation function (**PVF**).

PVF is represented as a WebAssembly module. On a high level, PVF takes the current state of the
parachain, a set of transactions, and produces a new state of the parachain. In order to deploy a
parachain, one has to provide a PVF and the initial state of the chain (genesis).

PVFs are executed by Polkadot validators. As usual with sharding, validators do not store the
state of each parachain since that would be prohibitively expensive and defy the purpose of sharding.
Therefore, PVFs only occupy a very limited state on the relay chain, something in the range of kilobytes. Typically, only the current parachain block header is stored there. That means that in order to execute a set of transactions, the values accessed on the course of execution of those transactions with the
corresponding merkle proofs must be provided to the PVF. We call the combination of the transactions
and the merkle proofs a proof-of-validity (**PoV**).


```goat
+----------------+
|   old state    |
|================|
|                |
|  block number  |
| -------------- |
|  parent hash   .----------.                                    +-------------------+
| -------------- |           |                                   |     new state     |
|   state root   |           |                                   +===================+
| -------------- |           |                                   |                   |
|      etc...    |           |     +----------------+            |   block number    |
+----------------+           '---->|                |            | ----------------- |
                                   |   PVF (Wasm)   .----------->|    parent hash    |
+----------------+           .---->|                |            | ----------------- |
|     PoV        |           |     +----------------+            |    state root     |
|================|           |                                   | ----------------- |
|                |           |                                   |      etc...       |
|   new header   |           |                                   +-------------------+
| -------------- |           |
|  transactions  .----------'
| -------------- |
|  merkle proofs |
| -------------- |
|      etc...    |
+----------------+
```

Note that I said typically. That is because Polkadot does not impose any restrictions on how the
state nor PoV is represented. In fact, those are opaque blobs to validators, and PVF is free to
interpret them in any way it wants.

Example: a ZK parachain. The state stores the current state root, the PoV stores the transaction
list, the ZK proof, and the new state root. The PVF just verifies the ZK proof and
updates the state root.

Another rather extreme example: a parachain storing only a counter in the state. The PVF just
increments the counter by the value given in the PoV. No merkle trie is used.

The size of the state part is limited to several kilobytes. The size of the PoV is currently limited
by around 4 MiB[^only-just-an-example] and is planned to be increased to 16 MiB in the future. As long as you can fit
your state and PoV into those limits and represent your state transition function as a WebAssembly
module, you can deploy a parachain on Polkadot.

### Consensus

The Polkadot relay chain has 1000[^only-just-an-example] validators. However, only
300[^only-just-an-example] of them are actively participating in the consensus. This makes up the
active validator set. This set changes approximately every 4[^only-just-an-example] hours.

Validators from the active validator list can extend the relay chain with new blocks. A validator
is selected utilizing a VRF[^vrf]. Simply speaking, the validators roll a dice, and one (or more) lucky
validator is chosen to create a new block. The mechanism is called [BABE].

The finalization of the relay chain blocks is done by [GRANDPA]. Again without diving into details, in GRANDPA, the validators from the active validator set are voting on the head of the chain they
believe to be the best. The finalization is achieved when a supermajority of validators vote for
the chain[^grandpa-why-chain].

Validators from the active validator set are also responsible for attesting parachain candidates in a process called **backing**. The active validator set is split into groups of 5 validators[^only-just-an-example]. Each group is
responsible for validating a particular parachain. The groups' assignments to parachains change every few blocks.

<figure>

```goat

+-All Validators--------------------------------------+
|                                                     |
| +-Active Validators----+                            |
| |                      |                            |
| | +-Backing Group 1--+ |                            |
| | |  .-.      .-.    | |                            |
| | | | 1 |    | 2 |   | |                            |
| | |  '-'      '-'    | |                            |
| | +------------------+ |                            |
| |                      |                            |
| | +-Backing Group 2--+ |                            |
| | |  .-.      .-.    | |      .-.    .-.     .-.    |
| | | | 3 |    | 4 |   | |     | 7 |  | 8 |   | 9 |   |
| | |  '-'      '-'    | |      '-'    '-'     '-'    |
| | +------------------+ |                            |
| |                      |                            |
| | +-Backing Group 3--+ |                            |
| | |  .-.      .-.    | |                            |
| | | | 5 |    | 6 |   | |                            |
| | |  '-'      '-'    | |                            |
| | +------------------+ |                            |
| +----------------------+                            |
+-----------------------------------------------------+
```

In the figure above, the validators are represented with numbers. The validators 7-9 are inactive
and do not participate in the consensus actively, at least not in the current session. 1-6 are active.
1-2, 3-4, and 5-6 make up the backing groups 1, 2, and 3, respectively.

To advance the state of a parachain, a PoV is required. In reality, the validators also need a piece
of data that sums up the state transition. Let's call that piece of data a receipt and the combination
of the receipt and the PoV a parachain **candidate**.

Validators do not create candidates but only attest to them. It's the job of nodes that are not a part
of the parachain consensus to create candidates. Those nodes are called **collators**. Typically,
those are full nodes on the parachain network. They collect transactions, create a parachain block
and a corresponding candidate, then submit it to the validators. If you are familiar with rollups,
you can think of collators similar to sequencers.

Once created, a candidate is sent to a validator in the appropriate backing group. The validator runs the PVF
with the given PoV and the current state found on the relay chain. If the candidate turns out to be
valid, the validator circulates the candidate to other validators in the backing group. Once validators check the candidate, they issue a backing statement. Those backing statements are gossiped to all
the validators in the active set.

When it's time to create the next relay chain block, the block author would include the candidates
that have received enough backing statements into the new block. It's worth noting that only the
receipt part of the candidate is included on the relay chain. At this point, only the backing
group possesses the full PoV.

The next step is ensuring **availability**. Sending and storing whole PoVs is prohibitively expensive.
So PoVs are split into chunks and distributed among validators. So Polkadot leverages erasure coding
to split the PoV into chunks, and a large subset of chunks can recover the original PoV. Each validator
stores only one chunk for a particular PoV. The protocol works as follows. If a validator from the active set notices
a candidate included in the relay chain, it requests the chunk from the validators that backed that
candidate. Once the chunk reaches the validator, it signs and gossips a statement within the active
validator set. The next relay chain block author includes all the signed statements into the block.
As soon as enough statements confirming possession of chunks are included, the candidate is considered
available.

Once the candidate is available the state transition is considered effectful. That is, the new state
returned by the PVF is saved in the relay chain, messages sent by the parachain are dispatched, etc.

Note, however, that so far the candidate was checked only by 5[^only-just-an-example] validators. Even though the backing
groups are chosen randomly, it's still possible that validators in the backing group colluded and
produced a bad candidate. That's because backing does not really contribute to overall security. The actual
security is provided by the **approval** process.

Above I mentioned that GRANDPA finalizes the relay chain blocks. I did not mention though that
GRANDPA will only consider a relay chain block ready for finalization if all the candidates included
are approved.

Approvals are done by the validators from the active set. The process is triggered for each candidate
once it's available. The approval validators would try to reconstruct the PoV, run the PVF and verify
the result. At the end of the process, the validator issues an approval vote.

The mechanism is designed to:

- Not reveal the identity of the validators until the last moment. Here, Polkadot relies on VRFs again.
- Ensure that the validators are randomly distributed across the active validator set.
- Ensure to deliver at least the minimum number of approval votes.

In case an assigned validator does not approve the candidate in time, then more approvers are assigned
for that candidate.

On average, only 40[^only-just-an-example] approval validators check any given candidate. It's not a
big number, but the probability of a bad candidate being approved is astronomically small.

One last mechanism I want to mention is **disputes**. This mechanism is designed to ensure that each
attempt to misbehave is caught. While the backing and approval mechanisms work within a single fork, the disputes mechanism can catch misbehaviors that occur across multiple forks.

Let's reiterate the lifecycle of a parachain candidate:

1. A candidate for a parachain is created by that parachain's collator.
1. The candidate is sent to a validator in the parachain's backing group.
1. The validator shares the candidate with other validators from the same group if the candidate is OK.
1. The relay chain block author includes the candidate into the relay chain block.
1. All validators fetch the chunks of the candidate's PoV and broadcast a signed statement confirming possession of the chunk. The statements are included in the relay chain block.
1. The approval process is run and the relay chain block is now ready for finalization.

At this point, the parachain can treat that block as finalized.

## Conclusion

I hope I provided a good overview of the Polkadot consensus and how parachains work. See the [Polkadot v1.0 blog post][Polkadot Sharding]. Also [Polkadot Book] is also worth a look.

[^grandpa-why-chain]: Why chain? Why not a block? This is how GRANDPA works, it does not finalize
individual blocks, it finalizes subchains. Given different validators voting for different chains,
that last common block of those chains will be finalized. More details [here][GRANDPA].

[^only-just-an-example]: This number is for illustration purposes only. One of the reasons for this
is that the chain is evolving quickly, and the actual number might have changed by the time you read this.
Also, the numbers might differ between e.g. Polkadot and Kusama.

[^vrf]: VRF stands for Verifiable Random Function. Read more [here][VRF].

[Polkadot Sharding]: https://polkadot.network/blog/polkadot-v1-0-sharding-and-economic-security/
[Polkadot Book]: https://paritytech.github.io/polkadot/book/
[VRF]: https://wiki.polkadot.network/docs/learn-randomness#:~:text=VRF%E2%80%8B,random%20number%20generation%20is%20valid.
[BABE]: https://polkadot.network/blog/polkadot-consensus-part-3-babe/
[GRANDPA]: https://polkadot.network/blog/polkadot-consensus-part-2-grandpa/
