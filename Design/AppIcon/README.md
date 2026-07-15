# MacContainer application icon

`MacContainer-master.png` is the reviewed source artwork for the MacContainer application icon. It was generated on 2026-07-16 with OpenAI's built-in image generation tool and is distributed under the repository's Apache-2.0 license.

The production assets are not edited by hand. Run `scripts/generate-app-icon.swift` to render the transparent macOS squircle and all canonical AppIcon sizes. Run `scripts/check-app-icon.swift --master Design/AppIcon/MacContainer-master.png --app-icon-set App/MacContainer/Resources/Assets.xcassets/AppIcon.appiconset` or `zsh Tests/ToolingTests/check-app-icon.bats` to validate the result.

## Generation prompt

```text
Use case: logo-brand
Asset type: production master artwork for a native macOS 26 developer-tools app icon named MacContainer
Primary request: create an original, beautiful macOS app icon that communicates safe container isolation, orchestration, and a matrix-like control plane. The central symbol is a compact modular container core made from three interlocking isometric panels, suspended inside an open luminous portal/gateway. The portal should subtly suggest the letter M through negative space without using typography.
Scene/backdrop: full square icon composition on a deep graphite-to-midnight-blue rounded-square tile, with generous optical padding and a clear silhouette
Style/medium: premium Apple-platform icon craft, dimensional but restrained, crisp geometric forms, softly layered glass and anodized metal, polished production artwork, not a UI mockup
Composition/framing: centered, symmetrical, strong silhouette readable at 16px; one dominant symbol only; no tiny decorative clutter
Lighting/mood: controlled cyan and electric indigo rim light, calm trustworthy depth, a single tiny warm amber status light as an accent
Color palette: graphite, midnight navy, cyan, indigo-violet, restrained amber accent; high contrast in light and dark desktop contexts
Materials/textures: subtle frosted glass portal, satin dark metal container core, minimal soft ambient shadow contained within the tile
Constraints: square 1:1, macOS app icon, no text, no letters, no numbers, no Apple logo, no Docker whale, no terminal glyph, no shipping-box clipart, no official Apple container artwork, no watermark; keep all important artwork safely inside the central 78 percent; avoid photorealism; avoid excessive glow; avoid neon cyberpunk clutter; avoid gradients that muddy at small sizes
```

Master SHA-256: `d2af83385bb5a6c311c908ba5cec460c46fb9c38bc1126562638b08e0fd4b017`.
