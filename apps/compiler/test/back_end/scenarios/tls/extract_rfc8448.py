"""
Reads RFC 8448's Simple 1-RTT Handshake (section 3) and writes its values as Hemera constants, rfc8448.hsc, for the tls
scenario. The RFC's text is downloaded from https://www.rfc-editor.org/rfc/rfc8448.txt:

    python -I extract_rfc8448.py <rfc8448.txt> rfc8448.hsc
"""
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="ascii", errors="replace").splitlines()
# Section 3's lines, page headers and footers dropped
start = next(i for i, line in enumerate(text) if line.startswith("3.  Simple 1-RTT Handshake"))
end = next(i for i, line in enumerate(text) if line.startswith("4.  Resumed 0-RTT Handshake"))
lines = [line for line in text[start:end] if not line.startswith("RFC 8448") and not line.startswith("Thomson")
         and "\f" not in line]

steps = []
step = None
field = None
for line in lines:
    found = re.match(r"^   \{(client|server)\}\s+(.*)$", line)
    if found:
        step = {"who": found.group(1), "what": found.group(2).strip(), "fields": {}}
        steps.append(step)
        field = None
        continue
    if step is None:
        continue
    found = re.match(r"^      ([A-Za-z][A-Za-z ]*?) \((\d+) octets\):\s*(.*)$", line)
    if found:
        field = found.group(1)
        step["fields"][field] = (int(found.group(2)), found.group(3).split())
        continue
    if field is not None and re.match(r"^\s+[0-9a-f]{2}( [0-9a-f]{2})*\s*$", line):
        step["fields"][field][1].extend(line.split())
        continue
    # A blank line, as a page break makes, doesn't end a field; prose does
    if line.strip() != "":
        field = None


def value(who, what, name, nth=0):
    matches = [each for each in steps if each["who"] == who and each["what"].startswith(what) and name in each["fields"]]
    count, octets = matches[nth]["fields"][name]
    assert len(octets) == count, (who, what, name, count, len(octets))
    return octets


wanted = [
    ("CLIENT_SECRET_KEY", "the client's X25519 secret key", ("client", "create an ephemeral x25519", "private key")),
    ("CLIENT_PUBLIC_KEY", "the client's X25519 public key", ("client", "create an ephemeral x25519", "public key")),
    ("CLIENT_HELLO", "the ClientHello, as a handshake message", ("client", "construct a ClientHello", "ClientHello")),
    ("CLIENT_HELLO_RECORD", "the ClientHello's record", ("client", "send handshake record", "complete record")),
    ("SERVER_SECRET_KEY", "the server's X25519 secret key", ("server", "create an ephemeral x25519", "private key")),
    ("SERVER_PUBLIC_KEY", "the server's X25519 public key", ("server", "create an ephemeral x25519", "public key")),
    ("SERVER_HELLO", "the ServerHello, as a handshake message", ("server", "construct a ServerHello", "ServerHello")),
    ("SERVER_HELLO_RECORD", "the ServerHello's record", ("server", "send handshake record", "complete record")),
    ("EARLY_SECRET", "the early secret", ("server", 'extract secret "early"', "secret")),
    ("HANDSHAKE_SECRET", "the handshake secret", ("server", 'extract secret "handshake"', "secret")),
    ("CLIENT_HANDSHAKE_SECRET", "client_handshake_traffic_secret", ("server", 'derive secret "tls13 c hs traffic"', "expanded")),
    ("SERVER_HANDSHAKE_SECRET", "server_handshake_traffic_secret", ("server", 'derive secret "tls13 s hs traffic"', "expanded")),
    ("MASTER_SECRET", "the master secret", ("server", 'extract secret "master"', "secret")),
    ("SERVER_HANDSHAKE_KEY", "the server's handshake write key", ("server", "derive write traffic keys for handshake data", "key expanded")),
    ("SERVER_HANDSHAKE_IV", "the server's handshake write IV", ("server", "derive write traffic keys for handshake data", "iv expanded")),
    ("SERVER_FINISHED", "the server's Finished, as a handshake message", ("server", "construct a Finished", "Finished")),
    ("SERVER_HANDSHAKE_PAYLOAD", "the server's encrypted handshake messages, in the clear", ("server", "send handshake record", "payload", 1)),
    ("SERVER_HANDSHAKE_RECORD", "the server's encrypted handshake record", ("server", "send handshake record", "complete record", 1)),
    ("CLIENT_APPLICATION_SECRET", "client_application_traffic_secret_0", ("server", 'derive secret "tls13 c ap traffic"', "expanded")),
    ("SERVER_APPLICATION_SECRET", "server_application_traffic_secret_0", ("server", 'derive secret "tls13 s ap traffic"', "expanded")),
    ("EXPORTER_SECRET", "exporter_master_secret", ("server", 'derive secret "tls13 exp master"', "expanded")),
    ("SERVER_APPLICATION_KEY", "the server's application write key", ("server", "derive write traffic keys for application data", "key expanded")),
    ("SERVER_APPLICATION_IV", "the server's application write IV", ("server", "derive write traffic keys for application data", "iv expanded")),
    ("CLIENT_HANDSHAKE_KEY", "the client's handshake write key", ("server", "derive read traffic keys for handshake data", "key expanded")),
    ("CLIENT_HANDSHAKE_IV", "the client's handshake write IV", ("server", "derive read traffic keys for handshake data", "iv expanded")),
    ("CLIENT_FINISHED", "the client's Finished, as a handshake message", ("client", "construct a Finished", "Finished")),
    ("CLIENT_FINISHED_RECORD", "the client's Finished's record", ("client", "send handshake record", "complete record", 1)),
    ("CLIENT_APPLICATION_KEY", "the client's application write key", ("client", "derive write traffic keys for application data", "key expanded")),
    ("CLIENT_APPLICATION_IV", "the client's application write IV", ("client", "derive write traffic keys for application data", "iv expanded")),
    ("TICKET_RECORD", "the server's NewSessionTicket's record", ("server", "send handshake record", "complete record", 2)),
    ("APPLICATION_DATA", "the application data each side sends", ("client", "send application_data record", "payload")),
    ("CLIENT_DATA_RECORD", "the client's application data record", ("client", "send application_data record", "complete record")),
    ("SERVER_DATA_RECORD", "the server's application data record", ("server", "send application_data record", "complete record")),
    ("CLIENT_ALERT_RECORD", "the client's close_notify record", ("client", "send alert record", "complete record")),
    ("SERVER_ALERT_RECORD", "the server's close_notify record", ("server", "send alert record", "complete record")),
]

out = ["package tls_test", "", "/*",
       " * RFC 8448's Simple 1-RTT Handshake (section 3), its values as the RFC prints them: written by",
       " * extract_rfc8448.py from the RFC's text. Don't edit; run the script again.",
       " */", ""]
for name, what, spec in wanted:
    octets = value(*spec)
    out.append(f"/** RFC 8448 section 3: {what}, {len(octets)} bytes. */")
    rows = [", ".join("0x" + octet for octet in octets[i:i + 16]) for i in range(0, len(octets), 16)]
    out.append(f"{name} :: u8.[")
    for row in rows:
        out.append(f"    {row},")
    out.append("]")
    out.append("")
Path(sys.argv[2]).write_text("\n".join(out), encoding="utf-8", newline="\n")
print(f"{len(wanted)} values, {len(steps)} steps")
