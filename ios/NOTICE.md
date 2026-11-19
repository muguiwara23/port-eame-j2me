# Port/eame Java

A Port/eame build of J2ME-Decade (iOS Edition): it runs the player's own
J2ME (MIDP 2.0 / CLDC 1.1) games on iPhone and iPad. No game is included.

Port/eame's changes (on the `port-eame/ios` branch): the bundled game is
removed, the 24/7 background keepalive (silent audio, location, network) is
off, the interface is in Spanish, and the app is built and packaged with the
Port/eame kit (https://github.com/muguiwara23/port-eame-kit).

Built on:

- J2ME-Decade (iOS Edition) by Vạn Trần — Apache License 2.0 (LICENSE).
- The J2ME emulator for iOS by Alexander Goremykin it started from.
- J2ME-Loader's MIDP/CLDC API (Apache License 2.0).
- miniJVM by digitalgust — MIT License (miniJVM-LICENSE.txt).
- GeneralUser GS SoundFont by S. Christian Collins (gs_instruments.sf2),
  under its GeneralUser GS license, which allows redistribution:
  https://schristiancollins.com/generaluser.php
