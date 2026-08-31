# Protocol conformance

Conformance fixtures give every Murmur SDK the same observable behavior. They
use the ProtoJSON field names and enum values defined in `spec/`.

An SDK is conformant for a fixture set when it can:

1. parse every line without losing the protocol, session, sequence, timing, or
   payload variant;
2. reject an unknown payload variant rather than silently treating it as a
   command;
3. preserve 64-bit integer values even on runtimes whose JSON number type
   cannot represent them safely;
4. serialize an equivalent ProtoJSON object; object key order is irrelevant;
5. keep transcript text and audio out of diagnostics produced during parsing.

Fixtures contain synthetic text only. Real recordings and conversations do not
belong in this directory.
