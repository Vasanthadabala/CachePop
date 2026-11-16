# Color refinement — build 15

Restores color where it distinguishes categories, measurements and status while retaining the compact build 14 layout.

- Clean Up uses seven category colors shared by scanning indicators, summary legends, selected bar segments and group icons. Unselected portions remain gray.
- Category icons use a colored glyph and soft tint. Sidebar icons and review badges identify their section without coloring the row or its text.
- Large Files distinguishes large files from extra copies. Disk Usage distinguishes applications, the home folder, system/other data and free space. Photos and Login Items regain their category accents through the shared palette.
- Monitor charts, rings and menu-panel graphs share metric colors: blue CPU, purple GPU, teal Memory, cyan Drive, green Battery and pink temperature. Read/write uses blue/teal in both charts and labels. Memory breakdown rows and CPU efficiency/performance bars are distinct.
- Text, surfaces and ordinary controls retain the compact neutral styling. Actions remain blue, and existing status/destructive colors are preserved. Sensor popup icons remain monochrome.
- Category colors have separate light/dark values, with brighter chart strokes and glyphs on dark surfaces.

Validation: three existing native UI checks passed, covering all six monitor pages in both appearances, all main app scan/review/navigation flows, and monochrome sensor popup icons in light/dark mode. Captured screenshots were visually reviewed. This is a presentation-only change; sampling, scan behavior and menu capsule sizing are unchanged.

Review artifacts: `build/color-refinement-2026-11-15/`. The development DMG is signed locally and is not notarized.
