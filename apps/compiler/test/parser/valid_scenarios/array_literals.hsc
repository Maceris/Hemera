package valid_scenarios

PRIMES :: int.[2, 3, 5, 7]
MAGIC : u64[2] : u64.[0xc7b1dd30df4c8b88, 0x0a82e883a194f07b]
EMPTY :: int.[]
TRAILING_COMMA :: f64.[
    0.5,
    1.5,
]

array_literals :: fn(x: int) {
    view : int[] : int.[x, x * 2, x + 1]
    nested :: Point.[Point.{1, 2}, Point.{x = 3, y = 4}]
    request :: Request.{id = u64.[1, 2, 3, 4], revision = 0}
    sum(int.[1, 2, 3])
}
