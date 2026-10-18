# m1ddc source provenance

- Source: https://github.com/waydabber/m1ddc
- Revision: 04d949794102eb8df01ad3681afff6464a3eede2
- License: MIT, retained in LICENSE and bundled with app.
- Imported: 2026-10-18; headers/, sources/, Makefile, LICENSE.

Local changes: DDC read wait 50ms for the attached LG ULTRAFINE; UInt16 copy lengths corrected from sizeof(2); VCP response header/result/code/checksum validation; optional DDC_DEBUG_RESPONSE diagnostic output. Build output and object files are ignored. The helper supports Apple Silicon, not Intel. LG read/write was exercised at 100 → 99 → 100; Samsung S9 uses the existing network path.
