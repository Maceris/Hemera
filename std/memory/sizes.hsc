package memory

/**
 * A number of bytes: a size, as a file's or a buffer's is. Distinct, so it isn't mistaken for a count of anything else,
 * and a program that shows values by their types, a shell's tables among them, can show it as a size (KiB, MiB) rather
 * than a bare number. Its schema names it ByteCount.
 */
ByteCount :: distinct alias u64
