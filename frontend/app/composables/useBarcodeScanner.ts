export function isBarcodeScannerSupported(): boolean {
  return typeof window !== 'undefined' && 'BarcodeDetector' in window
}

export interface BarcodeScanHandle {
  stop: () => void
}

/** Opens the rear camera and calls `onDetect` once with the first decoded QR payload. */
export async function startBarcodeScanner(
  video: HTMLVideoElement,
  onDetect: (value: string) => void,
): Promise<BarcodeScanHandle> {
  const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } })
  video.srcObject = stream
  await video.play()

  const detector = new BarcodeDetector({ formats: ['qr_code'] })
  let stopped = false
  let frame = 0

  const stop = () => {
    stopped = true
    cancelAnimationFrame(frame)
    stream.getTracks().forEach(track => track.stop())
  }

  const tick = async () => {
    if (stopped) return
    try {
      const codes = await detector.detect(video)
      const [first] = codes
      if (first) {
        onDetect(first.rawValue)
        stop()
        return
      }
    } catch {
      // Mid-frame decode errors are expected (e.g. camera still focusing) — keep polling.
    }
    frame = requestAnimationFrame(tick)
  }
  frame = requestAnimationFrame(tick)

  return { stop }
}
