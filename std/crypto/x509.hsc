package crypto

/*
 * X.509 certificates (RFC 5280): reading them, and validating a chain of them to a trust anchor, as a TLS
 * client checks a server's (section 6.1's path validation, for what TLS needs).
 *
 *     verdict := crypto.x509_verify_chain(chain, anchors, now, .SERVER)
 *     if verdict != .VALID { ... }
 *     leaf : crypto.X509Certificate
 *     _ = crypto.x509_parse(first_certificate, &leaf)
 *     if !crypto.x509_matches_host(&leaf, "example.com") { ... }
 *
 * A chain and a set of trust anchors are each DER certificates one after another, the leaf first in a
 * chain, as a TLS Certificate message's entries hold them; the rest of a chain may come in any order, and
 * certificates that aren't needed are skipped. What's read is views of those bytes; nothing is allocated.
 *
 * What's checked, for each certificate on the path from the leaf to an anchor: its signature, by its
 * issuer's key (RSA of 2048 bits or more with PKCS #1 v1.5 or PSS, P-256 or P-384 ECDSA, or Ed25519, over
 * SHA-256, SHA-384 or SHA-512); its validity period; that an issuer is a CA (basic constraints, and key usage's
 * keyCertSign when there's key usage) within its path length; name constraints on DNS names, IP addresses,
 * email addresses and directory names; extended key usage, the leaf's and any CA's that has one; and that
 * no extension marked critical is one that isn't understood. Names are compared byte for byte, as DER
 * writes them. Policies aren't processed, and revocation isn't checked.
 */

/** The most certificates a chain may have, the leaf included; more are refused. */
X509_MOST_CERTIFICATES :: 10
/** The fewest bits an RSA key that signs a certificate may have. */
X509_FEWEST_RSA_BITS :: 2048

/** How a certificate is signed: the algorithm and its hash. */
X509Signature :: enum {
    /** RSASSA-PKCS1-v1_5 with SHA-256 (sha256WithRSAEncryption). */
    RSA_PKCS1_SHA256,
    /** RSASSA-PKCS1-v1_5 with SHA-384. */
    RSA_PKCS1_SHA384,
    /** RSASSA-PKCS1-v1_5 with SHA-512. */
    RSA_PKCS1_SHA512,
    /** RSASSA-PSS with SHA-256 and MGF1 over it; its salt length is the certificate's pss_salt. */
    RSA_PSS_SHA256,
    /** RSASSA-PSS with SHA-384. */
    RSA_PSS_SHA384,
    /** RSASSA-PSS with SHA-512. */
    RSA_PSS_SHA512,
    /** ECDSA with SHA-256. */
    ECDSA_SHA256,
    /** ECDSA with SHA-384. */
    ECDSA_SHA384,
    /** ECDSA with SHA-512. */
    ECDSA_SHA512,
    /** Ed25519, over the certificate itself. */
    ED25519,
}

/** What kind of public key a certificate holds. */
X509KeyKind :: enum {
    /** An algorithm or curve this package doesn't do, like P-521: the certificate can be read but its key not used. */
    UNSUPPORTED,
    /** RSA: the key is a PKCS #1 RSAPublicKey's DER. */
    RSA,
    /** P-256: the key is SEC 1's point. */
    P256,
    /** P-384, which only verifies: the key is SEC 1's uncompressed point. */
    P384,
    /** Ed25519: the key is its 32 bytes. */
    ED25519,
}

/** What a chain is validated for: the extended key usage its leaf, and any CA that names some, has to allow. */
X509Purpose :: enum {
    /** A TLS server's certificate: id-kp-serverAuth. */
    SERVER,
    /** A TLS client's certificate: id-kp-clientAuth. */
    CLIENT,
    /** Any: extended key usage isn't checked. */
    ANY,
}

/** What validating a chain found: VALID, or the reason it isn't. */
X509Verdict :: enum {
    /** There's a path from the leaf to a trust anchor, and every check held. */
    VALID,
    /** A certificate in the chain, or an anchor, couldn't be read: it isn't DER, or not a certificate X.509 allows. */
    MALFORMED,
    /** The chain is empty, or has more than X509_MOST_CERTIFICATES. */
    BAD_CHAIN,
    /** No issuer could be found for a certificate, among the chain and the anchors. */
    UNKNOWN_ISSUER,
    /** An issuer was found by name, but its key didn't verify the signature. */
    BAD_SIGNATURE,
    /** A signature's algorithm, or a key, isn't one this package does, or an RSA key is too small. */
    UNSUPPORTED,
    /** A certificate on the path isn't valid at the time given: before its notBefore or after its notAfter. */
    EXPIRED,
    /** An issuer isn't a CA: no basic constraints with cA, or key usage without keyCertSign. */
    NOT_A_CA,
    /** An issuer's path length constraint is exceeded. */
    PATH_TOO_LONG,
    /** The leaf's key usage doesn't allow digitalSignature, which TLS 1.3 signs with. */
    KEY_USAGE,
    /** The leaf's extended key usage, or a CA's, doesn't allow the purpose. */
    PURPOSE,
    /** A name in a certificate is outside a CA's name constraints, or of a kind the constraints can't be checked on. */
    NAME_CONSTRAINTS,
}

/**
 * A certificate read: views of its DER for each part TLS and path validation need. It's #scoped, as its views are
 * of the bytes it was read from, which may be on the stack.
 */
X509Certificate :: struct #scoped {
    /** The whole certificate. */
    der: u8[],
    /** The TBSCertificate, tag and length included: what the signature is over. */
    tbs: u8[],
    /** The version: 1, 2 or 3. */
    version: i64,
    /** The serial number's contents, as DER writes the INTEGER. */
    serial: u8[],
    /** How it's signed. */
    signature_algorithm: X509Signature,
    /** For RSA-PSS, the salt length the parameters give, in bytes; 0 otherwise. */
    pss_salt: usize,
    /** The issuer's Name, its whole DER. */
    issuer: u8[],
    /** The subject's Name, its whole DER. */
    subject: u8[],
    /** The start of the validity period, in seconds since 1970-01-01T00:00:00Z. */
    not_before: i64,
    /** The end of the validity period, in the same seconds, inclusive. */
    not_after: i64,
    /** The SubjectPublicKeyInfo's whole DER. */
    public_key_info: u8[],
    /** The kind of public key. */
    key_kind: X509KeyKind,
    /** The public key, as key_kind says to read it; empty when it's UNSUPPORTED. */
    key: u8[],
    /** The signature's bytes: an RSA signature, an ECDSA-Sig-Value's DER, or Ed25519's 64 bytes. */
    signature: u8[],
    /** Whether there's a basic constraints extension. */
    has_basic_constraints: bool,
    /** Whether basic constraints say it's a CA. */
    is_ca: bool,
    /** Basic constraints' path length: how many CAs, not counting self-issued ones, may come below it; -1 for none. */
    path_length: i64,
    /** Whether there's a key usage extension. */
    has_key_usage: bool,
    /** Key usage's bits, digitalSignature (bit 0) as 0x8000, keyCertSign (bit 5) as 0x0400. */
    key_usage: u16,
    /** Whether there's an extended key usage extension. */
    has_extended_key_usage: bool,
    /** Whether extended key usage allows id-kp-serverAuth. */
    server_auth: bool,
    /** Whether extended key usage allows id-kp-clientAuth. */
    client_auth: bool,
    /** Whether extended key usage has anyExtendedKeyUsage. */
    any_purpose: bool,
    /** The subject alternative names: GeneralNames' contents, empty when there's no extension. */
    alternative_names: u8[],
    /** Whether there's a subject alternative name extension. */
    has_alternative_names: bool,
    /** Name constraints' permitted subtrees: GeneralSubtrees' contents; empty for none. */
    permitted: u8[],
    /** Name constraints' excluded subtrees, the same way; empty for none. */
    excluded: u8[],
}

/** keyCertSign's bit in X509Certificate.key_usage. */
X509_KEY_CERT_SIGN :: 0x0400
/** digitalSignature's bit in X509Certificate.key_usage. */
X509_DIGITAL_SIGNATURE :: 0x8000

/** rsaEncryption's OID, 1.2.840.113549.1.1.1. */
OID_RSA :: u8.[0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01]
/** sha256WithRSAEncryption, 1.2.840.113549.1.1.11. */
OID_RSA_SHA256 :: u8.[0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0b]
/** sha384WithRSAEncryption, 1.2.840.113549.1.1.12. */
OID_RSA_SHA384 :: u8.[0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0c]
/** sha512WithRSAEncryption, 1.2.840.113549.1.1.13. */
OID_RSA_SHA512 :: u8.[0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0d]
/** id-RSASSA-PSS, 1.2.840.113549.1.1.10. */
OID_RSA_PSS :: u8.[0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x0a]
/** id-mgf1, 1.2.840.113549.1.1.8. */
OID_MGF1 :: u8.[0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x08]
/** id-sha256, 2.16.840.1.101.3.4.2.1. */
OID_SHA256 :: u8.[0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]
/** id-sha384, 2.16.840.1.101.3.4.2.2. */
OID_SHA384 :: u8.[0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02]
/** id-sha512, 2.16.840.1.101.3.4.2.3. */
OID_SHA512 :: u8.[0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03]
/** id-ecPublicKey, 1.2.840.10045.2.1. */
OID_EC_PUBLIC_KEY :: u8.[0x2a, 0x86, 0x48, 0xce, 0x3d, 0x02, 0x01]
/** prime256v1, P-256's curve, 1.2.840.10045.3.1.7. */
OID_P256 :: u8.[0x2a, 0x86, 0x48, 0xce, 0x3d, 0x03, 0x01, 0x07]
/** secp384r1, P-384's curve, 1.3.132.0.34. */
OID_P384 :: u8.[0x2b, 0x81, 0x04, 0x00, 0x22]
/** ecdsa-with-SHA256, 1.2.840.10045.4.3.2. */
OID_ECDSA_SHA256 :: u8.[0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x02]
/** ecdsa-with-SHA384, 1.2.840.10045.4.3.3. */
OID_ECDSA_SHA384 :: u8.[0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x03]
/** ecdsa-with-SHA512, 1.2.840.10045.4.3.4. */
OID_ECDSA_SHA512 :: u8.[0x2a, 0x86, 0x48, 0xce, 0x3d, 0x04, 0x03, 0x04]
/** id-Ed25519, 1.3.101.112. */
OID_ED25519 :: u8.[0x2b, 0x65, 0x70]
/** id-kp-serverAuth, 1.3.6.1.5.5.7.3.1. */
OID_SERVER_AUTH :: u8.[0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x01]
/** id-kp-clientAuth, 1.3.6.1.5.5.7.3.2. */
OID_CLIENT_AUTH :: u8.[0x2b, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x02]
/** anyExtendedKeyUsage, 2.5.29.37.0. */
OID_ANY_PURPOSE :: u8.[0x55, 0x1d, 0x25, 0x00]

/**
 * Read an AlgorithmIdentifier that names a hash, as RSA-PSS names its hash and MGF1's: SHA-256, SHA-384 or SHA-512,
 * its parameters NULL or left out.
 *
 * @param element The AlgorithmIdentifier.
 * @return The hash; or null for another, or for malformed DER.
 */
x509_hash_identifier :: fn(element: DerElement) -> RsaHash? {
    if element.tag != DER_SEQUENCE {
        return null
    }
    oid_element := der_expect(element.contents, DER_OID) or_return null
    oid := der_oid(oid_element) or_return null
    if oid_element.rest.count != 0 {
        parameters := der_expect(oid_element.rest, DER_NULL) or_return null
        if parameters.contents.count != 0 || parameters.rest.count != 0 {
            return null
        }
    }
    if der_same(oid, OID_SHA256) {
        return .SHA256
    }
    if der_same(oid, OID_SHA384) {
        return .SHA384
    }
    if der_same(oid, OID_SHA512) {
        return .SHA512
    }
    return null
}

/**
 * Read the one element an EXPLICIT tag wraps.
 *
 * @param element The tagged element.
 * @return What it wraps; or null when that's malformed, or more than one element.
 */
x509_explicit :: fn(element: DerElement) -> DerElement? {
    inside := der_next(element.contents) or_return null
    if inside.rest.count != 0 {
        return null
    }
    return inside
}

/**
 * Read RSASSA-PSS's parameters (RFC 4055, section 3.1), which have to name SHA-256, SHA-384 or SHA-512, MGF1 over
 * the same hash, a salt length, and the trailer 1 or none.
 *
 * @param element The parameters' SEQUENCE.
 * @param salt Where the salt length goes, in bytes, up to 1024.
 * @return The signature algorithm; or null for SHA-1's defaults, another hash, a different hash for MGF1, or malformed
 *     DER.
 */
x509_pss_parameters :: fn(element: DerElement, salt: ptr[mut usize]) -> X509Signature? {
    if element.tag != DER_SEQUENCE {
        return null
    }
    hash_field := der_expect(element.contents, DER_CONSTRUCTED + 0) or_return null
    hash := x509_hash_identifier(x509_explicit(hash_field) or_return null) or_return null
    mask_field := der_expect(hash_field.rest, DER_CONSTRUCTED + 1) or_return null
    mask := x509_explicit(mask_field) or_return null
    if mask.tag != DER_SEQUENCE {
        return null
    }
    mgf := der_expect(mask.contents, DER_OID) or_return null
    mask_hash_element := der_next(mgf.rest) or_return null
    mask_hash := x509_hash_identifier(mask_hash_element) or_return null
    if !der_same(der_oid(mgf) or_return null, OID_MGF1) || mask_hash != hash || mask_hash_element.rest.count != 0 {
        return null
    }
    salt_field := der_expect(mask_field.rest, DER_CONSTRUCTED + 2) or_return null
    length := der_small(x509_explicit(salt_field) or_return null) or_return null
    if length > 1024 {
        return null
    }
    salt^ = cast[usize](length)
    if salt_field.rest.count != 0 {
        trailer_field := der_expect(salt_field.rest, DER_CONSTRUCTED + 3) or_return null
        trailer := der_small(x509_explicit(trailer_field) or_return null) or_return null
        if trailer != 1 || trailer_field.rest.count != 0 {
            return null
        }
    }
    match hash {
        case .SHA256 => return .RSA_PSS_SHA256
        case .SHA384 => return .RSA_PSS_SHA384
        case .SHA512 => return .RSA_PSS_SHA512
    }
}

/**
 * Read a signature's AlgorithmIdentifier.
 *
 * @param element The AlgorithmIdentifier.
 * @param salt Where RSA-PSS's salt length goes; set to 0 for the others.
 * @return The algorithm; or null for one this package doesn't verify, or malformed DER: RSA PKCS #1 v1.5's
 *     parameters have to be NULL or left out, ECDSA's and Ed25519's left out.
 */
x509_signature_algorithm :: fn(element: DerElement, salt: ptr[mut usize]) -> X509Signature? {
    salt^ = 0
    if element.tag != DER_SEQUENCE {
        return null
    }
    oid_element := der_expect(element.contents, DER_OID) or_return null
    oid := der_oid(oid_element) or_return null
    rest := oid_element.rest
    if der_same(oid, OID_RSA_PSS) {
        parameters := der_next(rest) or_return null
        algorithm := x509_pss_parameters(parameters, salt) or_return null
        if parameters.rest.count != 0 {
            return null
        }
        return algorithm
    }
    rsa := der_same(oid, OID_RSA_SHA256) || der_same(oid, OID_RSA_SHA384) || der_same(oid, OID_RSA_SHA512)
    if rsa && rest.count != 0 {
        parameters := der_expect(rest, DER_NULL) or_return null
        if parameters.contents.count != 0 {
            return null
        }
        rest = parameters.rest
    }
    if rest.count != 0 {
        return null
    }
    if der_same(oid, OID_RSA_SHA256) {
        return .RSA_PKCS1_SHA256
    }
    if der_same(oid, OID_RSA_SHA384) {
        return .RSA_PKCS1_SHA384
    }
    if der_same(oid, OID_RSA_SHA512) {
        return .RSA_PKCS1_SHA512
    }
    if der_same(oid, OID_ECDSA_SHA256) {
        return .ECDSA_SHA256
    }
    if der_same(oid, OID_ECDSA_SHA384) {
        return .ECDSA_SHA384
    }
    if der_same(oid, OID_ECDSA_SHA512) {
        return .ECDSA_SHA512
    }
    if der_same(oid, OID_ED25519) {
        return .ED25519
    }
    return null
}

/** A public key read from a SubjectPublicKeyInfo: its kind, and its bytes, a view of what it was read from. */
X509PublicKey :: struct {
    /** The kind of key. */
    kind: X509KeyKind,
    /** The key, as kind says to read it: PKCS #1's RSAPublicKey, SEC 1's point, or Ed25519's 32 bytes; empty for an
     * UNSUPPORTED key. */
    key: u8[],
}

/**
 * Read a SubjectPublicKeyInfo (RFC 5280, section 4.1.2.7): an RSA key (rsaEncryption, its parameters NULL), a P-256
 * or P-384 key (id-ecPublicKey with prime256v1 or secp384r1, its point checked to be on the curve), or an Ed25519 key
 * (RFC 8410).
 *
 * @param der The SubjectPublicKeyInfo's whole DER, and nothing after it.
 * @return The key, its bytes a view of der; UNSUPPORTED for another algorithm or curve that's well formed. Null for
 *     malformed DER, a P-256 key that isn't a point on the curve, an RSA key that isn't an RSAPublicKey, or an Ed25519
 *     key not of 32 bytes.
 */
x509_public_key :: fn(der: u8[]) -> X509PublicKey? {
    info := der_expect(der, DER_SEQUENCE) or_return null
    if info.rest.count != 0 {
        return null
    }
    algorithm := der_expect(info.contents, DER_SEQUENCE) or_return null
    bits_element := der_expect(algorithm.rest, DER_BIT_STRING) or_return null
    bits := der_bit_string(bits_element) or_return null
    if bits_element.rest.count != 0 {
        return null
    }
    oid_element := der_expect(algorithm.contents, DER_OID) or_return null
    oid := der_oid(oid_element) or_return null
    if der_same(oid, OID_RSA) {
        parameters := der_expect(oid_element.rest, DER_NULL) or_return null
        if parameters.contents.count != 0 || parameters.rest.count != 0 {
            return null
        }
        _ = rsa_public_key_from_der(bits) or_return null
        return X509PublicKey.{kind = .RSA, key = bits}
    }
    if der_same(oid, OID_EC_PUBLIC_KEY) {
        curve_element := der_expect(oid_element.rest, DER_OID) or_return null
        curve := der_oid(curve_element) or_return null
        if curve_element.rest.count != 0 {
            return null
        }
        if der_same(curve, OID_P384) {
            p384 := p384_curve()
            point : P384Point
            if !p384_decode_point(&p384, bits, &point) {
                return null
            }
            return X509PublicKey.{kind = .P384, key = bits}
        }
        if !der_same(curve, OID_P256) {
            return X509PublicKey.{kind = .UNSUPPORTED, key = bits[0..<0]}
        }
        point : P256Point
        if !p256_decode_point(bits, &point) {
            return null
        }
        return X509PublicKey.{kind = .P256, key = bits}
    }
    if der_same(oid, OID_ED25519) {
        if oid_element.rest.count != 0 || bits.count != 32 {
            return null
        }
        return X509PublicKey.{kind = .ED25519, key = bits}
    }
    return X509PublicKey.{kind = .UNSUPPORTED, key = bits[0..<0]}
}

/**
 * Read a PKCS #1 RSAPublicKey (RFC 8017, appendix A.1.1): SEQUENCE { modulus INTEGER, publicExponent INTEGER }.
 *
 * @param der The RSAPublicKey's DER, and nothing after it, as an RSA SubjectPublicKeyInfo's BIT STRING holds.
 * @return The key; or null for malformed DER, a negative number, or numbers rsa_public_key refuses.
 */
rsa_public_key_from_der :: fn(der: u8[]) -> RsaPublicKey? {
    sequence := der_expect(der, DER_SEQUENCE) or_return null
    if sequence.rest.count != 0 {
        return null
    }
    modulus_element := der_expect(sequence.contents, DER_INTEGER) or_return null
    exponent_element := der_expect(modulus_element.rest, DER_INTEGER) or_return null
    if exponent_element.rest.count != 0 {
        return null
    }
    modulus := der_unsigned(modulus_element) or_return null
    exponent := der_unsigned(exponent_element) or_return null
    return rsa_public_key(modulus, exponent)
}

/**
 * Read an ECDSA-Sig-Value (RFC 3279, section 2.2.3), SEQUENCE { r INTEGER, s INTEGER }, into r then s.
 *
 * @param der The signature's DER, and nothing after it.
 * @param pair Where r then s go, each right-aligned in half of it: 64 bytes for P-256, 96 for P-384, at most 132.
 * @return Whether it's well-formed DER of two numbers, 0 or more, each fitting half of pair.
 */
ecdsa_signature_from_der :: fn(der: u8[], pair: mut u8[]) -> bool {
    sequence := der_expect(der, DER_SEQUENCE) or_return false
    if sequence.rest.count != 0 || pair.count > 132 {
        return false
    }
    r_element := der_expect(sequence.contents, DER_INTEGER) or_return false
    s_element := der_expect(r_element.rest, DER_INTEGER) or_return false
    r := der_unsigned(r_element) or_return false
    s := der_unsigned(s_element) or_return false
    half := pair.count / 2
    if s_element.rest.count != 0 || r.count > half || s.count > half {
        return false
    }
    for i in 0..<pair.count {
        pair[i] = 0
    }
    for byte, i in r {
        at := half - r.count + i
        if at < pair.count {
            pair[at] = byte
        }
    }
    for byte, i in s {
        at := pair.count - s.count + i
        if at < pair.count {
            pair[at] = byte
        }
    }
    return true
}

/**
 * Read an ECDSA-Sig-Value (RFC 3279, section 2.2.3) as P-256's r then s.
 *
 * @param der The signature's DER, and nothing after it.
 * @return The signature as r then s, 32 bytes each; or null for malformed DER, a negative number, or one over 32
 *     bytes. Whether r and s are from 1 to n - 1 is p256_ecdsa_verify's to check.
 */
p256_signature_from_der :: fn(der: u8[]) -> P256Signature? {
    signature : P256Signature
    if !ecdsa_signature_from_der(der, signature[0..<64]) {
        return null
    }
    return signature
}

/**
 * Read an ECDSA-Sig-Value (RFC 3279, section 2.2.3) as P-384's r then s.
 *
 * @param der The signature's DER, and nothing after it.
 * @return The signature as r then s, 48 bytes each; or null for malformed DER, a negative number, or one over 48
 *     bytes. Whether r and s are from 1 to n - 1 is p384_ecdsa_verify's to check.
 */
p384_signature_from_der :: fn(der: u8[]) -> P384Signature? {
    signature : P384Signature
    if !ecdsa_signature_from_der(der, signature[0..<96]) {
        return null
    }
    return signature
}

/**
 * Check a Name is a SEQUENCE of non-empty SETs of AttributeTypeAndValue SEQUENCEs, each an OID and a value.
 *
 * @param element The Name.
 * @return Whether it's well formed; an empty SEQUENCE is.
 */
x509_name_well_formed :: fn(element: DerElement) -> bool {
    if element.tag != DER_SEQUENCE {
        return false
    }
    names := element.contents
    loop {
        set := der_expect(names, DER_SET) or_return false
        names = set.rest
        attributes := set.contents
        if attributes.count == 0 {
            return false
        }
        loop {
            attribute := der_expect(attributes, DER_SEQUENCE) or_return false
            attributes = attribute.rest
            oid := der_expect(attribute.contents, DER_OID) or_return false
            _ = der_oid(oid) or_return false
            value := der_next(oid.rest) or_return false
            if value.rest.count != 0 {
                return false
            }
        }
        while attributes.count != 0
    }
    while names.count != 0
    return true
}

/**
 * Check GeneralNames, or a GeneralName in a subtree, are well formed: each a context-specific tag 0 to 8, a
 * directoryName a Name, and an rfc822Name's, dNSName's or URI's bytes ASCII.
 *
 * @param contents GeneralNames' contents: one or more GeneralNames one after another.
 * @return Whether they're well formed, at least one of them.
 */
x509_general_names_well_formed :: fn(contents: u8[]) -> bool {
    names := contents
    if names.count == 0 {
        return false
    }
    loop {
        name := der_next(names) or_return false
        names = name.rest
        if (name.tag & 0xc0) != 0x80 || (name.tag & 0x1f) > 8 {
            return false
        }
        if name.tag == DER_CONSTRUCTED + 4 && !x509_name_well_formed(x509_explicit(name) or_return false) {
            return false
        }
        if name.tag == DER_CONTEXT + 1 || name.tag == DER_CONTEXT + 2 || name.tag == DER_CONTEXT + 6 {
            for byte in name.contents {
                if byte >= 0x80 {
                    return false
                }
            }
        }
    }
    while names.count != 0
    return true
}

/** The extensions of a certificate that path validation uses, read from their DER. */
X509Extensions :: struct {
    /** Whether there's a basic constraints extension. */
    has_basic_constraints: bool,
    /** Whether basic constraints say it's a CA. */
    is_ca: bool,
    /** Basic constraints' path length, or -1 for none. */
    path_length: i64,
    /** Whether there's a key usage extension. */
    has_key_usage: bool,
    /** Key usage's bits, as X509Certificate.key_usage holds them. */
    key_usage: u16,
    /** Whether there's an extended key usage extension. */
    has_extended_key_usage: bool,
    /** Whether extended key usage allows id-kp-serverAuth. */
    server_auth: bool,
    /** Whether extended key usage allows id-kp-clientAuth. */
    client_auth: bool,
    /** Whether extended key usage has anyExtendedKeyUsage. */
    any_purpose: bool,
}

/**
 * Read one extension, refusing a critical one this package doesn't understand. Subject alternative names and name
 * constraints, which are views, are read by the caller; this checks them.
 *
 * @param found What's read so far, updated with this extension.
 * @param oid The extension's OID's contents.
 * @param critical Whether it's marked critical.
 * @param value The extnValue OCTET STRING's contents: the extension's own DER.
 * @return Whether it's well formed and, if critical, understood.
 */
x509_extension :: fn(found: ptr[mut X509Extensions], oid: u8[], critical: bool, value: u8[]) -> bool {
    if oid.count != 3 || oid[0] != 0x55 || oid[1] != 0x1d {
        // Not one of id-ce's: authority information access, signed certificate timestamps and the like
        return !critical
    }
    match oid[2] {
        case 0x13 => {
            // Basic constraints
            sequence := der_expect(value, DER_SEQUENCE) or_return false
            fields := sequence.contents
            found.has_basic_constraints = true
            found.path_length = -1
            if der_next_is(fields, DER_BOOLEAN) {
                ca := der_next(fields) or_return false
                // DER leaves a DEFAULT out, so cA FALSE written out is refused
                found.is_ca = der_boolean(ca) or_return false
                if !found.is_ca {
                    return false
                }
                fields = ca.rest
            }
            if fields.count != 0 {
                length := der_expect(fields, DER_INTEGER) or_return false
                found.path_length = der_small(length) or_return false
                if !found.is_ca || length.rest.count != 0 {
                    return false
                }
            }
            return sequence.rest.count == 0
        }
        case 0x0f => {
            // Key usage
            bits := der_next(value) or_return false
            found.has_key_usage = true
            found.key_usage = der_named_bits(bits) or_return false
            return found.key_usage != 0 && bits.rest.count == 0
        }
        case 0x25 => {
            // Extended key usage
            sequence := der_expect(value, DER_SEQUENCE) or_return false
            purposes := sequence.contents
            found.has_extended_key_usage = true
            if purposes.count == 0 {
                return false
            }
            loop {
                element := der_expect(purposes, DER_OID) or_return false
                purposes = element.rest
                purpose := der_oid(element) or_return false
                found.server_auth = found.server_auth || der_same(purpose, OID_SERVER_AUTH)
                found.client_auth = found.client_auth || der_same(purpose, OID_CLIENT_AUTH)
                found.any_purpose = found.any_purpose || der_same(purpose, OID_ANY_PURPOSE)
            }
            while purposes.count != 0
            return sequence.rest.count == 0
        }
        case 0x11 => {
            // Subject alternative names
            sequence := der_expect(value, DER_SEQUENCE) or_return false
            return x509_general_names_well_formed(sequence.contents) && sequence.rest.count == 0
        }
        case 0x1e => {
            // Name constraints: GeneralSubtrees whose minimum is 0 and maximum absent, as RFC 5280 says
            sequence := der_expect(value, DER_SEQUENCE) or_return false
            fields := sequence.contents
            if fields.count == 0 || sequence.rest.count != 0 {
                return false
            }
            for tag in u8.[DER_CONSTRUCTED + 0, DER_CONSTRUCTED + 1] {
                if der_next_is(fields, tag) {
                    subtrees := der_next(fields) or_return false
                    fields = subtrees.rest
                    trees := subtrees.contents
                    if trees.count == 0 {
                        return false
                    }
                    loop {
                        tree := der_expect(trees, DER_SEQUENCE) or_return false
                        trees = tree.rest
                        base := der_next(tree.contents) or_return false
                        if base.rest.count != 0 || !x509_general_names_well_formed(base.whole) {
                            return false
                        }
                    }
                    while trees.count != 0
                }
            }
            return fields.count == 0
        }
        // Subject and authority key identifiers, and certificate policies (not processed, as browsers don't), which
        // may be critical
        case 0x0e => return true
        case 0x23 => return true
        case 0x20 => return true
        case _ => return !critical
    }
}

/**
 * Find an extension's value in a certificate's extensions.
 *
 * @param extensions The Extensions SEQUENCE's contents.
 * @param number The id-ce extension's last arc: 0x11 for subject alternative names, 0x1e for name constraints.
 * @return Its value's SEQUENCE's contents; or null when it isn't there or is malformed.
 */
x509_find_extension :: fn(extensions: u8[], number: u8) -> u8[]? {
    list := extensions
    loop {
        extension := der_expect(list, DER_SEQUENCE) or_return null
        list = extension.rest
        oid := der_expect(extension.contents, DER_OID) or_return null
        if oid.contents.count == 3 && oid.contents[0] == 0x55 && oid.contents[1] == 0x1d && oid.contents[2] == number {
            rest := oid.rest
            if der_next_is(rest, DER_BOOLEAN) {
                critical := der_next(rest) or_return null
                rest = critical.rest
            }
            value := der_expect(rest, DER_OCTET_STRING) or_return null
            sequence := der_expect(value.contents, DER_SEQUENCE) or_return null
            return sequence.contents
        }
    }
    while list.count != 0
    return null
}

/**
 * Read name constraints' subtrees of one kind, permitted or excluded.
 *
 * @param constraints The NameConstraints SEQUENCE's contents.
 * @param tag DER_CONSTRUCTED + 0 for the permitted subtrees, DER_CONSTRUCTED + 1 for the excluded ones.
 * @return The GeneralSubtrees' contents; empty when there are none of that kind.
 */
x509_subtrees :: fn(constraints: u8[], tag: u8) -> u8[] {
    fields := constraints
    loop {
        field := der_next(fields) or_return constraints[0..<0]
        if field.tag == tag {
            return field.contents
        }
        fields = field.rest
    }
    while fields.count != 0
    return constraints[0..<0]
}

/**
 * Read a certificate (RFC 5280, section 4.1), checking its DER and what path validation relies on.
 *
 * @param der The certificate's DER, and nothing after it.
 * @return The certificate, its views of der; or null when it isn't a well-formed certificate this package can use:
 *     malformed DER or a Name, a signature algorithm it doesn't verify, an outer algorithm that isn't the
 *     TBSCertificate's byte for byte, a version that doesn't match what's there (extensions only in 3, unique IDs in 2
 *     or 3, v1 not written out), a public key that's malformed, an extension given twice, or a critical one it
 *     doesn't understand.
 */
x509_parse :: fn(der: u8[]) -> X509Certificate? {
    certificate := X509Certificate.{der = der, version = 1, path_length = -1}
    whole := der_expect(der, DER_SEQUENCE) or_return null
    tbs := der_expect(whole.contents, DER_SEQUENCE) or_return null
    outer_algorithm := der_expect(tbs.rest, DER_SEQUENCE) or_return null
    signature := der_expect(outer_algorithm.rest, DER_BIT_STRING) or_return null
    if whole.rest.count != 0 || signature.rest.count != 0 {
        return null
    }
    certificate.signature = der_bit_string(signature) or_return null
    certificate.tbs = tbs.whole
    fields := tbs.contents
    if der_next_is(fields, DER_CONSTRUCTED + 0) {
        version_field := der_next(fields) or_return null
        version := der_small(x509_explicit(version_field) or_return null) or_return null
        // v1 is the DEFAULT, which DER leaves out
        if version < 1 || version > 2 {
            return null
        }
        certificate.version = version + 1
        fields = version_field.rest
    }
    serial := der_expect(fields, DER_INTEGER) or_return null
    certificate.serial = der_integer(serial) or_return null
    inner_algorithm := der_expect(serial.rest, DER_SEQUENCE) or_return null
    if !der_same(inner_algorithm.whole, outer_algorithm.whole) {
        return null
    }
    certificate.signature_algorithm = x509_signature_algorithm(inner_algorithm, &certificate.pss_salt) or_return null
    issuer := der_expect(inner_algorithm.rest, DER_SEQUENCE) or_return null
    if issuer.contents.count == 0 || !x509_name_well_formed(issuer) {
        return null
    }
    certificate.issuer = issuer.whole
    validity := der_expect(issuer.rest, DER_SEQUENCE) or_return null
    not_before := der_next(validity.contents) or_return null
    not_after := der_next(not_before.rest) or_return null
    if not_after.rest.count != 0 {
        return null
    }
    certificate.not_before = der_time(not_before) or_return null
    certificate.not_after = der_time(not_after) or_return null
    subject := der_expect(validity.rest, DER_SEQUENCE) or_return null
    // An empty subject is allowed, with its names in subject alternative names instead
    if !x509_name_well_formed(subject) {
        return null
    }
    certificate.subject = subject.whole
    info := der_expect(subject.rest, DER_SEQUENCE) or_return null
    certificate.public_key_info = info.whole
    public_key := x509_public_key(info.whole) or_return null
    certificate.key_kind = public_key.kind
    certificate.key = public_key.key
    fields = info.rest
    for tag in u8.[DER_CONTEXT + 1, DER_CONTEXT + 2] {
        if der_next_is(fields, tag) {
            unique := der_next(fields) or_return null
            if certificate.version < 2 {
                return null
            }
            fields = unique.rest
        }
    }
    if fields.count == 0 {
        return certificate
    }
    extensions_field := der_expect(fields, DER_CONSTRUCTED + 3) or_return null
    extensions := x509_explicit(extensions_field) or_return null
    if certificate.version != 3 || extensions_field.rest.count != 0 || extensions.tag != DER_SEQUENCE || extensions.contents.count == 0 {
        return null
    }
    found := X509Extensions.{path_length = -1}
    // Each id-ce extension's last arc, to refuse one given twice
    seen : u8[64]
    seen_count : usize = 0
    list := extensions.contents
    loop {
        extension := der_expect(list, DER_SEQUENCE) or_return null
        list = extension.rest
        oid_element := der_expect(extension.contents, DER_OID) or_return null
        oid := der_oid(oid_element) or_return null
        rest := oid_element.rest
        critical := false
        if der_next_is(rest, DER_BOOLEAN) {
            flag := der_next(rest) or_return null
            // DER leaves the DEFAULT, FALSE, out
            critical = der_boolean(flag) or_return null
            if !critical {
                return null
            }
            rest = flag.rest
        }
        value := der_expect(rest, DER_OCTET_STRING) or_return null
        if value.rest.count != 0 {
            return null
        }
        if oid.count == 3 && oid[0] == 0x55 && oid[1] == 0x1d {
            for i in 0..<seen_count % 65 {
                if seen[i % 64] == oid[2] {
                    return null
                }
            }
            if seen_count < 64 {
                seen[seen_count] = oid[2]
                seen_count += 1
            }
        }
        if !x509_extension(&found, oid, critical, value.contents) {
            return null
        }
    }
    while list.count != 0
    certificate.has_basic_constraints = found.has_basic_constraints
    certificate.is_ca = found.is_ca
    certificate.path_length = found.path_length
    certificate.has_key_usage = found.has_key_usage
    certificate.key_usage = found.key_usage
    certificate.has_extended_key_usage = found.has_extended_key_usage
    certificate.server_auth = found.server_auth
    certificate.client_auth = found.client_auth
    certificate.any_purpose = found.any_purpose
    match x509_find_extension(extensions.contents, 0x11) {
        case Some(names) => {
            certificate.has_alternative_names = true
            certificate.alternative_names = names
        }
        case None => {}
    }
    match x509_find_extension(extensions.contents, 0x1e) {
        case Some(constraints) => {
            certificate.permitted = x509_subtrees(constraints, DER_CONSTRUCTED + 0)
            certificate.excluded = x509_subtrees(constraints, DER_CONSTRUCTED + 1)
        }
        case None => {}
    }
    return certificate
}

/**
 * Check a signature made with a certificate's key, over bytes it signed: a child certificate's TBSCertificate here,
 * or, in TLS, a handshake's CertificateVerify content.
 *
 * @param kind The signer's kind of key.
 * @param key The signer's key, as X509Certificate.key holds it.
 * @param algorithm The signature's algorithm, which has to go with the kind of key.
 * @param salt For RSA-PSS, the salt length in bytes; otherwise ignored.
 * @param message The bytes signed, of any length.
 * @param signature The signature: an RSA signature, an ECDSA-Sig-Value's DER, or Ed25519's 64 bytes.
 * @return VALID; UNSUPPORTED when the algorithm doesn't go with the kind of key, the key is UNSUPPORTED, or an RSA key
 *     has fewer than X509_FEWEST_RSA_BITS bits; BAD_SIGNATURE when the signature isn't the key's on the message, or
 *     is malformed.
 */
x509_verify_signature :: fn(kind: X509KeyKind, key: u8[], algorithm: X509Signature, salt: usize, message: u8[], signature: u8[]) -> X509Verdict {
    hash := RsaHash.SHA256
    if algorithm == .RSA_PKCS1_SHA384 || algorithm == .RSA_PSS_SHA384 || algorithm == .ECDSA_SHA384 {
        hash = .SHA384
    }
    else if algorithm == .RSA_PKCS1_SHA512 || algorithm == .RSA_PSS_SHA512 || algorithm == .ECDSA_SHA512 {
        hash = .SHA512
    }
    digest : u8[64]
    size := rsa_hash_size(hash) % 65
    if kind != .ED25519 {
        rsa_hash_parts(hash, message, message[0..<0], message[0..<0], &digest)
    }
    verified := false
    match kind {
        case .RSA => {
            public := rsa_public_key_from_der(key) or_return .UNSUPPORTED
            if public.modulus.bits < X509_FEWEST_RSA_BITS {
                return .UNSUPPORTED
            }
            if algorithm == .RSA_PKCS1_SHA256 || algorithm == .RSA_PKCS1_SHA384 || algorithm == .RSA_PKCS1_SHA512 {
                verified = rsa_pkcs1_verify(&public, hash, digest[0..<size], signature)
            }
            else if algorithm == .RSA_PSS_SHA256 || algorithm == .RSA_PSS_SHA384 || algorithm == .RSA_PSS_SHA512 {
                verified = rsa_pss_verify(&public, hash, digest[0..<size], signature, salt)
            }
            else {
                return .UNSUPPORTED
            }
        }
        case .P256 => {
            if algorithm != .ECDSA_SHA256 && algorithm != .ECDSA_SHA384 && algorithm != .ECDSA_SHA512 {
                return .UNSUPPORTED
            }
            pair := p256_signature_from_der(signature) or_return .BAD_SIGNATURE
            verified = p256_ecdsa_verify(key, digest[0..<size], &pair)
        }
        case .P384 => {
            if algorithm != .ECDSA_SHA256 && algorithm != .ECDSA_SHA384 && algorithm != .ECDSA_SHA512 {
                return .UNSUPPORTED
            }
            pair := p384_signature_from_der(signature) or_return .BAD_SIGNATURE
            verified = p384_ecdsa_verify(key, digest[0..<size], &pair)
        }
        case .ED25519 => {
            if algorithm != .ED25519 {
                return .UNSUPPORTED
            }
            if key.count != 32 || signature.count != 64 {
                return .BAD_SIGNATURE
            }
            public : Ed25519PublicKey
            for i in 0..<32 {
                public[i] = key[i]
            }
            pair : Ed25519Signature
            for i in 0..<64 {
                pair[i] = signature[i]
            }
            verified = ed25519_verify(&public, message, &pair)
        }
        case .UNSUPPORTED => return .UNSUPPORTED
    }
    if !verified {
        return .BAD_SIGNATURE
    }
    return .VALID
}

/**
 * Say whether a certificate's extended key usage allows a purpose.
 *
 * @param certificate The certificate.
 * @param purpose The purpose.
 * @return True when it has no extended key usage, has anyExtendedKeyUsage, or names the purpose; true for ANY.
 */
x509_allows :: fn(certificate: ptr[X509Certificate], purpose: X509Purpose) -> bool {
    if !certificate.has_extended_key_usage || certificate.any_purpose || purpose == .ANY {
        return true
    }
    if purpose == .SERVER {
        return certificate.server_auth
    }
    return certificate.client_auth
}

/**
 * Lower an ASCII letter.
 *
 * @param byte Any byte.
 * @return Its lowercase letter for A to Z; any other byte as it is.
 */
x509_lower :: fn(byte: u8) -> u8 {
    if byte >= cast[u8]('A') && byte <= cast[u8]('Z') {
        return byte + 32
    }
    return byte
}

/**
 * Say whether two names are the same ASCII, ignoring letters' case.
 *
 * @param a One name.
 * @param b The other.
 * @return Whether they have the same count and the same bytes, a letter's two cases the same.
 */
x509_same_ignoring_case :: fn(a: u8[], b: u8[]) -> bool {
    if a.count != b.count {
        return false
    }
    for byte, i in a {
        if x509_lower(byte) != x509_lower(b[i]) {
            return false
        }
    }
    return true
}

/**
 * Say whether a DNS name is within a dNSName constraint (RFC 5280, section 4.2.1.10): the name itself or a name
 * under it, label by label; a constraint starting with a dot, only names under it; an empty one, every name.
 *
 * @param name The name, like www.example.com.
 * @param constraint The constraint, like example.com or .example.com.
 * @return Whether it's within, ignoring letters' case.
 */
x509_dns_within :: fn(name: u8[], constraint: u8[]) -> bool {
    if constraint.count == 0 {
        return true
    }
    if name.count < constraint.count {
        return false
    }
    start := name.count - constraint.count
    if start > name.count || !x509_same_ignoring_case(name[start..<name.count], constraint) {
        return false
    }
    if constraint[0] == cast[u8]('.') {
        return start > 0
    }
    if start == 0 {
        return true
    }
    before := start - 1
    return before < name.count && name[before] == cast[u8]('.')
}

/**
 * Say whether two mailboxes are the same: the local parts exactly, the hosts ignoring letters' case.
 *
 * @param a One mailbox, local@host.
 * @param b The other.
 * @return Whether they're the same.
 */
x509_mailbox_same :: fn(a: u8[], b: u8[]) -> bool {
    if a.count != b.count {
        return false
    }
    host := false
    for byte, i in a {
        if host {
            if x509_lower(byte) != x509_lower(b[i]) {
                return false
            }
        }
        else if byte != b[i] {
            return false
        }
        host = host || byte == cast[u8]('@')
    }
    return true
}

/**
 * Say whether an email address is within an rfc822Name constraint: a whole mailbox (with an @) the address itself, a
 * host the addresses at it, and a domain starting with a dot those at hosts under it.
 *
 * @param address The address, local@host.
 * @param constraint The constraint.
 * @return Whether it's within: the local part compared exactly, the host ignoring letters' case.
 */
x509_email_within :: fn(address: u8[], constraint: u8[]) -> bool {
    at : usize = address.count
    for byte, i in address {
        if byte == cast[u8]('@') {
            at = i
        }
    }
    if at >= address.count {
        return false
    }
    for byte in constraint {
        if byte == cast[u8]('@') {
            return x509_mailbox_same(address, constraint)
        }
    }
    host := address[at + 1..<address.count]
    if constraint.count > 0 && constraint[0] == cast[u8]('.') {
        return x509_dns_within(host, constraint)
    }
    return x509_same_ignoring_case(host, constraint)
}

/**
 * Say whether an IP address is within an iPAddress constraint: the address and mask, each 4 bytes for IPv4 or 16 for
 * IPv6.
 *
 * @param address The address, 4 or 16 bytes.
 * @param constraint The constraint, twice the address's bytes: the network, then the mask.
 * @return Whether the address, masked, is the network; false when the sizes don't go together.
 */
x509_ip_within :: fn(address: u8[], constraint: u8[]) -> bool {
    if constraint.count != 2 * address.count || constraint.count == 0 {
        return false
    }
    for byte, i in address {
        mask := constraint[(address.count + i) % constraint.count]
        if (byte & mask) != (constraint[i % constraint.count] & mask) {
            return false
        }
    }
    return true
}

/**
 * Say whether a Name is within a directoryName constraint: the constraint's RDNs are the first of the name's, each the
 * same DER.
 *
 * @param name The Name's whole DER.
 * @param constraint The constraint's Name's whole DER.
 * @return Whether the constraint's RDNs begin the name's.
 */
x509_directory_within :: fn(name: u8[], constraint: u8[]) -> bool {
    name_sequence := der_expect(name, DER_SEQUENCE) or_return false
    constraint_sequence := der_expect(constraint, DER_SEQUENCE) or_return false
    names := name_sequence.contents
    wanted := constraint_sequence.contents
    loop {
        a := der_next(wanted) or_return false
        b := der_next(names) or_return false
        if !der_same(a.whole, b.whole) {
            return false
        }
        wanted = a.rest
        names = b.rest
    }
    while wanted.count != 0
    return true
}

/**
 * Say whether a name is within one GeneralSubtree's base, when it's of the same kind.
 *
 * @param tag The name's GeneralName tag: rfc822Name, dNSName, directoryName or iPAddress.
 * @param name The name's contents, or a directoryName's Name's whole DER.
 * @param base The subtree's base GeneralName.
 * @return Whether the base is of the same kind and the name is within it.
 */
x509_within :: fn(tag: u8, name: u8[], base: DerElement) -> bool {
    if base.tag != tag {
        return false
    }
    if tag == DER_CONTEXT + 2 {
        return x509_dns_within(name, base.contents)
    }
    if tag == DER_CONTEXT + 1 {
        return x509_email_within(name, base.contents)
    }
    if tag == DER_CONTEXT + 7 {
        return x509_ip_within(name, base.contents)
    }
    if tag == DER_CONSTRUCTED + 4 {
        constraint := x509_explicit(base) or_return false
        return x509_directory_within(name, constraint.whole)
    }
    return false
}

/**
 * Check one name against a CA's name constraints: within none of its excluded subtrees, and, when it has permitted
 * subtrees of the name's kind, within one of them.
 *
 * @param ca The CA, whose permitted and excluded subtrees are used.
 * @param tag The name's GeneralName tag.
 * @param name The name's contents, or a directoryName's Name's whole DER.
 * @return Whether the name is allowed.
 */
x509_name_allowed :: fn(ca: ptr[X509Certificate], tag: u8, name: u8[]) -> bool {
    excluded := ca.excluded
    loop {
        tree := der_next(excluded) or_return false
        excluded = tree.rest
        if x509_within(tag, name, der_next(tree.contents) or_return false) {
            return false
        }
    }
    while excluded.count != 0
    permitted := ca.permitted
    of_kind := false
    loop {
        tree := der_next(permitted) or_return false
        permitted = tree.rest
        base := der_next(tree.contents) or_return false
        if base.tag == tag {
            of_kind = true
            if x509_within(tag, name, base) {
                return true
            }
        }
    }
    while permitted.count != 0
    return !of_kind
}

/**
 * Say whether GeneralSubtrees have a subtree of a kind of name.
 *
 * @param subtrees GeneralSubtrees' contents, empty for none.
 * @param tag The kind's GeneralName tag.
 * @return Whether a subtree's base has that tag.
 */
x509_subtrees_have :: fn(subtrees: u8[], tag: u8) -> bool {
    trees := subtrees
    loop {
        tree := der_next(trees) or_return false
        trees = tree.rest
        base := der_next(tree.contents) or_return false
        if base.tag == tag {
            return true
        }
    }
    while trees.count != 0
    return false
}

/**
 * Check a certificate's names against a CA's name constraints: its subject as a directoryName, and each of its
 * subject alternative names; a name of a kind the constraints have a subtree of but this package can't check, like a
 * URI, is refused.
 *
 * @param ca The CA with the constraints.
 * @param certificate The certificate below it.
 * @return Whether every name is allowed.
 */
x509_names_allowed :: fn(ca: ptr[X509Certificate], certificate: ptr[X509Certificate]) -> bool {
    if ca.permitted.count == 0 && ca.excluded.count == 0 {
        return true
    }
    subject := der_expect(certificate.subject, DER_SEQUENCE) or_return false
    if subject.contents.count != 0 && !x509_name_allowed(ca, DER_CONSTRUCTED + 4, certificate.subject) {
        return false
    }
    names := certificate.alternative_names
    loop {
        name := der_next(names) or_return false
        names = name.rest
        if name.tag == DER_CONSTRUCTED + 4 {
            directory := x509_explicit(name) or_return false
            if !x509_name_allowed(ca, name.tag, directory.whole) {
                return false
            }
        }
        else if name.tag == DER_CONTEXT + 1 || name.tag == DER_CONTEXT + 2 || name.tag == DER_CONTEXT + 7 {
            if !x509_name_allowed(ca, name.tag, name.contents) {
                return false
            }
        }
        else if x509_subtrees_have(ca.permitted, name.tag) || x509_subtrees_have(ca.excluded, name.tag) {
            return false
        }
    }
    while names.count != 0
    return true
}

/** The certificates of a chain, read, and how the path through them is being built. */
X509Path :: struct #scoped {
    /** The chain's certificates, the leaf first, as they came. */
    certificates: X509Certificate[10],
    /** How many there are, 1 to X509_MOST_CERTIFICATES. */
    count: usize,
    /** The path so far: indices into certificates, the leaf's first, each one's issuer after it. */
    path: usize[10],
    /** How many certificates the path has so far. */
    length: usize,
    /** The trust anchors, DER certificates one after another. */
    anchors: u8[],
    /** The time to check validity at, in seconds since 1970-01-01T00:00:00Z. */
    now: i64,
    /** What the chain is validated for. */
    purpose: X509Purpose,
    /** The most telling reason a path was refused, for when none is found. */
    reason: X509Verdict,
}

/**
 * Keep the most telling reason a candidate path was refused: anything found is more telling than an unknown issuer.
 *
 * @param state The validation, whose reason is updated.
 * @param verdict Why a candidate was refused.
 */
x509_note :: fn(state: ptr[mut X509Path], verdict: X509Verdict) {
    if state.reason == .UNKNOWN_ISSUER || state.reason == .VALID {
        state.reason = verdict
    }
}

/**
 * Say whether a certificate is self-issued: its issuer and subject the same name.
 *
 * @param certificate The certificate.
 * @return Whether they're the same DER.
 */
x509_self_issued :: fn(certificate: ptr[X509Certificate]) -> bool {
    return der_same(certificate.issuer, certificate.subject)
}

/**
 * Check what the path as built, ended by an anchor, has to hold beyond each signature: validity at the time given,
 * the leaf's key usage and purpose, each issuer being a CA allowed the purpose, path lengths, and name constraints.
 *
 * @param state The validation, its path from the leaf to the last certificate below the anchor.
 * @param anchor The trust anchor the path ends at.
 * @return VALID, or why the path is refused.
 */
x509_check_path :: fn(state: ptr[X509Path], anchor: ptr[X509Certificate]) -> X509Verdict {
    length := state.length % (X509_MOST_CERTIFICATES + 1)
    // Each certificate, then the anchor
    for step in 0..<length + 1 {
        certificate := anchor
        if step < length {
            certificate = &state.certificates[state.path[step % X509_MOST_CERTIFICATES] % X509_MOST_CERTIFICATES]
        }
        if state.now < certificate.not_before || state.now > certificate.not_after {
            return .EXPIRED
        }
        if !x509_allows(certificate, state.purpose) {
            return .PURPOSE
        }
        if step == 0 {
            if certificate.has_key_usage && (certificate.key_usage & X509_DIGITAL_SIGNATURE) == 0 && state.purpose != .ANY {
                return .KEY_USAGE
            }
            continue
        }
        // An issuer: a CA, which a version 1 anchor is taken to be
        v1_anchor := step == length && certificate.version == 1
        if !v1_anchor && (!certificate.is_ca || (certificate.has_key_usage && (certificate.key_usage & X509_KEY_CERT_SIGN) == 0)) {
            return .NOT_A_CA
        }
        // CAs below it that aren't self-issued, the leaf not counted
        if certificate.path_length >= 0 {
            below : i64 = 0
            for lower in 1..<step {
                if lower < length {
                    other := &state.certificates[state.path[lower % X509_MOST_CERTIFICATES] % X509_MOST_CERTIFICATES]
                    if !x509_self_issued(other) {
                        below += 1
                    }
                }
            }
            if below > certificate.path_length {
                return .PATH_TOO_LONG
            }
        }
        // Its name constraints on every certificate below it, a self-issued CA's exempt
        for lower in 0..<step {
            if lower < length {
                other := &state.certificates[state.path[lower % X509_MOST_CERTIFICATES] % X509_MOST_CERTIFICATES]
                if (lower == 0 || !x509_self_issued(other)) && !x509_names_allowed(certificate, other) {
                    return .NAME_CONSTRAINTS
                }
            }
        }
    }
    return .VALID
}

/**
 * Extend the path from its last certificate: first to an anchor that issued it, else through each certificate of the
 * chain that did, depth first.
 *
 * @param state The validation, its path at least the leaf; certificates are added to it and taken off again.
 * @return Whether a path to an anchor was found that holds every check.
 */
x509_extend :: fn(state: ptr[mut X509Path]) -> bool {
    length := state.length % (X509_MOST_CERTIFICATES + 1)
    if length == 0 {
        return false
    }
    last := &state.certificates[state.path[(length - 1) % X509_MOST_CERTIFICATES] % X509_MOST_CERTIFICATES]
    anchors := state.anchors
    loop {
        element := der_next(anchors) or_return false
        anchors = element.rest
        match x509_parse(element.whole) {
            case Some(anchor) => {
                if der_same(anchor.subject, last.issuer) {
                    signed := x509_verify_signature(anchor.key_kind, anchor.key, last.signature_algorithm, last.pss_salt, last.tbs,
                        last.signature)
                    if signed != .VALID {
                        x509_note(state, signed)
                    }
                    else {
                        trusted := anchor
                        verdict := x509_check_path(state, &trusted)
                        if verdict == .VALID {
                            return true
                        }
                        x509_note(state, verdict)
                    }
                }
            }
            case None => x509_note(state, .MALFORMED)
        }
    }
    while anchors.count != 0
    if length >= X509_MOST_CERTIFICATES {
        return false
    }
    for i in 1..<state.count % (X509_MOST_CERTIFICATES + 1) {
        used := false
        for j in 0..<length {
            used = used || state.path[j % X509_MOST_CERTIFICATES] == i
        }
        candidate := &state.certificates[i % X509_MOST_CERTIFICATES]
        if !used && der_same(candidate.subject, last.issuer) {
            signed := x509_verify_signature(candidate.key_kind, candidate.key, last.signature_algorithm, last.pss_salt, last.tbs,
                last.signature)
            if signed != .VALID {
                x509_note(state, signed)
            }
            else {
                state.path[length % X509_MOST_CERTIFICATES] = i
                state.length = length + 1
                if x509_extend(state) {
                    return true
                }
                state.length = length
            }
        }
    }
    return false
}

/**
 * Validate a chain of certificates to a trust anchor (RFC 5280, section 6.1, for what TLS needs; see this file's
 * comment for what's checked).
 *
 * @param chain The chain: DER certificates one after another, the leaf first, then the certificates that may lead from
 *     it to an anchor, in any order, as many as X509_MOST_CERTIFICATES in all. Ones not on the path are ignored.
 * @param anchors The trust anchors: DER certificates one after another, of any number, none included. An anchor is
 *     trusted for its key and name; its validity, CA bits, path length, extended key usage and name constraints are
 *     checked too, as if it were in the path. A version 1 anchor, without extensions, is taken to be a CA.
 * @param now The time to check validity at, in seconds since 1970-01-01T00:00:00Z, UTC.
 * @param purpose What the chain is for: SERVER for a TLS server's certificate.
 * @return VALID when some path from the leaf to an anchor holds every check; otherwise the most telling reason one
 *     didn't, UNKNOWN_ISSUER when no issuer was found at all. The leaf's names aren't checked against a host: see
 *     x509_matches_host.
 */
x509_verify_chain :: fn(chain: u8[], anchors: u8[], now: i64, purpose: X509Purpose) -> X509Verdict {
    state := X509Path.{anchors = anchors, now = now, purpose = purpose, reason = .UNKNOWN_ISSUER}
    rest := chain
    if rest.count == 0 {
        return .BAD_CHAIN
    }
    loop {
        if state.count >= X509_MOST_CERTIFICATES {
            return .BAD_CHAIN
        }
        element := der_next(rest) or_return .MALFORMED
        rest = element.rest
        state.certificates[state.count % X509_MOST_CERTIFICATES] = x509_parse(element.whole) or_return .MALFORMED
        state.count += 1
    }
    while rest.count != 0
    state.path[0] = 0
    state.length = 1
    if x509_extend(&state) {
        return .VALID
    }
    return state.reason
}

/**
 * Read a dotted-quad IPv4 address.
 *
 * @param text The text, like 192.0.2.1: four decimal numbers from 0 to 255, without leading zeros, separated by dots.
 * @param address Where its four bytes go.
 * @return Whether it's one.
 */
x509_ipv4 :: fn(text: u8[], address: ptr[mut u8[16]]) -> bool {
    part : usize = 0
    value : u32 = 0
    digits : usize = 0
    for c, i in text {
        if c == cast[u8]('.') {
            if digits == 0 || part >= 3 {
                return false
            }
            address[part % 16] = cast[u8](value)
            part += 1
            value = 0
            digits = 0
        }
        else if c >= cast[u8]('0') && c <= cast[u8]('9') {
            if digits > 0 && value == 0 {
                return false
            }
            value = value * 10 + cast[u32](c - cast[u8]('0'))
            digits += 1
            if value > 255 {
                return false
            }
        }
        else {
            return false
        }
    }
    if digits == 0 || part != 3 {
        return false
    }
    address[3] = cast[u8](value)
    return true
}

/**
 * Read an IPv6 address as RFC 4291 writes it: eight groups of up to four hex digits, one run of zero groups may be ::,
 * and the last two groups may be a dotted quad.
 *
 * @param text The text, like 2001:db8::1, without brackets or a zone.
 * @param address Where its 16 bytes go.
 * @return Whether it's one.
 */
x509_ipv6 :: fn(text: u8[], address: ptr[mut u8[16]]) -> bool {
    groups : u16[8]
    count : usize = 0
    gap : usize = 9
    at : usize = 0
    if text.count >= 2 && text[0] == cast[u8](':') && text[1] == cast[u8](':') {
        gap = 0
        at = 2
    }
    else if text.count >= 1 && text[0] == cast[u8](':') {
        return false
    }
    loop {
        // A dotted quad for the last 32 bits
        dots := false
        for i in at..<text.count {
            dots = dots || text[i] == cast[u8]('.')
        }
        if dots {
            if count > 6 {
                return false
            }
            quad : u8[16]
            if !x509_ipv4(text[at..<text.count], &quad) {
                return false
            }
            groups[count % 8] = (cast[u16](quad[0]) << 8) | cast[u16](quad[1])
            groups[(count + 1) % 8] = (cast[u16](quad[2]) << 8) | cast[u16](quad[3])
            count += 2
            at = text.count
            break
        }
        value : u32 = 0
        digits : usize = 0
        loop {
            c := text[at]
            nibble : u32 = 16
            if c >= cast[u8]('0') && c <= cast[u8]('9') {
                nibble = cast[u32](c - cast[u8]('0'))
            }
            else if c >= cast[u8]('a') && c <= cast[u8]('f') {
                nibble = cast[u32](c - cast[u8]('a')) + 10
            }
            else if c >= cast[u8]('A') && c <= cast[u8]('F') {
                nibble = cast[u32](c - cast[u8]('A')) + 10
            }
            if nibble == 16 {
                break
            }
            value = value * 16 + nibble
            digits += 1
            at += 1
        }
        while at < text.count
        if digits == 0 || digits > 4 || count >= 8 {
            return false
        }
        groups[count % 8] = cast[u16](value)
        count += 1
        if at < text.count {
            if text[at] != cast[u8](':') || at + 1 >= text.count {
                return false
            }
            at += 1
            if text[at] == cast[u8](':') {
                if gap != 9 {
                    return false
                }
                gap = count
                at += 1
            }
        }
    }
    while at < text.count
    if (gap == 9 && count != 8) || (gap != 9 && count >= 8) {
        return false
    }
    // Groups after the gap move to the end, zeros between
    full : u16[8]
    if gap == 9 {
        full = groups
    }
    else {
        for i in 0..<gap % 9 {
            full[i % 8] = groups[i % 8]
        }
        tail := count - gap
        for i in 0..<tail {
            full[(8 - tail + i) % 8] = groups[(gap + i) % 8]
        }
    }
    for i in 0..<8 {
        address[2 * i] = cast[u8](full[i] >> 8)
        address[2 * i + 1] = cast[u8](full[i])
    }
    return true
}

/**
 * Say whether a host name matches a dNSName (RFC 6125, section 6.4): the same, ignoring letters' case, or, for a
 * name whose first label is just *, a host with one more label of its own before the rest.
 *
 * @param host The host name, its labels in A-label form (punycode), without a trailing dot.
 * @param name The certificate's dNSName.
 * @return Whether it matches; a * anywhere but as the whole first label, or one over a single label, never does.
 */
x509_dns_matches :: fn(host: u8[], name: u8[]) -> bool {
    if name.count >= 2 && name[0] == cast[u8]('*') && name[1] == cast[u8]('.') {
        rest := name[1..<name.count]
        // The rest has to have a dot of its own, so *.com matches nothing
        dots : usize = 0
        for byte in rest {
            if byte == cast[u8]('.') {
                dots += 1
            }
        }
        if dots < 2 || host.count <= rest.count {
            return false
        }
        split := host.count - rest.count
        if split > host.count {
            return false
        }
        for byte in host[0..<split] {
            if byte == cast[u8]('.') {
                return false
            }
        }
        return x509_same_ignoring_case(host[split..<host.count], rest)
    }
    for byte in name {
        if byte == cast[u8]('*') {
            return false
        }
    }
    return x509_same_ignoring_case(host, name)
}

/**
 * Say whether a certificate is for a host, as a TLS client checks the server's (RFC 6125; RFC 9525): an IP address
 * against its iPAddress names, a host name against its dNSName names, wildcards in their first label allowed. The
 * subject's common name isn't used.
 *
 * @param certificate The leaf certificate.
 * @param host The host connected to: a name in A-label form (punycode), a trailing dot allowed, or an IPv4 address or
 *     IPv6 one, without brackets.
 * @return Whether one of its subject alternative names matches; false when it has none, or the host is empty.
 */
x509_matches_host :: fn(certificate: ptr[X509Certificate], host: string) -> bool {
    text := bit_cast[u8[]](host)
    if text.count > 0 && text[text.count - 1] == cast[u8]('.') {
        text = text[0..<text.count - 1]
    }
    if text.count == 0 {
        return false
    }
    address : u8[16]
    ip_size : usize = 0
    if x509_ipv4(text, &address) {
        ip_size = 4
    }
    else if x509_ipv6(text, &address) {
        ip_size = 16
    }
    names := certificate.alternative_names
    loop {
        name := der_next(names) or_return false
        names = name.rest
        if ip_size != 0 && name.tag == DER_CONTEXT + 7 && der_same(name.contents, address[0..<ip_size % 17]) {
            return true
        }
        if ip_size == 0 && name.tag == DER_CONTEXT + 2 && x509_dns_matches(text, name.contents) {
            return true
        }
    }
    while names.count != 0
    return false
}
