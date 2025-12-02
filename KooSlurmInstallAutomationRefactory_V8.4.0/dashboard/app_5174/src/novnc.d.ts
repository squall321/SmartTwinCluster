/**
 * noVNC Type Declarations
 *
 * noVNC는 TypeScript 타입을 제공하지 않으므로 기본 타입만 선언
 */

declare module '@novnc/novnc/lib/rfb.js' {
  export default class RFB {
    constructor(target: HTMLElement, url: string, options?: any);

    // 속성
    scaleViewport: boolean;
    resizeSession: boolean;
    showDotCursor: boolean;
    clipViewport: boolean;
    dragViewport: boolean;
    viewOnly: boolean;
    qualityLevel: number;
    compressionLevel: number;

    // 메서드
    disconnect(): void;
    sendKey(keysym: number, code: string, down?: boolean): void;
    sendCtrlAltDel(): void;
    machineShutdown(): void;
    machineReboot(): void;
    machineReset(): void;
    clipboardPasteFrom(text: string): void;

    // 이벤트
    addEventListener(type: string, listener: (e: any) => void): void;
    removeEventListener(type: string, listener: (e: any) => void): void;
  }
}
