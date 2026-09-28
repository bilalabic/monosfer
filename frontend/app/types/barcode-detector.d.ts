// BarcodeDetector is not yet in TypeScript's default DOM lib (Chrome/Edge/Android only).
// https://developer.mozilla.org/en-US/docs/Web/API/BarcodeDetector
interface BarcodeDetectorOptions {
  formats: string[]
}

interface DetectedBarcode {
  rawValue: string
  format: string
}

declare class BarcodeDetector {
  static getSupportedFormats(): Promise<string[]>
  constructor(options?: BarcodeDetectorOptions)
  detect(source: CanvasImageSource): Promise<DetectedBarcode[]>
}

interface Window {
  BarcodeDetector?: typeof BarcodeDetector
}
