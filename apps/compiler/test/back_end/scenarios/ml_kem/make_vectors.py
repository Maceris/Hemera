"""
Makes the ml_kem scenario's vectors.hsc from NIST's ACVP test vectors for ML-KEM (github.com/usnistgov/ACVP-Server,
gen-val/json-files, ML-KEM-keyGen-FIPS203 and ML-KEM-encapDecap-FIPS203, internalProjection.json; public domain) and
Project Wycheproof's (github.com/C2SP/wycheproof, testvectors_v1/mlkem_768_test.json; Apache License 2.0), their
ML-KEM-768 cases:

    python -I make_vectors.py <folder holding acvp_keygen.json, acvp_encap_decap.json and wycheproof_mlkem_768.json>

Wycheproof's cases of a seed or ciphertext of the wrong size are left out: std/crypto's types are of the right sizes,
so they can't be given one.
"""

import json
import sys
from pathlib import Path

folder = Path(sys.argv[1])


def load(name):
    return json.loads((folder / name).read_text(encoding="utf-8"))


def struct_list(type_name, constant, cases, fields):
    lines = [f"{constant} :: {type_name}.["]
    for case in cases:
        values = ", ".join(f'{field} = "{case[key].lower()}"' if isinstance(case[key], str) else f"{field} = {str(case[key]).lower()}"
                           for field, key in fields)
        lines.append(f"    {type_name}.{{{values}}},")
    lines.append("]")
    return "\n".join(lines)


keygen = [test for group in load("acvp_keygen.json")["testGroups"] if group["parameterSet"] == "ML-KEM-768" for test in group["tests"]]
encap_decap = load("acvp_encap_decap.json")["testGroups"]
encaps = [t for g in encap_decap if g["parameterSet"] == "ML-KEM-768" and g["function"] == "encapsulation" for t in g["tests"]]
decaps = [t for g in encap_decap if g["parameterSet"] == "ML-KEM-768" and g["function"] == "decapsulation" for t in g["tests"]]
ek_checks = [t for g in encap_decap if g["parameterSet"] == "ML-KEM-768" and g["function"] == "encapsulationKeyCheck" for t in g["tests"]]
dk_checks = [t for g in encap_decap if g["parameterSet"] == "ML-KEM-768" and g["function"] == "decapsulationKeyCheck" for t in g["tests"]]
wycheproof = [t for g in load("wycheproof_mlkem_768.json")["testGroups"] for t in g["tests"]
              if t["result"] == "valid" and len(t["seed"]) == 128 and len(t.get("c", "")) == 2176]
skipped = sum(len(g["tests"]) for g in load("wycheproof_mlkem_768.json")["testGroups"]) - len(wycheproof)

header = f'''/*
 * ML-KEM-768's test vectors, made by make_vectors.py from NIST's ACVP vectors (public domain) and Project Wycheproof's
 * (Apache License 2.0): {len(keygen)} key pairs, {len(encaps)} encapsulations, {len(decaps)} decapsulations, {len(ek_checks)} public
 * and {len(dk_checks)} secret key checks, and {len(wycheproof)} of Wycheproof's ({skipped} left out, of sizes the types can't hold).
 * Remake it with make_vectors.py rather than editing it.
 */
package ml_kem_test

KeyGenCase :: struct {{
    d : string,
    z : string,
    ek : string,
    dk : string,
}}

EncapCase :: struct {{
    ek : string,
    m : string,
    c : string,
    k : string,
}}

DecapCase :: struct {{
    dk : string,
    c : string,
    k : string,
}}

KeyCheckCase :: struct {{
    key : string,
    passes : bool,
}}

WycheproofCase :: struct {{
    seed : string,
    ek : string,
    c : string,
    k : string,
}}
'''
parts = [header,
         struct_list("KeyGenCase", "KEY_PAIRS", keygen, [("d", "d"), ("z", "z"), ("ek", "ek"), ("dk", "dk")]),
         struct_list("EncapCase", "ENCAPSULATIONS", encaps, [("ek", "ek"), ("m", "m"), ("c", "c"), ("k", "k")]),
         struct_list("DecapCase", "DECAPSULATIONS", decaps, [("dk", "dk"), ("c", "c"), ("k", "k")]),
         struct_list("KeyCheckCase", "PUBLIC_KEY_CHECKS", ek_checks, [("key", "ek"), ("passes", "testPassed")]),
         struct_list("KeyCheckCase", "SECRET_KEY_CHECKS", dk_checks, [("key", "dk"), ("passes", "testPassed")]),
         struct_list("WycheproofCase", "WYCHEPROOF", wycheproof, [("seed", "seed"), ("ek", "ek"), ("c", "c"), ("k", "K")])]
Path(__file__).with_name("vectors.hsc").write_text("\n\n".join(parts) + "\n", encoding="utf-8", newline="\n")
print(len(keygen), len(encaps), len(decaps), len(ek_checks), len(dk_checks), len(wycheproof), skipped)
