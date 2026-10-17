#!/usr/bin/env python3
"""Apply the narrow standard-python comm compatibility fix to Quarto 1.10.19."""

import ast
import hashlib
from pathlib import Path
import sys


ORIGINAL_SHA256 = "542cf629c668fbecbb1edca6c2f5523e718c43de8c39900197e7778b181746e4"
ORIGINAL = '''    msg = client.kc.session.msg(
        "comm_open",
        {
            "comm_id": "quarto_comm",
            "target_name": "quarto_kernel_setup",
            "data": {"options": quarto_kernel_setup_options},
        },
    )
    client.kc.shell_channel.send(msg)
'''
# This optional custom-kernel handshake has no target in standard ipykernel.
# Standard Python's actual Quarto initialization uses the injected setup cell.
# Retain the handshake for custom Python names and all other kernel languages.
GUARD = (
    "    if not (get_language_from_nb_metadata(client.nb.metadata) == 'python' "
    "and client.nb.metadata.kernelspec.name == 'python3'):\n"
)
PATCHED = GUARD + "".join("    " + line for line in ORIGINAL.splitlines(keepends=True))


def digest(source: bytes) -> str:
    return hashlib.sha256(source).hexdigest()


def patch(path: Path) -> None:
    source_bytes = path.read_bytes()
    source = source_bytes.decode("utf-8")
    # Idempotence still verifies the complete original source by reversing the
    # one exact patch; an unrelated modification must never be silently trusted.
    if source.count(PATCHED) == 1:
        restored = source.replace(PATCHED, ORIGINAL, 1).encode("utf-8")
        if digest(restored) != ORIGINAL_SHA256:
            raise SystemExit("Refusing modified Quarto source with an existing patch")
        ast.parse(source, filename=str(path))
        print(f"Quarto Jupyter patch already present: {digest(source_bytes)}")
        return
    if digest(source_bytes) != ORIGINAL_SHA256:
        raise SystemExit("Refusing unexpected Quarto Jupyter source SHA-256")
    if source.count(ORIGINAL) != 1:
        raise SystemExit("Expected exactly one Quarto kernel setup handshake")
    patched = source.replace(ORIGINAL, PATCHED, 1)
    ast.parse(patched, filename=str(path))
    path.write_bytes(patched.encode("utf-8"))
    print(f"Patched Quarto Jupyter source: {digest(patched.encode('utf-8'))}")


if __name__ == "__main__":
    if len(sys.argv) > 2:
        raise SystemExit("Usage: patch-quarto-jupyter.py [notebook.py]")
    patch(Path(sys.argv[1]) if len(sys.argv) == 2 else Path("/opt/quarto/share/jupyter/notebook.py"))
