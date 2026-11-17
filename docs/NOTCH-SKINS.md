# Notch skins

A notch skin is an image Kannu draws behind the notch, in place of the plain black fill. It shows
when the notch is open and, as a thin strip, when it is closed.

Pick one under **Brain › Settings › Appearance › Notch skin**:

- **Default**: the plain fill.
- **Horns**: red and black, built in.
- **Your own**: click **Upload skin** or drop an image on the grid. PNG, JPG, WebP, HEIC, GIF and
  SVG work; a raster image must be at least 200 × 40 pixels. Right-click an uploaded skin to remove
  it.

If the agent light or the text is hard to read on a skin, raise **Scrim opacity**: it lays black
over the image, up to 60%.

## Size and safe areas

Kannu scales a skin to fill the notch and crops what does not fit, keeping the centre.

- **Open:** 640 × 200 points by default (wider if you widen the notch or turn on more tabs). An
  image of **1920 × 600 pixels** is three times that, so it stays sharp on a Retina display.
- **Closed:** about 150–200 × 32 points, and about 250–320 × 32 points while an agent switches:
  the agent light then sits at the strip's left end and the agent's app icon at its right end
  (the sideways pill, 2.0's default). The full width shows, cropped to roughly the middle 40% of
  the height.
- **The corridor:** keep a calm, dark band through the middle of the image, edge to edge, from
  about 180 to 420 pixels down in a 1920 × 600 image. It is all the closed notch shows, and the
  light and the icon must read on its ends. Put decoration above and below it.
- **The centre** holds text, icons and album art when the notch opens, so keep the middle 60% of
  the width dark and quiet too. Put decoration toward the left and right edges. Kannu picks dark
  or light text from the skin's average colour under its scrim, but a busy or bright centre still
  reads worse than a dark one.
- **The top centre** meets the camera housing: keep it close to black.
- **The corners** are rounded and clipped: keep detail about 40 pixels in from every edge.

## Built-in skins

**Horns** predates the sideways pill: its bright red ends sit right where the light and the icon
now go, so a red or yellow light reads poorly on it. It is being redrawn. Until the new image lands,
raise **Scrim opacity** to read the light on it. The prompt for the redraw, for an image AI, is:

```text
Make one 1920 × 600 pixel landscape PNG: a background skin called "Horns" for a macOS app that lives in the MacBook notch. Devilish red and black. Base: deep charcoal black with a faint hexagon-mesh texture. Two curved, glowing crimson horns: one rising from the upper-left area and curling up and outward, the other mirroring it at the upper right. Faint embers and scorched grain in the lower-left and lower-right corners. Keep a calm, near-black horizontal corridor across the whole width, from about 180 to 420 pixels down, with no red, glow or texture in it: a small status light (sometimes red or yellow) sits at its left end and an app icon at its right end. Keep the middle 60% of the width dark and quiet, the top centre pure black for the camera notch, and all detail at least 40 pixels in from every edge. No text, letters, logos, watermarks, interface elements, people or faces.
```

## Design one with AI

Click **Copy AI prompt** in the same section, paste it into ChatGPT or another AI that makes images,
and answer its questions. It asks about mood, colours, motifs, how bold, and what to avoid, then
draws a skin that follows the rules above. Save the image and upload it with **Upload skin**.

This is the prompt it copies:

```text
You are a designer making a background image ("skin") for Kannu, a macOS app that lives in the MacBook notch. The image fills the panel that drops down from the top centre of the screen, and a thin strip through its middle fills the closed notch.

First, ask me these questions one at a time, and wait for each answer. Do not generate anything until I have answered all of them.
1. What mood or theme do you want? (For example: calm, cosy, sci-fi, retro arcade, nature, devilish.)
2. Which two or three colours should lead?
3. Any motifs, textures or patterns? (For example: circuit lines, marble, waves, embers.)
4. How bold should it be: subtle, balanced or loud?
5. Anything to avoid?

Then sum up my answers in one short paragraph and generate one image that follows these rules:
- 1920 × 600 pixels, landscape, PNG.
- Keep a calm, dark horizontal corridor through the middle of the image, from the left edge to the right edge, from about 180 to 420 pixels down. The closed notch shows only this corridor: Kannu draws a small coloured status light at its far left end and an app icon at its far right end, and both must stay readable on it.
- Keep the centre (about the middle 60% of the width) dark and low in detail too. When the notch opens, Kannu draws text, icons and album art there.
- Put the decoration above and below the corridor, toward the left and right edges, balanced on both sides.
- Keep the top centre close to black, so it blends into the camera notch.
- Keep important detail at least 40 pixels from every edge: the corners are rounded and clipped.
- No text, letters, logos, watermarks, interface elements, people or faces.

If I ask for changes, keep the same size and rules.
```
