# MuffinStore Compatibility Fork

Experimental App Store app downgrader / installer with TrollStore. This fork
adds an automatic compatibility scan to the historical version picker.

When a version list opens, MuffinStore checks builds from newest to oldest,
reads each build's authoritative `MinimumOSVersion`, and marks the newest build
that supports the device's current iOS version.

## How compatibility detection works

1. MuffinStore gets historical version identifiers from the existing
   `apis.bilin.eu.org` history endpoint.
2. The device's active App Store account requests the selected build metadata
   directly from Apple. Credentials and tokens are never stored or sent to a
   third-party service.
3. HTTP range requests read only the IPA ZIP directory and the main
   `Payload/*.app/Info.plist`; the complete IPA is not downloaded.
4. Results are cached by App Store app ID and external version identifier.

The target app must already be in the signed-in account's purchase history.
Use the refresh button in the picker to discard cached compatibility metadata
and check again.

For downloading older versions you can choose between entering a app's older version's identifier manually, or getting them from a API. You might consider getting them from the API a invasion of privacy, as it needs to also send the app's app id you want to download with the request. If you want to use this app without using a external API except the App Store, you can just enter a id manually. You can get them from ipatool-py, and numerous other places.

## Support Me
Everything I do is for free, and open source. If you like my work, please consider supporting me on [Ko-fi](https://ko-fi.com/mineekdev), it would help me stay motivated and help me buy new testing devices for example. Thanks.
