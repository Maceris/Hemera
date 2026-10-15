package external_ok

Marker :: struct {
    id : u64,
}

START #externally_initialized #section(".requests_start") :: Marker.{ id = 1 }
PLAIN #externally_initialized :: Marker.{}
