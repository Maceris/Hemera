package external_in_if

LEVEL #externally_initialized :: 3

// Its value is only known once the program is loaded
#if LEVEL > 2 {
    HIGH :: 1
}
