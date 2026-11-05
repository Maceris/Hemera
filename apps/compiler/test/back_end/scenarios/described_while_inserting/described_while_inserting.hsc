package described_while_inserting

import compiler from "base"
import runtime from "base"
import testing from "std"

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

describes_a_struct_again_once_its_whole #test :: fn(t: ptr[mut testing.T]) -> testing.Outcome {
    node := Node.{from = 30, to = 8}
    testing.expect_eq(t, node.from, 30, "Node has an int field for Edge's pointer from")
    testing.expect_eq(t, node.to, 8, "and one for its pointer to")
    testing.expect_eq(t, NODE_FIELDS, 2, "described once laid out, Node has both fields, not the none it had mid-#insert")
    return .Ok
}
