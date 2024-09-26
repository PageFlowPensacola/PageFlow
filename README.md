# Signatures

Borrowing to the point of theft from https://github.com/Rosuav/StilleBot.

## Dependencies

- gtk2 (`brew install gtk+`)  (Is this still a dependency?)
- Pike 9+
- Image Magic (`brew install imagemagick`)
– Tesseract

## Required Steps on Initial Setup

### Python requirements
* `$ pip install -r requirements.txt` (Install Python pip if necessary).

### Seed the database
* `$ pike app --exec=seed_domains {--confirm}`
* `$ pike app --exec=domain_import {--confirm}` // for now

### Run the app
* `pike app`


## Database
To initialize database run `pike app.pike --exec=tables`
View `pike app.pike --exec=help` for utils to populate some required fields.
Two initial insertions along the lines of:
```sql
insert into templates (id, name, domain) values (0, 'default', 'com.pageflow.');
insert into template_signatories (id, name, template_id) values (0, 'Unspecified', 0)
```

## Helpful Command Line Utilities

There are methods in `utils.pike` which can be called with the syntax `pike app --exec={some_utility} {--named or positional params }

View methods by calling `pike app --help` (or `pike app --exec=help`).

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
`@` is the spread operator

To get extra debug information on stdout: `pike -DSP_DEBUG app`

## Markdown Parsing

Markdown elements can receive a following  `> `

The `render()` method of `http_request` (which inherits from (currently) `websocket_handler`) accepts
a mapping, which is a set of replacements.
When `vars` is submitted, it writes js vars into a script tag.
There are also some defaults, for example `ws_type` and `ws_code`, which
default to the module name (eg `index` and `/static/index.js`) _if_ `ws_group` is
present.
For example:
```
return render(req,
	([
			"vars": (["ws_group": "", "helloworld": 1234]),
			"foo": "foo-value",
	]));
	```

Will yield:
```
<script>let helloworld = 1234;
let ws_group = "";
let ws_type = "index";
let ws_code = "/static/index.js";
let ws_sync = null; import('/static/ws_sync.js?mtime=1711459399').then(m => ws_sync = m);</script>
```

Here's an example markdown with additional variables (and defaults) defined:

```
constant markdown = #"# PageFlow Index Screen

* This is a variable: $$foo$$
* This variable has no value but a default: $$bar||bar-default$$
";
```

Markdown can be rendered directly via the http module (`index.pike`, etc), or via
a `.md` file with matching name. The one in the pike file takes precedence.

### Websockets

Group will always follow pattern: {org:item?}

### Signature Detection

git@github.com:ahmetozlu/signature_extractor.git

### More native apps
brew install --cask pdf-images
brew install pdf2image
`convert -density 300 "test_files/Residential Contract for Sale And Purchase One Initials Set.pdf" -background cyan -alpha Remove test_files/OneInitialsSet.png`
https://imagemagick.org/script/command-line-options.php?#write

### Utilities
`pike app.pike --exec=update_page_bounds`
`pike app.pike --exec=compare_scores`
`pike app.pike --exec=audit_score`

### Tesseract

We use Tesseract to generate a text bounding box on template and submitted files.
Tesseract's `makebox` param generates `w 92 708 100 73 0` for each line where
the five columns are the found letter, the four coordinates and the page number.

[HOCR Specs https://kba.github.io/hocr-spec/1.2/](https://kba.github.io/hocr-spec/1.2/)

### Audit Rectangles

For each page template, a number of audit rectangles are stored.
Each submitted file is compared to matching template and scored
based on the dark/light transition count within the bounds of the
rectangle area.
To account for varying margins between template file and submitted file,
the bounds of page text area are calculated and when comparing each
rectangle is rescaled proportionally to the page bounds, with
corresponding margins adjusted to match the saved page rect (which
does not take into account page text bounds).

### Some Python ML/NLP Resources that may be useful

* Lankchain - chat-focused
* Giskrd - library for evaluating bias of models

### Alternative Rosuav Signature Recognition Algorithm July 2024

* Maintain a previous row and a previous cell (in current row). Initially all zeroes.
* For each pixel in current row:
  - If pixel is white(ish), select Whites, else select Blacks.
  - If pixel above is of the same set, use that (after redirect).
  - If pixel to the left is of same set, use that (after redirect).
  - If both are of same set and different, merge them.
    - Record a redirect from the higher numbered to the lower.
    - Combine their scores
- If both are of other set (or zero), assign the next available number. Never reuse numbers.
  - Increment the score for this pixel's number
* When done, you will have a list of areas and their sizes.
* Discard any areas deemed too small (eg <5 pixels)
* A signed document should have a few (1-3) large black areas and a good number of white areas
* One large black area and one large white area implies a splodge, probably not a signature
* One large white and no black implies blank
* One large black and no white implies a scanning problem
