+++
title = "It's all about light clients"
date = "2023-09-04T18:12:27+02:00"
author = "pepyakin"
authorTwitter = "pepyakin"
cover = ""
tags = ["rollups", "sharding", "light clients", "fraud proofs", "validity proofs"]
description = "I discuss the notion of state commitment arguments and how they are used to build light clients."
showFullContent = false
readingTime = true
hideComments = false
+++

*Special thanks to [Andre Silva](https://twitter.com/andrebeat), [Bastian Köcher](https://twitter.com/bkchr), [Guillaume Ballet](https://twitter.com/gballet) and [Robert Habermeier](https://twitter.com/rphmeier) for their valuable feedback.*

In this write-up, I will introduce a useful notion of State Commitment Arguments and how they are used by light clients. We will go through the following topics:

1. Full nodes and how they are foundational.
1. Light clients and how they are very important.
1. All flavors of rollups: pessimistic, sovereign, and classic.
1. How this mental model incorporates the upcoming upgrades of ethereum like stateless clients or ZK clients.
1. I will also talk about an Ethereum feature that never happened: sharding.

but first, let's define some notions because I know how hard it is to have discourse these days.

---

Blockchain is a state machine replication system, and as such it is defined by:

1. The **state**.
1. The **input**.
1. The state transition function (**STF**). A function that takes the current state and the inputs and produces the new state. This function is deterministic, meaning that passing the same state and inputs will lead to the same resulting state.

If you take Ethereum, then the state would be the Merkle-Patricia Trie, the STF would be EVM and blocks would act as the input. Well, turns out this is too simplistic for a couple of reasons.

First, in Ethereum, the state transition is not limited to only EVM. Second, and more importantly for this discussion, a block bundles not only inputs but also outputs of the STF, as well as data that is not fed into the STF.

The actual inputs to the STF are the list of transactions (a.k.a. the block body) and values that are observable by EVM (e.g. `timestamp`, `base_fee`) or otherwise participate in the STF (e.g. `fee_recipient`).

Fields such as `state_root`, `receipts_root`, `log_blooms` are outputs. There are several arguments for why they are outputs. First, they are definitely not inputs because they are not used within the STF. They are outputs because they can only be computed by executing the STF.

Before I continue, I think it would be good to give a name for a blockchain construction like this for further discussion. I will call it a **classical blockchain**, and it encompasses chains like Ethereum, everything built on CometBFT and Substrate, and so on.

---

But do the blocks really have to contain the outputs? What would happen if we removed e.g. `state_root`? Would it be even a functional blockchain?

It turns out yes, sort of.

Recall that blockchains replicate a state machine and for that they need inputs. As long as the inputs fed to the STF are the same, it will arrive to the same final state.

I don't think this is a groundbreaking statement. Actually, a real-life example of that is Bitcoin. The state is represented by a set of UTXO, yet, bitcoin blocks do not contain a commitment to that state. It's implied by the inputs.

Note that:

- This property doesn't have anything to do with PoW. In PoS this works exactly the same: the state root is not required for attesting the blocks. The votes can target specific block hashes.
- Block import can never fail due to state root mismatch, because, well, there is no state root to match with.
- Merkle tries help with fork handling, but are not strictly necessary for it. Any [persistent data structure](https://en.wikipedia.org/wiki/Persistent_data_structure) will do and every state can be referred to via the block hash.
- Likewise, merkle tries somewhat help with detecting data corruption. Then again, it's not like every bitflip will be noticed immediately. That also can be solved by a non-cryptographic checksum.

---

But why does almost every modern blockchain have commitments to the state in their blocks? Well, as you guessed it, it's all about the light clients.

> ℹ️ A **light client** is a client that doesn't have access to the full state.
>
> There is a common misconception that light clients are not secure, but that is not true (you probably heard of the term verifying light client). It should become clear why is that in a moment.

The objective of a light client is to obtain a recent state commitment. Given that, it can verify the claims about the committed state from the full nodes. Turns out this is a very useful property because it allows access to the state without having to replay all transactions from the beginning of time. This is great because:

1. Allows for user devices to access the state in a trust-minimized way.
2. Enables more efficient syncing.
3. Enables remote blockchains to establish a view of the state, and thus communicate. This is especially important because replaying the STF within another blockchain STF is not very scalable.

So by adding a state commitment into the blocks, the blockchain would gain all those benefits and by that, we get our classical blockchain. But is this the only way?

---

Two mechanisms allow us to achieve a similar thing that are well-known in the community. Those are fault proofs and validity proofs.

1. Validity proofs. There are two subtypes. SNARK proofs represent a cryptographic argument that shows that a certain claim is correct. Another subtype is reexecution proofs when the claim is re-executed using the merkle proofs (or other commitments) of the parts of the state that were accessed.
1. Fault proofs. Some actor posts a claim that a certain set of inputs results in a certain state commitment. Light clients pencil in the claim. Anybody can produce a proof[^snark-fault-proof] that the claim is invalid. In case nobody produces such commitment, light clients accept the claim as truthful.

[^why-snark-proofs]: I use the term SNARK proofs because validity proofs are also not ideal. See the discussion [here](https://twitter.com/pepyakin/status/1694742040364421260?s=20).

[^snark-fault-proof]: A fault proof can be realized via a SNARK that shows that the inputs do not correspond to the claimed output.

Now if we removed the state commitment from a block and inserted one of the mechanisms above,  we would get a system that has very different properties. Most importantly, you get different trust assumptions for the state commitment. In a classic blockchain, the trustworthiness of the state commitment hinges on the honest majority assumption. SNARK proofs trust assumptions inherit those of the proving system used[^snark-proofs-assumptions]. Reexecution proofs would depend on the state commitment assumptions (e.g. merkle or verkle proofs). Fault proofs depend on the assumption that the evidence can reach the light client within the challenge period.

[^snark-proofs-assumptions]: e.g. things like the proper trusted setup assumption, discrete log hardness assumption, or that your hash function is collision-resistant.

This is one of the reasons I think about those mechanisms as arguments. They are arguments that convince light clients of the recent state. Hence, state commitment *arguments*.

> ℹ️ State Commitment Argument (or **SCA** for short) represents a claim about a recent state of the blockchain and all sufficient proofs that convince a particular light client.
>
> More precisely, it convinces a light client that the state transition function returned the claimed state commitment (e.g. merkle proof) for the given input (e.g. the block/batches and its parents).
>
> Important point: this concept acknowledges the underlying consensus security properties, but abstracts over them. It narrowly focuses on the state aspect.

There are other reasons why it's useful to think about SCAs as separate notions.

A blockchain system can deploy multiple SCAs at the same time. Ethereum being a classical blockchain already uses the classic state commitment argument in the block header (of the execution layer). Ethereum stateless client approach would essentially add re-execution validity proofs and verkle proofs. When that happens, clients that do not possess state will have two options to rely on: either on the SCA based on honest majority or on validity proof SCA. Once again, SCA based on re-execution validity proofs IMO are better arguments than an honest majority, since the assumptions are less strong.

The used SCA is a property of a light client. In other words, different light clients in the same network can use different SCAs. To demonstrate this, consider [this writeup](https://vitalik.ca/general/2023/03/31/zkmulticlient.html) by Vitalik where he is pondering how to preserve the multi-client philosophy in the SNARKified Ethereum future.

> **Open multi ZK-EVM**: Different clients have different ZK-EVM implementations, and each client waits for a proof that is compatible with its own implementation before accepting a block as valid.

Basically, two light clients both based on the same type of an argument (in this case SNARK validity proofs) still can have different implementations, which have the potential to disagree with each other.

You can categorize SCAs by the main medium the argument relies on. Both stateless client and SNARK Ethereum L1 clients would circulate the proofs on the p2p layer, probably in their own subnets. This is in contrast to traditional blockchains where the state roots travel directly in block headers. It's possible to enshrine the validity proofs SCAs in blocks as well (Mina does that). It is also possible to do the same with fault proofs.

Onchain light clients (aka bridges) are also convinced about the remote chain state by an SCA. In this case, the light client is passive: to convince the onchain light client about the new state, somebody has to submit a transaction to the chain it's hosted on. Often SCAs based on either fault or validity proofs are employed. In this framework multi-sigs are also an SCA: the trustworthiness of that argument hinges on the assumption that N-of-M are well-behaved, often without any penalties imposed for them in case they are not.

SCAs are not something that is necessarily provided by the chain, i.e. enshrined. Sure, the state roots in blocks are enshrined, but in other cases, it's not necessary. To show that I have several examples:

1. Anybody can build an end-user light client for Ethereum based on SNARK proofs. No protocol changes to Ethereum are required.
2. Similarly, somebody can deploy an onchain light client of Ethereum based on fault proofs, and again no change on the Ethereum side is required.
3. Finally, another team could present a competing Stateless Ethereum implementation based on other commitments.

In all those cases, they all have to figure out how to incentivize the producers of those proofs, and it's an easy path just to assign validators to it, but I believe this is not an insurmountable issue.

In summary:

1. SCAs can have varying trust assumptions.
2. SCAs can use different mediums: p2p, blocks, transactions.
3. A light client can rely on 1 or more SCAs.
4. SCAs can be enshrined or not.

There are more angles you can view them with, e.g. bandwidth, costs, complexities, and limitations. But I will save them for a follow-up post.

Now, let's examine how different scaling solutions fit into this framework.

**Rollups**. A rollup can be seen as a blockchain (per the definition above) that somehow piggybacks on another blockchain for its data availability ([per Dankrad](https://twitter.com/dankrad/status/1689634128101310464?s=20) all L2 should use the L1's DA).

The most basic rollup is what's called a pessimistic rollup. In order to access its state in a completely trustminimized manner, you gotta have to run a full node (or trust somebody who does).

Then, you can extend it by adding a p2p SCA. Those can be based on the validity or fault proofs, or be as simple as "N-of-M of my peers claimed this state is correct", and with this the rollup gains the ability to have end-user light clients and also more efficient syncing. I think this may qualify as a sovereign rollup.

Finally, if a light client is added on some chain, then that allows for building bridges from the rollup to that chain. If that light client takes a cornerstone place in the rollup, (e.g it may add inputs in addition to the normal route, referred to as force inclusion) then maybe such a rollup can be called a classical rollup.

**Sharding**. Maybe some of you who are familiar with sharding constructions[^sharding-constructions] already noticed similarities between shards and rollups. Both of them are kind of blockchains and both of them have to use the data availability of the parent chain.

[^sharding-constructions]: I consider only Ethereum/Polkadot-like constructions. I admit that there may be other constructions that don't quite fit this mental model, in which case, I would be glad to hear about them.

The important difference is in the arrangement, it commonly has two parts:

1. How validators learn about the shard state, and thus they are light clients of the shard[^shard-validators-are-light-clients]. Typically, a validity proof based on re-execution is used to convince the validator of the state of the shard chain.
2. How the main (/beacon/relay) chain learns about the shard state. The main chain is typically convinced by the signatures of validators.

[^shard-validators-are-light-clients]: Validators can theoretically be full nodes of a validated shard. However, in reality, validators need to be reshuffled between the shards, and thus, need to essentially be light clients of the validated shard. A validator cannot be a full node of every shard because that defies the purpose of sharding in the first place.

The different SCAs are the source of different tradeoffs between sharding and rollups. Theoretically, the former would have better latency but rollups may potentially achieve higher throughput. I may probably talk more about this in the following posts.

To close it off I'd say that not every combination of SCA and use-case would make sense. Each of them has tradeoffs on multiple axes. Validity proofs based on re-execution would make a bad onchain client. Fault proofs practically don't have throughput constraints, but have high latency due to the challenge periods.

### Conclusion

Full nodes don't require any specific arguments, they always know the right state. The light clients don't possess the state and need to rely on third parties to provide them with that state. To be sure of the state the light clients need a convincing argument about the latest state, referred to as SCAs.

All those mechanisms are needed to make various flavors of light clients possible. It may seem that light clients are something secondary. The simplest blockchains do not require any specific SCAs, but those blockchains have limited applicability: they can't convince outside entities about the state, and introducing light clients solves it.

So in fact light clients are very much important, so that it's worth jumping through the hoops. Luckily, the toolkit of SCA is growing each day.
