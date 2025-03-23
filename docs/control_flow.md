# Control Flow

## Loops

```
// 0 to 10, excluding 10
for i in 0..<10 {
    println(value)
}

// 0 to 10, including 10
for i in 0..=10 {
    println(value)
}

// The bounds can be variables, expressions
for i in x..<random_integer() {

}

some_array : int[3] : {1, 3, 19}

for value in some_array {
    println(value)
}

// You can add an optional second parameter for the index number 
for value, index in some_array {
    println(value)
}
```

You can iterate arrays and views by reference:

```
for &value in some_array {
    println(value)
}

// Index is not affected
for &value, index in some_array {
    println(value)
}
```

The `#reverse` directive indicates a loop should be done in reverse

```
for i in 0..=10 #reverse {
    println(value)
}
```
