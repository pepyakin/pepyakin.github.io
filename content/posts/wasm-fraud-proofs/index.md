+++
title = "Why Wasm is not the best format for Fraud Proofs"
description = "In this article I'll dive into why Wasm isn't suited for interactive fraud proofs."
date = "2022-09-01T16:00:00+00:00"
authorTwitter = "pepyakin" #do not include @
tags = ["wasm", "fraud proofs", "rollups"]
cover = ""
showFullContent = false
readingTime = false
hideComments = false
+++

I work at Parity on various stuff. I can highlight WebAssembly and Parachains. One of the products it has is a blockchain framework called Substrate. In a nutshell, the chain developer provides a WebAssembly blob that controls the blockchain's various aspects (such as validating transactions), and the rest is handled by Substrate. Right now, Substrate can be used to build a standalone chain, or it can be used to make a parachain (or, in the future, a pay-as-you-go version, a parathread).

Since we delivered parachains, it was time for me to look around. I've been following rollup tech with interest. Naturally, that led me to play with the idea of adding another way of using Substrate: to create an optimistic rollup and allow anchoring the chain to a data-availability layer — one of the existing parachains, a dedicated DA parachain, Celestia or Ethereum.

The crucial component to enable this is a fraud-proof protocol.

After playing with it, I concluded that **Wasm is not a good fit for fraud proofs**.

Before diving in, let's establish a common understanding of fraud proofs.

## Fraud Proofs

There are two roles: claimer and challenger. The claimer performs some computation that takes some inputs and publishes the output. The challenger can initiate a challenge that disputes that claim if they think it is wrong.

I know of two kinds of fraud-proof protocols: one-round fraud proofs and interactive fraud proofs (**IFP**). I will focus only on IFP here since I believe it is superior to one-round in the context of rollups[^2].

IFP requires the claimer and the challenger to divide the computation into steps. The computation state at each step can be described as a short commitment. Typically, meaning that the VM state should be merkelized[^4]. The commitment encompasses the output of the VM. The claim contains the commitment to the final step of the computation. The challenge will have its version of the hash. If the final step between the claim and challenge are equal, then the outputs must be identical, which means such a challenge is invalid. The first step commitment of the computation is implicitly known.

Then the claimer and the challenger divide the computation in half and compare the VM state commitments. If they are the same, then the discrepancy must have happened on the right half; otherwise, on the left. They keep reducing computation until a single step is left. The claimer and challenger agree on the starting state (pre-state) but disagree on the state after the step (post-state).

The challenge is resolved by re-executing this single step. Typically, such a step would be some kind of instruction. For example, the instruction `r0 = r1 + r2` would take the registers `r1` and `r2` values, add them and save the result into `r0`. Using the pre-state commitment, one can get the values of the `r1` and `r2`. Computing the state commitment after updating `r0` gives the post-state.

If the challenger turns out to be right, the original claim is reverted. The loser has to suffer a fine. If a party decides not to participate, they automatically lose. If the claim goes unchallenged for a certain amount of time, that claim is assumed to be correct and final. The whole protocol is typically implemented as an on-chain smart contract.

Now, with that out of the way, I want to argue that WebAssembly is not a good fit for implementing IFP.

## Wasm

Let's walk through different corners of WebAssembly that, in my opinion, make IFP hard.

### Control Flow

One notorious effect is that Wasm expresses control flow via constructions not too dissimilar to `if`-s, `while`-s, and `switch`-es found in your favorite high-level language. Consider the following code:

```wasm
local.get $x
if
    call $a
else
    call $b
end
```

That is an actual wasm code. Each instruction occupies a line.

As you might expect, if the variable `x` is non-zero, the control flows into the `then` block and calls the function `$a`. Otherwise, the control flows into the `else` block and calls the function `$b`.

When interpreting the `if` instruction, the offset of the `else` marker instruction should be known. Likewise, the same is true for `else` and `end`.

In the context of IFP, the on-chain verifier should get those offsets from somewhere. It will become clear later why this is a problem, but ultimately it has to do with unnecessary complexity.

### Typedness

WebAssembly is strongly typed. There are at least 4 types: i32, i64, f32, f64, and some other types were added by extensions like v128 or reference-like values. Before execution, the code is validated, including checking the types. It's a nice property that comes in handy when compiling Wasm, but it's not entirely necessary for runtime execution (e.g., i64 can subsume i32 operations). Frankly, i32 should be enough for everyone.

However, there are some dark corners of the wasm standard. E.g. statically unreachable code is a subject for a weird type-checking semantics (see e.g. [this](https://binji.github.io/posts/webassembly-type-checking/) or [this](https://webassembly.github.io/spec/core/appendix/algorithm.html)). While unreachable code is never executed, the verifier has to deal with the possibility of encountering this code. That complicates the implementation.

### Complex Instruction Set

WebAssembly provides some high-level-ish instructions. Take for example [`call_indirect`](https://webassembly.github.io/spec/core/exec/instructions.html#exec-call-indirect) instruction. It:
- takes an index of the function to call passed as an operand,
- loads the corresponding entry from the table specified as an index via an immediate,
- traps if the load is out-of-bounds,
- traps if the value is null,
- loads the signature of the function,
- checks it with the signature specified by the immediate,
- and only then performs call (which by itself is [not simple](https://webassembly.github.io/spec/core/exec/instructions.html#exec-invoke)).

Some instructions can perform an arbitrary amount of work. For example, `memory.fill`, a sibling of `memset`, stores the given value in the given memory range. The range is passed as input to the instruction and can be arbitrarily large. This problem can be solved by limiting the range in some way (like by instrumentation or by a simple promise if the code is trusted) or perhaps just banning the use of those instructions (they are for performance anyway and for proofing that does not matter).

### VM State

The logical state of wasm computation is rather diverse. To name a few: memories contents and attributes, tables[^1] contents and attributes, various stacks, global variables, etc.

As discussed above, instructions will need to be provided with a subset of the VM state. That means that either the whole state is collapsed into a homogeneous tree which is queried with some kind of key-value scheme (simpler, less efficient), or each of those subsets of the state is represented by their own data structures (more efficient, complex).

There are also some small annoying things. One of them is the program counter. A Wasm module consists of a bunch of functions. A `call` instruction does not specify the code offset. Rather, it specifies the function index. The logic verifying the effects of the `call` instruction must check that the program counter was set to the beginning of a given function.

### It can be simpler

Those problems are not insurmountable.

One mitigation strategy is to analyze the wasm module and collate side tables. The on-chain verifier would refer to those to see where the `else` of the corresponding `if` instruction is. You will still have to deal with the complex state and other complexities.

A better approach seems to be to transform Wasm into a more proof-friendly VM. All wasm functions can be flattened into a single code blob. Unreachable code could be removed. Stacks could be merged into a single one. Any complex instructions could be replaced with a bunch of simpler instructions. Floating point types could be dropped.

Ideally, we end up with a super simple VM with a minimum number of instructions that operate on a minimum amount of state, and the state is as uniform as possible.

The caveat is that there must now be a compiler from WebAssembly to such a format. Also, the VM is implemented twice: once for the off-chain prover and once for the on-chain verifier. In the end, it feels that the system is almost as complex as before, the complexity is mostly shifted.

What if there was a simpler alternative? Why can't we compile the program into a simpler ISA in the first place?

## Alternative

Now, compare that to RISC ISAs like RISC-V or MIPS. Those instruction sets are extremely simple and can be implemented directly in hardware. That turns out to be really handy for IFPs as well: each state transition of a VM based on those ISAs performs a limited amount of work and operates on a limited amount of data.

Since the binary is not a sophisticated format, initialization is way simpler: just copy the program into the memory.

Or take, for example, a branch instruction. It takes the destination address, and its semantics can be described as:

```
br r0 => pc = r0
# where PC is the register containing the next execution's address.
```

The whole RV32IM has 48 instructions, and MIPS is around 40.

The state of a VM is basically: memory and registers. Registers can be mapped onto memory. Assuming no unaligned loads are used, the memory can be divided into words. That simplifies the proving mechanism quite a bit.

## Discussion

Wasm provides you with things you don't need, but they will cost you.

For me, the main selling point of Wasm is that it allows you to compile into machine code that can be safely sandboxed relatively simply. To achieve that, Wasm requires validation to establish invariants. Instead of simple gotos, it uses structured control flow. Several flavors of stacks and the existence of the concept of tables are all consequences of that. Those features may be important for some use cases. However, for IFP, those are just unnecessary. IFP can get away with interpretation just fine[^3]. Using Wasm for IFP requires you to unwind all of that. Why not start with a simpler model, to begin with?

While Wasm is excellent for specific use cases, IFP is not one of them. A RISC-based VM seems to be a better choice for IFP, hands down.

Feel free to leave a [comment](https://twitter.com/pepyakin/status/1565378422205030400).

[^1]: if a memory can be seen as an array of bytes, then a table is an array of references. Often it's used for placing function pointers there.
[^2]: One might say that in Polkadot, we use one-round fraud proofs. They are used in an off-chain setting.
[^3]: In the optimistic case, it's not necessary to use the VM for proving. The equvalent program compiled to native code could be executed instead, so there is no effect on the scalability.
[^4]: That is, a Merkle tree is created out of values of every memory cell, register, and every other piece of data required to describe the complete VM state. The critical feature of Merkle trees is that they allow the creation of a proof of inclusion. The proof convinces somebody who possesses the commitment for that tree that the tree has a specific value at a particular place. Such proof is compact, way less than presenting the whole tree itself.
