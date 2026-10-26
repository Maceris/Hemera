package described_while_inserting

import compiler from "base"
import runtime from "base"

// Node's #insert describes Edge, which points back at Node: what's behind a pointer isn't waited for, since
// Node can't be laid out until this is done
Node :: struct {
    #insert fields_from(Edge),
}

Edge :: struct {
    from : ptr[Node],
    to : ptr[Node],
}

// An int field for each pointer field of type
fields_from :: fn(type: type) -> compiler.Code {
    info :: cast[ptr[compiler.TypeInfoStruct]](type_info_of(type))
    made : compiler.Code[..]
    for member in info.members {
        if member.member_type.variant == .POINTER {
            runtime.array_add(&made, #code fields {
                #insert compiler.name(member.name) : int,
            })
        }
    }
    return compiler.list(made)
}

/*
 * Node's fields through Edge's, once Node is laid out, which size_of waits for: Node's descriptor, made while its
 * #insert ran, is made again now that it's whole
 */
node_fields :: fn() -> int {
    _ = size_of(Node)
    edge :: cast[ptr[compiler.TypeInfoStruct]](type_info_of(Edge))
    for member in edge.members {
        base :: cast[ptr[compiler.TypeInfoPointer]](member.member_type).base_type or_return 0
        node :: cast[ptr[compiler.TypeInfoStruct]](base)
        return cast[int](node.members.count)
    }
    return 0
}

NODE_FIELDS :: #run node_fields()

main :: fn() -> int {
    node := Node.{from = 30, to = 8}
    // 42: 30 and 8, and two for each of Node's two fields
    return node.from + node.to + 2 * NODE_FIELDS
}
