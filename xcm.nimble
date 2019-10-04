# Package

version       = "0.1.0"
author        = "SolitudeSF"
description   = "X.org color matrix manipulation"
license       = "MIT"
srcDir        = "src"
bin           = @["xcm"]


# Dependencies

requires "nim >= 1.0.0", "https://github.com/SolitudeSF/x11#a33254a5ac0df76786ffdaf9d736add242179964", "cligen >= 0.9.38"
