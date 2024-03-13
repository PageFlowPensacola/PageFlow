# Signatures

Borrowing to the point of theft from https://github.com/Rosuav/StilleBot.

## Dependencies
  * gtk2 (`brew install gtk+`)
  * Pike 9+

## Development

There's an `.editorconfig` file to help with consistency between devs and environments.
For VS Code [this extension](https://marketplace.visualstudio.com/items?itemName=EditorConfig.EditorConfig) will enable it.
There are extensions for other editors as well.

### Pike

Can install with `brew install pike` BUT we want version 9 for async.

Stable is version 8.

So, download and run `make configure` then `make`.

For Pike on osx in bash/zsh env `xcode-select --install` and also:
Check output of `brew ls -v gmp` and ensure dir with `libgmp.a` is in LDFLAGS
Also `CPPFLAGS` _may_ require `/usr/local/include`
eg:
```
CPPFLAGS="$CPPFLAGS -I/usr/local/include"
LDFLAGS="$LDFLAGS -L/usr/local/Cellar/gmp/6.3.0/lib/"
# export both, of course
```

### Additional steps and notes:

As of Pike Master (v9) 12 March 2024, on osx, if there are `@` like Homebrew puts in it's paths,
in your LDFLAGS, compilation won't work. You'll either have to manually update the
`linker_options` in `build/.../modules` and `build/.../modules/gmp`, adding two flags
to the end of `/Users/mikekilmer/pike/build/darwin-22.6.0-x86_64/modules/Gmp/module.a`,
so that it reads `...modules/Gmp/module.a -lgmp  -lmpfr` _or_ remove the offending
library paths from LDPATHS for the `make configure`, then reenstate.
