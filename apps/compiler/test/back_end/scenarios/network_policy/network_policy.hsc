package network_policy

import testing from "std"
import text_buffer from "std"
import net_address from "std/os/slop_os"
import network from "std/os/slop_os"

/*
 * The network protocol's policies (std/os/slop_os/network's policy.hsc), which are plain code, so tested hosted: which
 * addresses are public, what a policy allows, and which policies are within others, as Narrow checks.
 */

/**
 * Make an endpoint.
 *
 * @param a The address's first byte.
 * @param b Its second.
 * @param c Its third.
 * @param d Its fourth.
 * @param port The port.
 * @return The endpoint.
 */
at :: fn(a: u8, b: u8, c: u8, d: u8, port: u16) -> net_address.Endpoint {
    return net_address.Endpoint.{address = net_address.v4(a, b, c, d), port = port}
}

knows_public_addresses #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    testing.expect(t, network.is_public(net_address.v4(93, 184, 215, 14)), "a global address")
    for private in net_address.Address.[net_address.v4(10, 0, 2, 2), net_address.v4(192, 168, 1, 1), net_address.v4(172, 16, 0, 1),
        net_address.v4(127, 0, 0, 1), net_address.v4(169, 254, 1, 1), net_address.v4(100, 64, 0, 1), net_address.v4(224, 0, 0, 1),
        net_address.v4(0, 0, 0, 0), net_address.v4(198, 51, 100, 7)] {
        testing.expect(t, !network.is_public(private), "a private, local or reserved address")
    }
    global := net_address.Address.{family = .V6}
    global.bytes[0] = 0x26
    global.bytes[1] = 0x06
    testing.expect(t, network.is_public(global), "a global IPv6 address")
    link_local := net_address.Address.{family = .V6}
    link_local.bytes[0] = 0xfe
    link_local.bytes[1] = 0x80
    testing.expect(t, !network.is_public(link_local), "a link-local IPv6 address")
    return .Ok
}

a_session_reaches_public_addresses_only #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    session := network.public_only()
    testing.expect(t, network.allows_connect(&session, network.TRANSPORT_TCP, at(93, 184, 215, 14, 443)), "a public address, by TCP")
    testing.expect(t, network.allows_connect(&session, network.TRANSPORT_UDP, at(93, 184, 215, 14, 53)), "and by UDP")
    testing.expect(t, !network.allows_connect(&session, network.TRANSPORT_TCP, at(10, 0, 2, 2, 7)), "not a private one")
    testing.expect(t, !network.allows_listen(&session, network.TRANSPORT_TCP, 8080), "listening on nothing")
    everything := network.everything()
    testing.expect(t, network.allows_connect(&everything, network.TRANSPORT_TCP, at(10, 0, 2, 2, 7)), "everything reaches it")
    testing.expect(t, network.allows_listen(&everything, network.TRANSPORT_UDP, 53), "and listens anywhere")
    return .Ok
}

narrowing_gives_only_less #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    everything := network.everything()
    session := network.public_only()
    testing.expect(t, network.within(&everything, &session), "a session's within everything")
    testing.expect(t, !network.within(&session, &everything), "everything isn't within a session's")
    one_host := network.Policy.{connect_count = 1}
    one_host.connect[0] = network.range_rule(net_address.v4(93, 184, 215, 14), 32, network.TRANSPORT_TCP, 443, 443)
    testing.expect(t, network.within(&session, &one_host), "one public host and port is within public addresses")
    testing.expect(t, network.allows_connect(&one_host, network.TRANSPORT_TCP, at(93, 184, 215, 14, 443)), "which it allows")
    testing.expect(t, !network.allows_connect(&one_host, network.TRANSPORT_TCP, at(93, 184, 215, 14, 80)), "on that port only")
    testing.expect(t, !network.allows_connect(&one_host, network.TRANSPORT_UDP, at(93, 184, 215, 14, 443)), "by TCP only")
    private_host := network.Policy.{connect_count = 1}
    private_host.connect[0] = network.range_rule(net_address.v4(10, 0, 2, 2), 32, network.TRANSPORT_TCP, 7, 7)
    testing.expect(t, !network.within(&session, &private_host), "a private host isn't within public addresses")
    testing.expect(t, network.within(&everything, &private_host), "but is within everything")
    // A narrower range within a wider one, and not the other way round
    wide := network.Policy.{connect_count = 1}
    wide.connect[0] = network.range_rule(net_address.v4(10, 0, 0, 0), 8, network.TRANSPORT_TCP | network.TRANSPORT_UDP, 0, 65535)
    testing.expect(t, network.within(&wide, &private_host), "a host within its /8")
    testing.expect(t, !network.within(&private_host, &wide), "the /8 not within one host")
    listening := network.Policy.{listen_count = 1}
    listening.listen[0] = network.Rule.{transports = network.TRANSPORT_TCP, first_port = 8080, last_port = 8080}
    testing.expect(t, !network.within(&session, &listening), "listening isn't within a session's")
    return .Ok
}

describes_a_policy #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    policy := network.Policy.{connect_count = 1}
    policy.connect[0] = network.range_rule(net_address.v4(10, 0, 2, 2), 32, network.TRANSPORT_TCP, 7, 7)
    storage : u8[200]
    text := text_buffer.make(storage)
    network.describe(&policy, &text)
    testing.expect_eq(t, text_buffer.as_string(&text), "TCP to 10.0.2.2, port 7", "one host's port")
    session := network.public_only()
    more : u8[200]
    described := text_buffer.make(more)
    network.describe(&session, &described)
    testing.expect_eq(t, text_buffer.as_string(&described), "TCP and UDP to any public address, any port", "a session's")
    return .Ok
}

/** A policy of one rule allowing a name's hosts by TCP on a port. */
named :: fn(name: string, port: u16) -> network.Policy {
    policy := network.Policy.{connect_count = 1}
    policy.connect[0] = network.name_rule(name, network.TRANSPORT_TCP, port, port) or_else network.Rule.{}
    return policy
}

matches_names #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    exact := network.name_rule("Example.COM.", network.TRANSPORT_TCP, 443, 443) or_else network.Rule.{}
    testing.expect(t, network.name_covers(network.rule_name(&exact), string_bytes("example.com")), "a name, its case and final dot aside")
    testing.expect(t, !network.name_covers(network.rule_name(&exact), string_bytes("www.example.com")), "not a name under it")
    every := network.name_rule("*.example.com", network.TRANSPORT_TCP, 443, 443) or_else network.Rule.{}
    pattern :: network.rule_name(&every)
    testing.expect(t, network.name_covers(pattern, string_bytes("www.Example.com")) && network.name_covers(pattern, string_bytes("a.b.example.com.")),
        "a wildcard covers the names under its domain")
    testing.expect(t, !network.name_covers(pattern, string_bytes("example.com")), "not the domain itself")
    testing.expect(t, !network.name_covers(pattern, string_bytes("badexample.com")), "nor a name that only ends the same")
    testing.expect(t, network.name_rule("", network.TRANSPORT_TCP, 1, 1) is_none, "an empty name isn't a rule")
    return .Ok
}

names_reach_public_addresses_only #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    name :: string_bytes("peer.example.test")
    session := network.public_only()
    testing.expect(t, network.allows_named(&session, network.TRANSPORT_TCP, name, at(93, 184, 215, 14, 443)), "a name's public address")
    testing.expect(t, !network.allows_named(&session, network.TRANSPORT_TCP, name, at(10, 0, 2, 2, 7)),
        "not a private one it's answered with (DNS rebinding)")
    everything := network.everything()
    testing.expect(t, !network.allows_named(&everything, network.TRANSPORT_TCP, name, at(127, 0, 0, 1, 7)),
        "not even with everything allowed, without a range naming it")
    local := network.Policy.{connect_count = 1}
    local.connect[0] = network.range_rule(net_address.v4(10, 0, 2, 0), 24, network.TRANSPORT_TCP, 0, 65535)
    testing.expect(t, network.allows_named(&local, network.TRANSPORT_TCP, name, at(10, 0, 2, 2, 7)), "a range names it")
    peer := named("peer.example.test", 7)
    testing.expect(t, network.allows_named(&peer, network.TRANSPORT_TCP, name, at(93, 184, 215, 14, 7)), "a name rule's host")
    testing.expect(t, !network.allows_named(&peer, network.TRANSPORT_TCP, string_bytes("other.example.test"), at(93, 184, 215, 14, 7)),
        "not another name")
    testing.expect(t, !network.allows_named(&peer, network.TRANSPORT_TCP, name, at(93, 184, 215, 14, 8)), "nor another port")
    testing.expect(t, !network.allows_named(&peer, network.TRANSPORT_TCP, name, at(10, 0, 2, 2, 7)), "nor a private address")
    testing.expect(t, !network.allows_connect(&peer, network.TRANSPORT_TCP, at(93, 184, 215, 14, 7)), "nor any address but by name")
    testing.expect(t, network.allows_resolve(&peer) && network.allows_resolve(&session), "who connects anywhere may resolve")
    nothing := network.Policy.{}
    testing.expect(t, !network.allows_resolve(&nothing), "who connects nowhere may not")
    return .Ok
}

narrows_to_names #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    session := network.public_only()
    host := named("www.example.com", 443)
    testing.expect(t, network.within(&session, &host), "a name's within public addresses")
    testing.expect(t, !network.within(&host, &session), "public addresses aren't within a name")
    domain := named("*.example.com", 443)
    testing.expect(t, network.within(&domain, &host), "a host within its domain's wildcard")
    below := named("*.a.example.com", 443)
    testing.expect(t, network.within(&domain, &below), "and a wildcard below it")
    same := named("*.example.com", 443)
    testing.expect(t, network.within(&domain, &same), "and itself")
    testing.expect(t, !network.within(&host, &domain), "a wildcard isn't within one host")
    apex := named("example.com", 443)
    testing.expect(t, !network.within(&domain, &apex), "nor the domain within its wildcard")
    local := network.Policy.{connect_count = 1}
    local.connect[0] = network.range_rule(net_address.v4(10, 0, 2, 0), 24, network.TRANSPORT_TCP, 0, 65535)
    testing.expect(t, !network.within(&local, &host), "a name isn't within a private range")
    storage : u8[200]
    text := text_buffer.make(storage)
    network.describe(&domain, &text)
    testing.expect_eq(t, text_buffer.as_string(&text), "TCP to *.example.com, port 443", "a name rule described")
    return .Ok
}
