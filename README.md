# Signatures

Borrowing to the point of theft from https://github.com/Rosuav/StilleBot.

## Dependencies

- gtk2 (`brew install gtk+`)
- Pike 9+

## Development

There's an `.editorconfig` file to help with consistency between devs and environments.
For VS Code [this extension](https://marketplace.visualstudio.com/items?itemName=EditorConfig.EditorConfig) will enable it.
There are extensions for other editors as well.

### Pike

Array `({})`
Mapping `([])`
Set `(<>)`
Split string `string / "boundary"`
While app is running, type `update` to hot reload.
A file is a class (or "program" (from LPC)) in Pike, so at top of file you can: `inherit`.
Create a program within a program (file/class) using the `class` keyword. This will be of _type_ `program`.

To get extra debug information on stdout: `pike -DSP_DEBUG app`
