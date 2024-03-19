# Calling convention

* *BP*: base pointer
* *SP*: stack pointer
* *IP*: instruction pointer

| Caller | VM | Callee |
|--------|----|--------|
| Push arguments to stack |||
| Push # of arguments to stack |||
| `call` |||
|| Push current BP ||
|| Push return address ||
|| Assigns SP to BP ||
|| Jumps to caller code ||
||| Allocate space for locals |
||| ... |
||| Push return value |
||| `ret` |
|| Pop return value and save it ||
|| Pop return address and assign it to IP ||
|| Pop old BP and assign it to BP ||
|| Pop # of arguments ||
|| Pop arguments ||
|| Push saved return value ||
| ... |||

## Example
4 parameters, load parameter 2: offset = -6 + 1 = -5
```
load %-5
```
Store local 3: offset = 2
```
store %2
```