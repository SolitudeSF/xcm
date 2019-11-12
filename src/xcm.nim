import math, options
import x11/[x, xlib, xrandr, xatom]

const
  minLut = 1.0 / float(1 shl 10)
  lutSize = 4096
  propDegamma = "DEGAMMA_LUT"
  propRegamma = "GAMMA_LUT"
  propCTM = "CTM"

type
  Color = tuple[r, g, b: float]
  CoeffTable = array[lutSize, Color]
  DrmCTM = array[9, int64]
  DrmLUT = tuple[red, green, blue, reserved: uint16]
  rgCurve = enum
    rgCustom = "custom", rgSrgb = "srgb", rgMax = "max", rgMin = "min"
  dgCurve = enum
    dgSrgb = "srgb", dgLinear = "linear"

func sanitized(x: float): float {.inline.} =
  if x < minLut: minLut else: x

func toCoeffTable(exps: openArray[float]): CoeffTable =
  let
    r = exps[0].sanitized
    g = exps[1].sanitized
    b = exps[2].sanitized
  for i in 0..result.high:
    let d = i.float * 1 / (lutSize - 1).float
    result[i].r = pow(d, 1 / r)
    result[i].g = pow(d, 1 / g)
    result[i].b = pow(d, 1 / b)

func coeffTableMax: CoeffTable =
  for i in 1..result.high:
    result[i].r = 1.0
    result[i].g = 1.0
    result[i].b = 1.0

func satToMatrix(s: float): array[9, float] =
  let
    l = (1.0 - s) / 3
    h = l + s
  [h, l, l, l, h, l, l, l, h]

func brightToMatrix(s: float): array[9, float] =
  [s, 0, 0, 0, s, 0, 0, 0, s]

func coeffsToLUT(coeffs: CoeffTable): array[lutSize, DrmLUT] =
  for i in 0..result.high:
    result[i].red = uint16(coeffs[i].r * 0xFFFF)
    result[i].green = uint16(coeffs[i].g * 0xFFFF)
    result[i].blue = uint16(coeffs[i].b * 0xFFFF)

func coeffsToCTM(coeffs: openArray[float]): DrmCTM =
  for i in 0..8:
    if coeffs[i] < 0:
      result[i] = int64(-coeffs[i] * float(1'i64 shl 32))
      result[i] = result[i] or cast[int64](1'u64 shl 63)
    else:
      result[i] = int64(coeffs[i] * float(1'i64 shl 32))

proc setOutputBlob(dpy: PDisplay, output: TRROutput, propName: string,
                   blob: pointer, size: int, format: RandrFormat) =
  let
    propAtom = XInternAtom(dpy, propName.cstring, 1)
    propInfo = XRRQueryOutputProperty(dpy, output, propAtom)

  XRRChangeOutputProperty(
    dpy, output, propAtom, XA_INTEGER, format.cint, PropModeReplace,
    cast[ptr cuchar](blob), cint(size div (format.int shr 3)))

  discard XSync(dpy, 0.TBool)

proc setCTM(dpy: PDisplay, output: TRROutput, coeffs: openArray[float]) =
  let ctm = coeffs.coeffsToCTM
  var paddedCTM: array[DrmCTM.len * 2, int]
  for i in 0..17:
    paddedCTM[i] = int(cast[array[DrmCTM.len * 2, int32]](ctm)[i])
  setOutputBlob(dpy, output, propCTM, addr paddedCTM, sizeof DrmCTM, randrFormat32bit)

proc setGamma(dpy: PDisplay, output: TRROutput, coeffs: Option[CoeffTable], isDegamma: bool) =
  let propName = if isDegamma: propDegamma else: propRegamma
  if coeffs.isSome:
    let lut = coeffsToLUT(coeffs.get)
    setOutputBlob(dpy, output, propName, unsafeAddr lut, sizeof lut, randrFormat16bit)
  else:
    let zero = 0
    setOutputBlob(dpy, output, propName, unsafeAddr zero, 2, randrFormat16bit)

proc findOutput(dpy: PDisplay, res: PXRRScreenResources, name: string): TRROutput =
  for i in 0..<res.noutput.int:
    result = res.outputs[i]
    let outputInfo = XRRGetOutputInfo(dpy, res, result)
    if outputInfo.name == name.cstring:
      XRRFreeOutputInfo outputInfo
      break
    XRRFreeOutputInfo outputInfo

proc getActiveOutputs(dpy: PDisplay, res: PXRRScreenResources): seq[TRROutput] =
  for i in 0..<res.noutput.int:
    let
      output = res.outputs[i]
      outputInfo = XRRGetOutputInfo(dpy, res, output)
    if outputInfo.connection == RR_Connected:
      result.add output
    XRRFreeOutputInfo outputInfo

when isMainModule:
  import cligen

  proc initX(output = ""): (PDisplay, TWindow, PXRRScreenResources, TRROutput) =
    result[0] = XOpenDisplay(nil)
    result[1] = DefaultRootWindow(result[0])
    result[2] = XRRGetScreenResourcesCurrent(result[0], result[1])
    result[3] = if output.len == 0:
      getActiveOutputs(result[0], result[2])[0]
    else:
      findOutput(result[0], result[2], output)

  proc deinitX(display: PDisplay, res: PXRRScreenResources) =
    XRRFreeScreenResources(res)
    discard XCloseDisplay(display)

  proc matrix(output = "", coefficients: seq[float]) =
    ## set arbitrary color matrix
    if coefficients.len == 9:
      var (dpy, root, res, outputId) = initX(output)
      setCTM(dpy, outputId, coefficients)
      deinitX(dpy, res)
    else:
      stderr.writeLine "Expected 9 matrix components."

  proc saturation(output = "", value: seq[float]) =
    ## set saturation to specified value
    if value.len == 1:
      var (dpy, root, res, outputId) = initX(output)
      setCTM(dpy, outputId, value[0].satToMatrix)
      deinitX(dpy, res)
    else:
      stderr.writeLine "Expected one saturation value."

  proc brightness(output = "", value: seq[float]) =
    ## set brightness to specified value
    if value.len == 1:
      var (dpy, root, res, outputId) = initX(output)
      setCTM(dpy, outputId, value[0].brightToMatrix)
      deinitX(dpy, res)
    else:
      stderr.writeLine "Expected one brightness value."

  proc degamma(output = "", curve: seq[dgCurve]) =
    ## set degamma
    if curve.len == 1:
      var (dpy, root, res, outputId) = initX(output)
      case curve[0]
      of dgSrgb:
        setGamma(dpy, outputId, none[CoeffTable](), true)
      of dgLinear:
        setGamma(dpy, outputId, some toCoeffTable [1.0, 1, 1], true)
      deinitX(dpy, res)
    else:
      stderr.writeLine "Expected one degamma curve type."

  proc regamma(output = "", curve = rgCustom, coefficients: seq[float]) =
    ## set regamma
    var (dpy, root, res, outputId) = initX(output)
    case curve
    of rgSrgb:
      setGamma(dpy, outputId, none[CoeffTable](), false)
    of rgMin:
      setGamma(dpy, outputId, some default CoeffTable, false)
    of rgMax:
      setGamma(dpy, outputId, some coeffTableMax(), false)
    of rgCustom:
      if coefficients.len == 3:
        setGamma(dpy, outputId, some toCoeffTable coefficients, false)
      else:
        stderr.writeLine "Expected 3 color components"
    deinitX(dpy, res)

  dispatchMulti(
    ["multi", doc = "Manage display colors of X\n\n"],
    [matrix],
    [saturation],
    [brightness],
    [degamma],
    [regamma]
  )
