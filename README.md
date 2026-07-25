# Celeste iOS patcher

Binary is produced by repackaging the official Discord IPA, a dylib is injected to redirect network traffic to Celeste's, then the app is re-signed and re-zipped.

## Install

You can just download the [latest release](https://github.com/vbxq/celeste-ipa/releases/latest/download/Celeste.ipa) 


## Build
If you want to build it yourself

```sh
./bootstrap.sh   # once: tools + SDK
./build.sh       # generates Celeste.ipa
```

`build.sh` expects `Discord.ipa` at the repo root.

## Distribution

`source.json` is an AltStore source: point your alternative app store at
`sourceURL` to install `Celeste.ipa`.

## License

<a href="LICENSE"><img src="https://upload.wikimedia.org/wikipedia/commons/thumb/0/06/AGPLv3_Logo.svg/1280px-AGPLv3_Logo.svg.png" alt="GNU Affero General Public License v3" width="240"></a>

celeste-ipa is free software released under the
[GNU Affero General Public License v3](LICENSE).