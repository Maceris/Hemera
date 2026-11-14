package import_names

// The package in fake_io is named fake_io: an alias is fine, another name isn't (E4043)
import fake_io as io from "../imports/fake_std/fake_io"
import wrong from "../imports/fake_std/fake_io"
import deep from "std:nested/deep"
