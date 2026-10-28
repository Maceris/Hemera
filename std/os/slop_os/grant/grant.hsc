package grant

// Only for SlopOS, where std/os has what its generated code needs: base.OS, since the #insert in it could declare an OS of its own
#if base.OS == .SlopOS {
    import os from "std"
    import slop_os from "std/os"
    import files from "std/os/slop_os"

    /*
     * A grant (the SlopOS repository's roadmap 8f): what a directory's Grant gives, to hand to a directory in another
     * volume, whose Link keeps it as a stored link. Its holder can make one link from it; it's good until then, or
     * until it's closed. Only the server keeping the link speaks it: Claim gives what that server takes to the storage
     * service, which has the link issued.
     */
    Grant :: struct {}

    PROTOCOL :: slop_os.Protocol.{name = "grant", major_version = 1, lending = .PerConnection}

    // What a claim gives: the volume the grant is from, by its container and ID, a ticket for its one link, and whether it writes.
    Claim :: struct {
        container : u8[16],
        volume : u64,
        ticket : u8[32],
        write : bool,
    }

    Request :: union {
        Claim,
    }

    Response :: union {
        Claimed(Claim),
        // Claimed already, or what it grants is gone
        Failed(files.FileError),
        Unsupported,
    }

    // A grant is claimed once.
    is_idempotent :: fn(request: ptr[Request]) -> bool {
        return false
    }

    #insert os.protocol_code(Request, Response)
}
