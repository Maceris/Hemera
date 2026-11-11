"""
Makes the x509 scenario's test authority and its chains, good and bad, with Python's cryptography package,
and writes them to certificates.hsc as PEM constants:

    python -I make_certificates.py

Every certificate is valid from 2025-01-01 to 2125-01-01 unless a case says otherwise, and the tests check
them at 2026-06-01, so they don't expire. Keys are made afresh each run, so the file changes whole.
"""

import datetime
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, ed25519, padding, rsa
from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID, ObjectIdentifier

START = datetime.datetime(2025, 1, 1, tzinfo=datetime.timezone.utc)
END = datetime.datetime(2125, 1, 1, tzinfo=datetime.timezone.utc)

constants = []


def name(common):
    return x509.Name([x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Hemera Test"), x509.NameAttribute(NameOID.COMMON_NAME, common)])


def p256():
    return ec.generate_private_key(ec.SECP256R1())


def rsa_key(bits=2048):
    return rsa.generate_private_key(public_exponent=65537, key_size=bits)


def certificate(subject, key, issuer_name, issuer_key, ca=False, path_length=None, key_usage=None, eku=None, names=None,
                constraints=None, start=START, end=END, extra=None, pss=False, basic=True, hash_=None):
    builder = (x509.CertificateBuilder().subject_name(name(subject)).issuer_name(issuer_name).public_key(key.public_key())
               .serial_number(x509.random_serial_number()).not_valid_before(start).not_valid_after(end))
    if basic:
        builder = builder.add_extension(x509.BasicConstraints(ca=ca, path_length=path_length), critical=True)
    if key_usage is None:
        key_usage = "ca" if ca else "leaf"
    if key_usage == "ca":
        builder = builder.add_extension(x509.KeyUsage(digital_signature=True, content_commitment=False, key_encipherment=False,
                                                      data_encipherment=False, key_agreement=False, key_cert_sign=True,
                                                      crl_sign=True, encipher_only=False, decipher_only=False), critical=True)
    elif key_usage == "leaf":
        builder = builder.add_extension(x509.KeyUsage(digital_signature=True, content_commitment=False, key_encipherment=False,
                                                      data_encipherment=False, key_agreement=False, key_cert_sign=False,
                                                      crl_sign=False, encipher_only=False, decipher_only=False), critical=True)
    elif key_usage == "encipher":
        builder = builder.add_extension(x509.KeyUsage(digital_signature=False, content_commitment=False, key_encipherment=True,
                                                      data_encipherment=False, key_agreement=False, key_cert_sign=False,
                                                      crl_sign=False, encipher_only=False, decipher_only=False), critical=True)
    elif key_usage == "no_cert_sign":
        builder = builder.add_extension(x509.KeyUsage(digital_signature=True, content_commitment=False, key_encipherment=False,
                                                      data_encipherment=False, key_agreement=False, key_cert_sign=False,
                                                      crl_sign=True, encipher_only=False, decipher_only=False), critical=True)
    if eku is not None:
        builder = builder.add_extension(x509.ExtendedKeyUsage(eku), critical=False)
    if names is not None:
        builder = builder.add_extension(x509.SubjectAlternativeName(names), critical=False)
    if constraints is not None:
        builder = builder.add_extension(x509.NameConstraints(permitted_subtrees=constraints[0], excluded_subtrees=constraints[1]),
                                        critical=True)
    if extra is not None:
        builder = builder.add_extension(extra, critical=True)
    if isinstance(issuer_key, ed25519.Ed25519PrivateKey):
        return builder.sign(issuer_key, None)
    if pss:
        return builder.sign(issuer_key, hashes.SHA256(), rsa_padding=padding.PSS(mgf=padding.MGF1(hashes.SHA256()),
                                                                                 salt_length=32))
    return builder.sign(issuer_key, hash_ or hashes.SHA256())


def pem(*certificates):
    return "".join(c.public_bytes(serialization.Encoding.PEM).decode() for c in certificates)


def text_constant(name_, text, comment):
    # A multiline string: each line after its \\, joined by newlines
    lines = text.strip("\n").split("\n")
    constants.append(f"// {comment}\n{name_} ::\n" + "\n".join("    \\\\" + line for line in lines) + "\n")


def constant(name_, *certificates, comment):
    text_constant(name_, pem(*certificates), comment)


def self_signed(subject, key, path_length=None):
    return certificate(subject, key, name(subject), key, ca=True, path_length=path_length)


dns = x509.DNSName
leaf_names = [dns("example.test"), dns("*.wild.test"), x509.IPAddress(__import__("ipaddress").ip_address("192.0.2.1")),
              x509.IPAddress(__import__("ipaddress").ip_address("2001:db8::1"))]
server = [ExtendedKeyUsageOID.SERVER_AUTH]

rsa_root_key = rsa_key()
rsa_root = self_signed("RSA Root", rsa_root_key)
p256_root_key = p256()
p256_root = self_signed("P-256 Root", p256_root_key)
ed_root_key = ed25519.Ed25519PrivateKey.generate()
ed_root = self_signed("Ed25519 Root", ed_root_key)
constant("ANCHORS", rsa_root, p256_root, ed_root, comment="The trust anchors: an RSA root, a P-256 root and an Ed25519 root")

# An RSA intermediate, PSS-signed, below the RSA root, then a P-256 leaf
inter_key = rsa_key()
inter = certificate("RSA Intermediate", inter_key, rsa_root.subject, rsa_root_key, ca=True, path_length=0, pss=True)
leaf_key = p256()
leaf = certificate("example.test", leaf_key, inter.subject, inter_key, names=leaf_names, eku=server)
constant("RSA_CHAIN", leaf, inter, comment="A P-256 leaf, by an RSA intermediate signed with PSS, by the RSA root")

# P-256 all the way
p_inter_key = p256()
p_inter = certificate("P-256 Intermediate", p_inter_key, p256_root.subject, p256_root_key, ca=True)
p_leaf = certificate("example.test", p256(), p_inter.subject, p_inter_key, names=leaf_names, eku=server)
constant("P256_CHAIN", p_leaf, p_inter, comment="A P-256 leaf by a P-256 intermediate by the P-256 root")

# Ed25519 root signs a leaf directly
e_leaf = certificate("example.test", p256(), ed_root.subject, ed_root_key, names=leaf_names)
constant("ED25519_CHAIN", e_leaf, comment="A leaf signed by the Ed25519 root directly")

# The chain out of order, with a certificate that isn't on the path
constant("SHUFFLED_CHAIN", p_leaf, inter, p_inter, comment="The P-256 chain with an RSA intermediate in between that isn't on its path")

# A P-384 intermediate, like Let's Encrypt's E5, under the RSA root, signing a P-256 leaf with SHA-384
p384_inter_key = ec.generate_private_key(ec.SECP384R1())
p384_inter = certificate("P-384 Intermediate", p384_inter_key, rsa_root.subject, rsa_root_key, ca=True, path_length=0)
constant("P384_CHAIN", certificate("example.test", p256(), p384_inter.subject, p384_inter_key, names=leaf_names, eku=server,
                                   hash_=hashes.SHA384()), p384_inter,
         comment="A P-256 leaf by a P-384 intermediate, signed with ecdsa-with-SHA384, by the RSA root")

# Expired, and not yet valid
expired = certificate("example.test", p256(), p_inter.subject, p_inter_key, names=leaf_names,
                      start=datetime.datetime(2020, 1, 1, tzinfo=datetime.timezone.utc),
                      end=datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc))
constant("EXPIRED_CHAIN", expired, p_inter, comment="A leaf that expired on 2026-01-01")
future = certificate("example.test", p256(), p_inter.subject, p_inter_key, names=leaf_names,
                     start=datetime.datetime(2027, 1, 1, tzinfo=datetime.timezone.utc))
constant("FUTURE_CHAIN", future, p_inter, comment="A leaf not valid until 2027")

# An intermediate that isn't a CA, one without keyCertSign, and a path too long
not_ca_key = p256()
not_ca = certificate("Not A CA", not_ca_key, p256_root.subject, p256_root_key, ca=False, key_usage="ca")
constant("NOT_CA_CHAIN", certificate("example.test", p256(), not_ca.subject, not_ca_key, names=leaf_names), not_ca,
         comment="A leaf by an intermediate whose basic constraints say it isn't a CA")
no_sign_key = p256()
no_sign = certificate("No Cert Sign", no_sign_key, p256_root.subject, p256_root_key, ca=True, key_usage="no_cert_sign")
constant("NO_CERT_SIGN_CHAIN", certificate("example.test", p256(), no_sign.subject, no_sign_key, names=leaf_names), no_sign,
         comment="A leaf by a CA whose key usage hasn't keyCertSign")
below_key = p256()
below = certificate("Below Path Length 0", below_key, inter.subject, inter_key, ca=True)
constant("PATH_TOO_LONG_CHAIN", certificate("example.test", p256(), below.subject, below_key, names=leaf_names), below, inter,
         comment="A second intermediate below the RSA intermediate, whose path length is 0")

# Name constraints
import ipaddress
nc_key = p256()
nc = certificate("Constrained", nc_key, p256_root.subject, p256_root_key, ca=True,
                 constraints=([dns("allowed.test"), x509.IPAddress(ipaddress.ip_network("192.0.2.0/24"))],
                              [dns("bad.allowed.test")]))
constant("CONSTRAINED_GOOD_CHAIN", certificate("host.allowed.test", p256(), nc.subject, nc_key,
                                               names=[dns("host.allowed.test"), x509.IPAddress(ipaddress.ip_address("192.0.2.7"))]), nc,
         comment="A leaf within its CA's name constraints: allowed.test and 192.0.2.0/24, but not bad.allowed.test")
constant("CONSTRAINED_DNS_CHAIN", certificate("other.test", p256(), nc.subject, nc_key, names=[dns("other.test")]), nc,
         comment="A leaf with a name outside the permitted subtrees")
constant("CONSTRAINED_EXCLUDED_CHAIN", certificate("x.bad.allowed.test", p256(), nc.subject, nc_key, names=[dns("x.bad.allowed.test")]), nc,
         comment="A leaf with a name in the excluded subtree")
constant("CONSTRAINED_IP_CHAIN", certificate("host.allowed.test", p256(), nc.subject, nc_key,
                                             names=[dns("host.allowed.test"), x509.IPAddress(ipaddress.ip_address("198.51.100.1"))]), nc,
         comment="A leaf with an IP address outside the permitted range")

# Purpose and key usage
constant("CLIENT_ONLY_CHAIN", certificate("example.test", p256(), p_inter.subject, p_inter_key, names=leaf_names,
                                          eku=[ExtendedKeyUsageOID.CLIENT_AUTH]), p_inter,
         comment="A leaf whose extended key usage is only clientAuth")
constant("KEY_USAGE_CHAIN", certificate("example.test", rsa_key(), p_inter.subject, p_inter_key, names=leaf_names, key_usage="encipher"), p_inter,
         comment="A leaf whose key usage is keyEncipherment alone")

# An unknown critical extension
constant("CRITICAL_CHAIN", certificate("example.test", p256(), p_inter.subject, p_inter_key, names=leaf_names,
                                       extra=x509.UnrecognizedExtension(ObjectIdentifier("1.3.6.1.4.1.55555.1"), b"\x05\x00")), p_inter,
         comment="A leaf with a critical extension nothing understands")

# A forged signature: the P-256 leaf with a byte of its signature changed
good = p_leaf.public_bytes(serialization.Encoding.DER)
forged = bytearray(good)
forged[-5] ^= 0x01
forged_text = "-----BEGIN CERTIFICATE-----\n" + __import__("base64").encodebytes(bytes(forged)).decode() + "-----END CERTIFICATE-----\n"
text_constant("FORGED_CHAIN", forged_text + pem(p_inter), "The P-256 leaf with its signature changed")

# An unknown root, and a small RSA key
stranger_key = p256()
stranger = self_signed("Stranger Root", stranger_key)
constant("UNKNOWN_CHAIN", certificate("example.test", p256(), stranger.subject, stranger_key, names=leaf_names),
         comment="A leaf by a root that isn't an anchor")
small_key = rsa_key(1024)
small = certificate("Small RSA", small_key, p256_root.subject, p256_root_key, ca=True)
constant("SMALL_RSA_CHAIN", certificate("example.test", p256(), small.subject, small_key, names=leaf_names), small,
         comment="A leaf by an intermediate with a 1024-bit RSA key")

header = '''/*
 * The x509 scenario's test authority and chains, made by make_certificates.py with Python's cryptography
 * package; remake them with it rather than editing them. Each chain is PEM, the leaf first.
 */
package x509_test

'''
Path(__file__).with_name("certificates.hsc").write_text(header + "\n".join(constants) + "\n", encoding="utf-8", newline="\n")
