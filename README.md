# ESP Slides

A local, project-less Elements Server Pages app that renders Markdown decks with
Oxygene and Elements.Markdown. The browser uses plain JavaScript and CSS.

## Start a deck

Use a current Elements installation with Core EBuild on your PATH and the .NET
10 SDK. Keep the app in one folder and pass the Markdown file from wherever
you keep the deck.

```sh
~/Code/RemObjects/Slides/slides "/path/to/my talk/slides.md"
open http://localhost:8055/
```

With no arguments, the launcher opens the bundled RemObjects Infrastructure
sample. Pass a port as the second argument to run another deck alongside the
first. The app runs on the machine that can read the deck and serves the deck
only to a local browser.

## Edit and present

Edit the original Markdown in any editor. Saving refreshes the displayed
content within about a second and keeps the current slide selected.

Use left and right arrows or Page Up and Page Down to navigate. Space advances,
Shift+Space goes back, Home and End jump, and F toggles fullscreen.

Put `---` on its own line between slides. Use ATX headings such as `# Title`
because an unindented `---` is a slide separator. Separators inside fenced
code blocks and standalone HTML comments stay with their slide. Use optional
front matter for the deck `title` and slide `layout` (`default`, `cover`,
`section`, or `center`). Fenced Mermaid renders using the browser runtime
bundled with Elements.Markdown.

Relative Markdown image links such as `![Diagram](assets/diagram.svg)` resolve
inside the deck's own folder. PNG, JPEG, GIF, SVG, WebP, AVIF, MP3, WAV, MP4 and
WebM assets can be served from that folder. This prototype uses Markdown and
built-in layouts, with selected Slidev syntax supported below.

## Present from two windows

The default presenter view shows the current slide, next slide, notes, and
presentation and slide timers. Choose **Presentation View** or press P to open the synced
audience window. It shows the slide at the largest size that fits while
preserving its aspect ratio. Press F in that window for browser fullscreen.
Either window can advance. Use **Overview** or O from the presenter view
to jump to a slide. Put speaker notes in the final standalone Markdown
comment of a slide.

Wrap a Markdown list in `<v-clicks>` and `</v-clicks>` to reveal its top-level
items one at a time. For arbitrary Markdown blocks, use `<v-click>` or
`<div v-click>`. Use `<v-after>` or `<div v-after>` to reveal a block with
the previous step. Put opening and closing tags on their own unindented lines.

A code fence such as `oxygene {1|2-4|*}` highlights line 1 initially,
then lines 2–4 on the next click, then clears the emphasis. Line groups
can include multiple ranges, such as `{1,3-4|6}`. Use the regular
forward and back keys to move through steps.

## Planned durations

Use `duration: 35m` in the opening front matter to plan the whole talk.
Use `slideDuration: 2m` there to time the first slide. On any later slide,
use `duration: 2m` in that slide's front matter. Durations accept seconds
(`90s`), minutes (`2m` or `2min`), hours (`1h`), or minutes and seconds
(`2:30`).

The presenter shows elapsed time and, when a duration is set, time and
percentage remaining. Each timer has its own reset. Changing slides
restarts the slide timer. Stepping through reveals and saving the deck
keep the timers running.

## Logo and theme

Set a default in the first front matter block.

```yaml
---
title: RemObjects Infrastructure
logo: assets/remobjects.svg
theme: light
---
```

The logo sits in the upper-right corner. Relative images resolve from the
deck folder. A slide's own front matter can use a different `logo:` path
or set `logo: false` to hide it for that slide. Set `theme: light` or
`theme: dark` on the deck or individual slide.
