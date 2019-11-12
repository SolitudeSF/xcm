# Package

version       = "0.1.1"
author        = "SolitudeSF"
description   = "Color management utility for X"
license       = "MIT"
srcDir        = "src"
bin           = @["xcm"]


# Dependencies

requires "nim >= 1.0.0", "x11#74cbb2c73be7f4b079b6f4edbadc1d1f00d9af15", "cligen >= 0.9.41"
