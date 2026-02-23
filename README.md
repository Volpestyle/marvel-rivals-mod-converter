# Marvel Rivals Old->New Mod Converter

Small utility to convert **old loose-asset mods** (with `Content/...` files like `.uasset/.uexp/.ubulk`) into the **new Marvel Rivals `~mods` format** (`.pak + .ucas + .utoc`).

## Included

- `convert_marvel_rivals_mod.sh` - converter script
- `convert_marvel_rivals_mod.bat` - Windows launcher for the converter

## Requirements

- WSL/Linux shell (`bash`)
- `retoc.exe` (recommended from the retoc release)
- `unzip` and `wslpath` available in WSL

## Setup

1. Put `retoc.exe` in this same folder, **or**
2. Pass the path with `--retoc`.

Default game mods folder:

`C:\Program Files (x86)\Steam\steamapps\common\MarvelRivals\MarvelGame\Marvel\Content\Paks\~mods`

By default the converter stages files into `Marvel/Content/...` before packing, which matches the typical Marvel Rivals project layout.

## Usage

### WSL/bash usage

```bash
./convert_marvel_rivals_mod.sh /path/to/old_mod_folder --name MyMod
```

Convert from zip:

```bash
./convert_marvel_rivals_mod.sh /path/to/old_mod.zip --name MyMod
```

Convert and auto-install into game `~mods`:

```bash
./convert_marvel_rivals_mod.sh /path/to/old_mod.zip --name MyMod --install
```

If `retoc.exe` is elsewhere:

```bash
./convert_marvel_rivals_mod.sh /path/to/old_mod --name MyMod --retoc "/mnt/c/Users/you/Downloads/retoc-x86_64-pc-windows-msvc/retoc.exe"
```

If a game variant uses a different project folder name:

```bash
./convert_marvel_rivals_mod.sh /path/to/old_mod --name MyMod --project-name Marvel
```

### Windows `.bat` usage

From Command Prompt in this folder:

```bat
convert_marvel_rivals_mod.bat "C:\path\to\old_mod.zip" --name MyMod --install
```

You can pass either Windows-style paths (`C:\...`) or WSL paths (`/mnt/c/...`).

## Output

By default, files are written to `./converted_mods`:

- `MyMod_9999999_P.pak`
- `MyMod_9999999_P.ucas`
- `MyMod_9999999_P.utoc`

You can change output folder with `--output-dir`.

## Notes

- Default engine version is `UE5_3` because it matches typical current Marvel Rivals mod container format.
- If needed, try `--version UE5_4` or `--version UE5_5`.
