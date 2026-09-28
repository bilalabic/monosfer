import QRCode from 'qrcode'

export async function renderAcceptanceQrCode(canvas: HTMLCanvasElement, payload: string): Promise<void> {
  await QRCode.toCanvas(canvas, payload, {
    errorCorrectionLevel: 'M',
    margin: 2,
    width: 320,
  })
}
