# The Blue language

A Blue program is a Blue expression that returns an integer, for example: 
```
# do_nothing.blue
0
```


The usual mathematical operators are supported:
```
# Return 4
6 / 2 + 1
```


Variables and functions are defined in **let**-expressions:
```
let
  # Symbols without parameters are just variables
  num_to_square = 5;
  # The function square takes a parameter x
  # Inside the function, the only available symbols from outside the function scope
  # are other functions. It is thus not possible to reference `num_to_square` inside `square`.
  square x = x ** x;
in square num_to_square
```


The arrow operator (**->**) makes it possible to string
together expressions and discard all results except for the last one.
That means this program:
```
let discard = print 42; in 0
```
...can be rewritten as such:
```
(print 42) -> 0
```


This code will throw an error:
```
let 
  sum a b = a + b;
  x = 2;
  y = 3;
in sum x y
```


This is because the parser is will read the last line as:
```
# ...
in (sum (x (y))
```


(The **x** is interpreted as a function taking **y** as an argument).
The dot operator (**.**) can be used to terminate the
current expression at **x** and treat **y** as an argument to **sum**:
```
# ...
in sum x . y
```
**Note**: the dot operator must be preceeded by atleast one whitespace,
or else it's interpreted as field access.


Functions with exactly two parameters can be used as infix operators
by prefixing the identifier with a single quote:
```
# ...
in x 'sum y
```


Lists are handled with the following oeprators:
* **++** - Concatenation
* **::** - Appending
* **$** - Indexing
Example:
```
(([1, 2, 3] :: 4) ++ [5, 6]) $ 3
```


Structs are used like so:
``` 
let
  person = { name = "Karl", age = 46 };
  print_name person = print person.name;
in print_name person . -> 0
```


See the [example directory](../examples/) for more examples.
