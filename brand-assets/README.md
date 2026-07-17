# Giftmaxxing app icon

`app-icon-master.png` is the generated brand master: a coral-to-violet satin
ribbon gift on a midnight background, with no text or baked corner mask.

Sync the iOS and website assets:

```sh
swift scripts/render-app-icon.swift
```

Rebuild the App Store product images:

```sh
swift scripts/compose-appstore-screenshots.swift
```
