"""
Makes the tls scenario's test authority, its chains and their keys, with Python's cryptography package, and writes
them to certificates.hsc as DER constants:

    python -I make_certificates.py

A root signs an intermediate, which signs each leaf, for tls.test: one with a P-256 key, one with Ed25519's; then one
expired, and one for another name. Another root, which signs nothing the tests trust, stands for an unknown authority.
Every certificate is valid from 2025-01-01 to 2125-01-01 but the expired one, and the tests check them at NOW,
2026-06-01. Keys are made afresh each run, so the file changes whole.
"""

import datetime
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, ed25519
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

START = datetime.datetime(2025, 1, 1, tzinfo=datetime.timezone.utc)
END = datetime.datetime(2125, 1, 1, tzinfo=datetime.timezone.utc)
NOW = datetime.datetime(2026, 6, 1, tzinfo=datetime.timezone.utc)


def name(common):
    return x509.Name([x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Hemera TLS Test"), x509.NameAttribute(NameOID.COMMON_NAME, common)])


def certificate(subject, key, issuer_name, issuer_key, ca=False, names=None, start=START, end=END):
    builder = (x509.CertificateBuilder().subject_name(name(subject)).issuer_name(issuer_name).public_key(key.public_key())
               .serial_number(x509.random_serial_number()).not_valid_before(start).not_valid_after(end)
               .add_extension(x509.BasicConstraints(ca=ca, path_length=None), critical=True))
    if ca:
        builder = builder.add_extension(x509.KeyUsage(digital_signature=False, content_commitment=False, key_encipherment=False,
            data_encipherment=False, key_agreement=False, key_cert_sign=True, crl_sign=True, encipher_only=False,
            decipher_only=False), critical=True)
    else:
        builder = builder.add_extension(x509.KeyUsage(digital_signature=True, content_commitment=False, key_encipherment=False,
            data_encipherment=False, key_agreement=False, key_cert_sign=False, crl_sign=False, encipher_only=False,
            decipher_only=False), critical=True)
        builder = builder.add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False)
    if names:
        builder = builder.add_extension(x509.SubjectAlternativeName([x509.DNSName(each) for each in names]), critical=False)
    algorithm = None if isinstance(issuer_key, ed25519.Ed25519PrivateKey) else hashes.SHA256()
    return builder.sign(issuer_key, algorithm)


def der(cert):
    return cert.public_bytes(serialization.Encoding.DER)


root_key = ec.generate_private_key(ec.SECP256R1())
root = certificate("Hemera TLS Test Root", root_key, name("Hemera TLS Test Root"), root_key, ca=True)
middle_key = ec.generate_private_key(ec.SECP256R1())
middle = certificate("Hemera TLS Test Intermediate", middle_key, root.subject, root_key, ca=True)
other_key = ec.generate_private_key(ec.SECP256R1())
other_root = certificate("Hemera TLS Unknown Root", other_key, name("Hemera TLS Unknown Root"), other_key, ca=True)

p256_key = ec.generate_private_key(ec.SECP256R1())
p256_leaf = certificate("tls.test", p256_key, middle.subject, middle_key, names=["tls.test"])
ed_key = ed25519.Ed25519PrivateKey.generate()
ed_leaf = certificate("tls.test", ed_key, middle.subject, middle_key, names=["tls.test"])
expired_key = ec.generate_private_key(ec.SECP256R1())
expired_leaf = certificate("tls.test", expired_key, middle.subject, middle_key, names=["tls.test"],
                           start=datetime.datetime(2024, 1, 1, tzinfo=datetime.timezone.utc),
                           end=datetime.datetime(2025, 1, 1, tzinfo=datetime.timezone.utc))
wrong_key = ec.generate_private_key(ec.SECP256R1())
wrong_leaf = certificate("other.test", wrong_key, middle.subject, middle_key, names=["other.test"])
stranger_key = ec.generate_private_key(ec.SECP256R1())
stranger_leaf = certificate("tls.test", stranger_key, other_root.subject, other_key, names=["tls.test"])


def scalar(key):
    return key.private_numbers().private_value.to_bytes(32, "big")


def seed(key):
    return key.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption())


constants = [
    ("ROOT", "the test root, the anchor the tests trust", der(root)),
    ("P256_CHAIN", "tls.test's chain with a P-256 key: its leaf, then the intermediate", der(p256_leaf) + der(middle)),
    ("P256_KEY", "its leaf's P-256 secret key", scalar(p256_key)),
    ("ED25519_CHAIN", "tls.test's chain with an Ed25519 key", der(ed_leaf) + der(middle)),
    ("ED25519_KEY", "its leaf's Ed25519 secret key", seed(ed_key)),
    ("EXPIRED_CHAIN", "a chain whose leaf expired at 2025-01-01", der(expired_leaf) + der(middle)),
    ("EXPIRED_KEY", "its leaf's key", scalar(expired_key)),
    ("WRONG_NAME_CHAIN", "a chain for other.test", der(wrong_leaf) + der(middle)),
    ("WRONG_NAME_KEY", "its leaf's key", scalar(wrong_key)),
    ("STRANGER_CHAIN", "a chain for tls.test from a root the tests don't trust", der(stranger_leaf)),
    ("STRANGER_KEY", "its leaf's key", scalar(stranger_key)),
]

out = ["package tls_test", "", "/*", " * Made by make_certificates.py: the tls scenario's test authority, chains and keys. Don't edit; run the",
       " * script again.", " */", "", "/** When the tests check certificates: 2026-06-01, in seconds since 1970 UTC. */",
       f"NOW : i64 : {int(NOW.timestamp())}", ""]
for constant, what, data in constants:
    out.append(f"/** {what[0].upper() + what[1:]}, {len(data)} bytes. */")
    out.append(f"{constant} :: u8.[")
    for i in range(0, len(data), 16):
        out.append("    " + ", ".join(f"0x{byte:02x}" for byte in data[i:i + 16]) + ",")
    out.append("]")
    out.append("")
(Path(__file__).parent / "certificates.hsc").write_text("\n".join(out), encoding="utf-8", newline="\n")
print(f"{len(constants)} constants")
