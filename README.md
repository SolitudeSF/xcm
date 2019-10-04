# xcm
Color management CLI application. Allows setting arbitrary color transformation matrix, saturation, degamma, preset and custom regamma values.

## Installation
`nimble install xcm`

Required dependencies are `x11`, `xrandr` and `libdrm`.

## Example usage
```sh
xcm saturation 2
xcm regamma 1 2 3
xcm degamma linear
xcm matrix 0 0 0 1 1 0 0 0 1
```

CLI interface is using [cligen](https://github.com/c-blake/cligen), so you can abbreviate any command and option like this:  
```sh
xcm s 2
xcm d l
```
