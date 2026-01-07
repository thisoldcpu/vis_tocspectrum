# vis_tocspectrum

![ARX39Ff_d](https://github.com/user-attachments/assets/78e84221-1e2c-441e-8e47-fb21bbd1096c)

![ZehAKBQ_d](https://github.com/user-attachments/assets/7d153fb6-328e-4bb6-ab8b-c2465f01b15d)

**ThisOldCPU’s OpenGL Spectrum Analyzer for Winamp 5+**

A modern Winamp visualization plugin inspired by the clean, functional aesthetics of early 2000s spectrum analyzers with a visual direction loosely influenced by the iZotope Ozone 5 era.

This project aims to bring a high-quality, GPU-accelerated spectrum analyzer to Winamp while respecting the architectural and behavioral expectations of classic Winamp visualization plugins.

---

## Features

- OpenGL-based rendering (fixed-function, compatibility profile, additional renderers being ported)
- Real-time spectrum visualization
- No dependencies
- Designed for correctness, clarity, and longevity

This plugin is **not** a port of any existing visualization and does **not** reuse proprietary code or assets.

---

## Design Philosophy

This project intentionally follows a few hard rules:

- Winamp stays in control
  - No message-pumping in `Render`
  - No `Application.*` usage
  - No window reparenting hacks
- Explicit OpenGL state
  - Known-state rendering every frame
  - No reliance on undefined driver behavior
- Delphi-first
  - No C/C++ shims
  - No unnecessary SDK abstraction layers
- Readable over clever
  - Clear math
  - Predictable transforms
  - Debuggable visuals

If you are looking for shader-heavy, modern-core OpenGL effects, this is **not** that project.

---










## Build Requirements

- **Delphi 12.x** (Win32)
- **Winamp 5.x** (Classic)
- Windows (tested on Windows 10/11)
- OpenGL driver with compatibility profile support

No external libraries are required.

---

## Project Structure

```text
vis_tocspectrum/
├── vis_tocspectrum.dpr   // Plugin entry point
├── vis.pas               // Winamp vis.h port
├── window.gl.pas         // OpenGL window + WGL setup
├── render.gl.pas         // All rendering logic
├── font.gl.pas           // Bitmap/vector font handling
├── form.config.pas       // Configuration dialog
└── resources (.res)
```

---

## Status

**Active development.**

Breaking changes may occur during development.

---

## Contributing

Contributions are welcome, but please understand the constraints:

- Delphi code only
- No framework creep
- No Winamp behavior regressions
- Preserve historical compatibility

If in doubt, open an issue before submitting a PR.

---

## License

Copyright (c) 2002–2025 Jason McClain / ThisOldCPU


This project is licensed under the **GNU General Public License v3.0 or later**.

You may redistribute and/or modify this software under the terms of the GPL.
There is **no warranty** of any kind.

See `LICENSE` or <https://www.gnu.org/licenses/> for full details.

---

## Acknowledgements

- **Jan Horn** (2002)
- **Michael John Sarver** (2005)
- The Winamp community — for keeping the platform alive long enough to matter

---

## Links

- GitHub repository:  
  https://github.com/thisoldcpu/vis_tocspectrum

