package tiers

/**
 * What a std package needs from the target it runs on.
 *
 * Every std package declares one as PACKAGE_TIER, and may only import packages of the same or a lower tier, so a
 * package's tier is at least that of everything it imports. The members are in order, lowest first.
 *
 * Code without an operating system (OS == .None) can use up to Allocating, once it has an allocator in its context.
 */
Tier :: enum {
    /** Needs only base: no allocator and no system calls, so usable anywhere, a kernel included. */
    Freestanding,
    /** Needs an Allocator in context, but no system calls. */
    Allocating,
    /** Needs system calls, so an operating system to make them to. */
    Os,
}
