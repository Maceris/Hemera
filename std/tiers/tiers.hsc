package tiers

/*
 * What a std package needs from the target it runs on. Every std package declares one as
 * PACKAGE_TIER, and may only import packages of the same or a lower tier.
 *
 * Code without an operating system (OS == .None) can use up to Allocating, once it has
 * an allocator in its context.
 */
Tier :: enum {
    // Needs only base.
    Freestanding,
    // Needs an Allocator in context.
    Allocating,
    // Needs system calls.
    Os,
}
