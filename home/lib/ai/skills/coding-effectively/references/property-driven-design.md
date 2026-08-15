# Property-Driven Design

Ask what properties a feature should hold before implementing it. The questions surface design gaps early, while they are still cheap.

| Question | Property | Example |
| --- | --- | --- |
| Does it have an inverse operation? | Roundtrip | `decode(encode(x)) == x` |
| Is applying it twice the same as once? | Idempotence | `f(f(x)) == f(x)` |
| What quantities are preserved? | Invariant | length, sum, count unchanged |
| Is argument order irrelevant? | Commutativity | `f(a, b) == f(b, a)` |
| Can operations be regrouped? | Associativity | `f(f(a,b), c) == f(a, f(b,c))` |
| Is there a neutral element? | Identity | `f(x, 0) == x` |
| Is there a reference implementation? | Oracle | `new(x) == old(x)` |
| Can output be checked without recomputing it? | Easy to verify | `is_sorted(sort(x))` |

These reliably expose the questions that otherwise surface as bugs:

- What about deleted or deactivated entities?
- Case-sensitive or not?
- Stable sort? What are the tie-breaking rules?
- Which algorithm, and is it configurable?

Surface these during design, not during debugging.
