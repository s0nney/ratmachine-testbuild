# Themes

Main and Cyb share one set of layout rules in
`src/assets/stylesheets/main.css`. Main declares the default purple palette
as `--theme-*` properties. `cyb.css` imports that stylesheet and overrides the
properties with a black background, green text and accents, dark fields, and
monospace fonts. Layout changes should go in the shared stylesheet so both
themes stay in sync.

Both retain desktop nested threads and collapsing board dividers, the flat
mobile thread view and backlinks, target highlights, the bottom composer and
connected board tabs and the overboard. (The Pinned and Archives tabs it also
styled were removed on 2026-09-21.) There is no client-side
JavaScript.

Horizontal and vertical scrollbars share theme-colored sunken tracks, raised
striped thumbs, and beveled arrow buttons. Blink/WebKit use the detailed
scrollbar pseudo-elements; Firefox uses native scrollbars with theme-colored
thumbs and tracks. Keep `scrollbar-color: auto` in the pseudo-element support
branch: a custom standard color overrides the detailed treatment in Blink.
Mobile board tabs retain their hidden scrollbar and native swipe scrolling.

The Cyb palette uses a separate strong-text variable from field backgrounds
so active tab labels and backlinks remain readable. CAPTCHA images keep a
light backing because their generated glyphs are black. Formatting effects
remain available, including Cyb's yellow greentext.

Webpack resolves the import into `public/dist/cyb.bundle.css`; it does not
require a second stylesheet request. Rebuild both themes with `npm run build`
(or run it in the app container when generated files are owned by that container).
The existing `/style/main` and `/style/cyb` routes select the theme via cookie.

On mobile, a discreet 16 × 44 px grip on the left bezel opens a native
`details` drawer. The handle has no visible text; its accessible name and
tooltip remain “Themes.” Its beveled handle and compact appearance panel use the
current palette, with Main/Cyb choices and an active-theme indicator. Tapping
the handle again closes it; keyboard users can toggle it with the native
summary control. Opening animation respects reduced-motion preferences.

Choosing a theme sends a normal request and redirects to the same application
page using a validated `return_to` parameter. Board/reply paths and existing
query strings survive; text typed into an unsent form is not persisted across
this page load. External destinations and theme-action loops fall back to `/`.

Verified: both bundles build; main-theme declaration values remain equivalent
after variable substitution; Cyb renders on desktop and portrait mobile,
with an expanded reply composer and CAPTCHA, and on landscape moderator login.
