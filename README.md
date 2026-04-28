# FreeFlow

This is my fork of [zachlatta/freeflow](https://freeflow.zachlatta.com/).

Two reasons for keeping a separate fork: 
- The main repo is completely vibe coded and unusable. I don't trust new releases.
- I want to add features that aren't useful for everyone.

Build the local dev app:

```bash
make -B all CODESIGN_IDENTITY=-
```

Run it from the repo:

```bash
open "build/FreeFlow Dev.app"
```

Move the rebuilt dev app into Applications:

```bash
rm -rf "/Applications/FreeFlow Dev.app"
cp -R "build/FreeFlow Dev.app" "/Applications/FreeFlow Dev.app"
```