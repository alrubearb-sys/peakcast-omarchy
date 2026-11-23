# Peakcast for Omarchy

Mountain weather in the [Omarchy](https://omarchy.org/) bar: the summit temperature of your area,
and on click its summit and base, wind at the height of the summit, snow line and freezing level.

The plugin shows what the [Peakcast](https://github.com/alrubearb-sys/peakcast) engine prints, so
the engine has to be installed first.

## Install

1. Install the engine. Until the AUR package is ready, take it from the latest
   [release](https://github.com/alrubearb-sys/peakcast/releases) (use `aarch64` instead of `x86_64`
   on ARM):

   ```
   cd /tmp
   curl -LO https://github.com/alrubearb-sys/peakcast/releases/download/v0.2.0/peakcast-0.2.0-x86_64-linux.tar.gz
   tar xzf peakcast-0.2.0-x86_64-linux.tar.gz
   install -Dm755 peakcast-0.2.0-x86_64-linux/peakcast peakcast-0.2.0-x86_64-linux/peakcast-map -t ~/.local/bin/
   ```

2. Add an area, for example `peakcast add Säntis`.

3. Add the plugin:

   ```
   omarchy plugin add https://github.com/alrubearb-sys/peakcast-omarchy --enable
   ```

Left click opens the card, middle click refreshes. Update with `omarchy plugin update io.github.alrubearb-sys.peakcast`.

## Remove

```
omarchy plugin remove io.github.alrubearb-sys.peakcast
rm ~/.local/bin/peakcast ~/.local/bin/peakcast-map
```

Your areas stay in `~/.config/peakcast` and the caches in `~/.cache/peakcast`; delete those folders
too to remove everything.

## Requirements

- The [Peakcast](https://github.com/alrubearb-sys/peakcast) engine (`peakcast`), which the plugin runs
  to read the forecast. The plugin itself makes no network requests; the engine asks Open-Meteo for
  the forecast and Nominatim for place searches.

## License

MIT. Weather data by [Open-Meteo](https://open-meteo.com/) (CC BY 4.0).
