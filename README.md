# Celeste iOS patcher

Binary is produced by repackaging the official Discord IPA, a dylib is injected to redirect network traffic to Celeste's, then the app is re-signed and re-zipped.

## Install

You can just download the [latest release](https://github.com/vbxq/celeste-ipa/releases/latest/download/Celeste.ipa) 


## Build
If you want to build it yourself

```sh
./bootstrap.sh                          # once: tools + SDK
./build.sh [Discord.ipa] [Celeste.ipa]  # defaults to both at the repo root
```

The input must be a decrypted Discord IPA: every Mach-O needs `cryptid 0`.
An App Store copy is FairPlay-encrypted and cannot run once re-signed, so
`build.sh` refuses it. Decrypt Discord from your own device (for example
`bagbak` or `frida-ios-dump` on a jailbroken iPhone).

## Distribution

`source.json` is an AltStore source: point your alternative app store at
`sourceURL` to install `Celeste.ipa`.

## License

<a href="LICENSE"><img src="https://upload.wikimedia.org/wikipedia/commons/thumb/0/06/AGPLv3_Logo.svg/1280px-AGPLv3_Logo.svg.png" alt="GNU Affero General Public License v3" width="240"></a>

celeste-ipa is free software released under the
[GNU Affero General Public License v3](LICENSE).