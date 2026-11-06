# Release notes

## Unreleased

- With Tone on Auto, folder and app icons now follow your Mac's Light and Dark mode while Icon Mixer is running.
- Auto shows a Light and a Dark preview side by side.
- Auto is the default tone.

## 1.0.0

6 November 2026

The first release of Icon Mixer, a Mac app for putting your own pictures on folder and app icons. It needs a Mac with Apple silicon and macOS 14 or later, and has been tested on macOS 26.

### Folders

- Drag in a folder and an image, check the preview, and press Apply.
- Choose from four styles: Fill, Sticker, Tinted and Stamp. Sticker, Tinted and Stamp can use a front colour of your choice.
- Set what appears behind the front of the folder: the original back, a plain colour, or the picture in the same or a different position. A shadow between the layers is optional.
- Use Whole Cut to cut the picture to the folder's shape, or Picture Only to use the image itself as the icon.
- Give the second layer its own picture with Second Image.

### Apps

- Mix an image with an app's icon, with the picture following the icon's shape.
- Leave the image empty to add a finish to the app's original icon.
- Remove Image returns to the original icon.

### Finishes

- Add a Liquid Glass or Frosted finish, drawn in as a still image.
- On a folder, apply it to the whole folder, the first layer, the second layer, or both layers.
- Choose a Light, Dark, Auto or Custom tone. Clicking the icon in the preview switches between light and dark.
- Strength controls blur and bending. At 0 the picture stays sharp and only the glass surface shows.

### Adjusting

- Drag the preview to move a layer and pinch on a trackpad to zoom.
- The Adjust panel has a tab for each layer, each with placement, opacity, brightness, contrast and saturation.
- The front fades to 40% while you edit the second layer.
- Undo, Remove Custom Icon and Discard let you back out of a change.

### Known limits

- The app isn't notarised, so macOS may block it the first time you open it.
- macOS refuses to change system apps, and apps owned by root may be refused too. Other apps may need App Management permission.
- A custom app icon makes a strict code signature check fail, and an app update will probably replace it.
- A saved icon is one fixed picture, so it doesn't change when your Mac switches between Light and Dark mode.
- A physical trackpad pinch and external drives haven't been tested.
