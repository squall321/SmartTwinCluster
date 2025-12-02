import { PatternFill, PatternOp, PatternKind, Rect } from "../types";

// 내부/외부 처리 유틸
function applyArea(
  ctx: CanvasRenderingContext2D,
  r: Rect,
  drawShapePath: () => void,           // 모양 경로(채움 가능한 path여야 함)
  op: PatternOp,
  fill: PatternFill
) {
  ctx.save();
  if (fill === "inside") {
    // 모양 내부만 영향
    if (op === "paint") {
      ctx.globalCompositeOperation = "source-over";
      ctx.fillStyle = "#fff";
      drawShapePath();
      ctx.fill();
    } else {
      // erase
      ctx.globalCompositeOperation = "destination-out";
      drawShapePath();
      ctx.fill();
    }
  } else {
    // outside: face rect - shape 를 채움 (evenodd)
    const makeOutsidePath = () => {
      ctx.beginPath();
      // 큰 사각형
      ctx.rect(r.x, r.y, r.w, r.h);
      // 모양 경로(구멍)
      drawShapePath();
    };

    if (op === "paint") {
      ctx.globalCompositeOperation = "source-over";
      ctx.fillStyle = "#fff";
      makeOutsidePath();
      ctx.fill("evenodd"); // 바깥 영역만 칠함
    } else {
      // erase outside
      ctx.globalCompositeOperation = "destination-out";
      makeOutsidePath();
      ctx.fill("evenodd");
    }
  }
  ctx.restore();
}

export function drawPatternOnFace(
  ctx: CanvasRenderingContext2D,
  r: Rect,
  kind: PatternKind,
  params: Record<string, number>,
  ppmm: number,
  op: PatternOp = "paint",
  fill: PatternFill = "inside"
) {
  ctx.save();
  ctx.imageSmoothingEnabled = true;

  const lineMM = params.lineMM ?? 2;
  const bandMM = params.bandMM ?? 8;
  const borderMM = params.borderMM ?? 3;
  const padMM = params.padMM ?? 6;
  const gapMM = params.gapMM ?? 2;
  const cornerMM = params.cornerMM ?? 12;

  const lw = Math.max(1, Math.round(lineMM * ppmm));
  const bh = Math.round(bandMM * ppmm);
  const bw = Math.round(bandMM * ppmm);
  const b = Math.max(1, Math.round(borderMM * ppmm));
  const pad = Math.max(1, Math.round(padMM * ppmm));
  const gap = Math.max(0, Math.round(gapMM * ppmm));
  const c = Math.max(0, Math.round(cornerMM * ppmm));

  switch (kind) {
    case "wrap-cross": {
      // 가로/세로 십자 = 두 개의 띠(채움 가능한 영역)
      const drawShapePath = () => {
        // 가로 띠
        const y = Math.round(r.y + (r.h - bh) / 2);
        ctx.rect(r.x, y, r.w, bh);
        // 세로 띠
        const x = Math.round(r.x + (r.w - bw) / 2);
        ctx.rect(x, r.y, bw, r.h);
      };
      applyArea(ctx, r, drawShapePath, op, fill);
      break;
    }

    case "band-h": {
      const drawShapePath = () => {
        const y = Math.round(r.y + (r.h - bh) / 2);
        ctx.rect(r.x, y, r.w, bh);
      };
      applyArea(ctx, r, drawShapePath, op, fill);
      break;
    }

    case "band-v": {
      const drawShapePath = () => {
        const x = Math.round(r.x + (r.w - bw) / 2);
        ctx.rect(x, r.y, bw, r.h);
      };
      applyArea(ctx, r, drawShapePath, op, fill);
      break;
    }

    case "border-only": {
      const drawShapePath = () => {
        // 바깥 사각형 - 안쪽 사각형 (테두리 영역)
        ctx.rect(r.x, r.y, r.w, r.h);
        ctx.rect(r.x + b, r.y + b, Math.max(0, r.w - 2*b), Math.max(0, r.h - 2*b));
      };
      // 테두리 자체가 채움 가능한 면적이므로 inside/outside 그대로 처리
      applyArea(ctx, r, drawShapePath, op, fill);
      break;
    }

    case "corner-pads": {
      const drawShapePath = () => {
        // 네 모서리 사각형들
        ctx.rect(r.x + gap, r.y + gap, pad, pad);
        ctx.rect(r.x + r.w - pad - gap, r.y + gap, pad, pad);
        ctx.rect(r.x + gap, r.y + r.h - pad - gap, pad, pad);
        ctx.rect(r.x + r.w - pad - gap, r.y + r.h - pad - gap, pad, pad);
      };
      applyArea(ctx, r, drawShapePath, op, fill);
      break;
    }

    case "diagWrapX": {
      // 대각 X: 두 대각선(굵기 lw)을 면의 꼭짓점에서 꼭짓점까지
      // line 기반이라 outside 처리를 별도 구현
      ctx.save();

      const strokeX = () => {
        ctx.lineCap = "butt";
        ctx.lineJoin = "miter";
        ctx.lineWidth = lw;

        // \ 대각선
        ctx.beginPath();
        ctx.moveTo(r.x, r.y);
        ctx.lineTo(r.x + r.w, r.y + r.h);
        ctx.stroke();

        // / 대각선
        ctx.beginPath();
        ctx.moveTo(r.x + r.w, r.y);
        ctx.lineTo(r.x, r.y + r.h);
        ctx.stroke();
      };

      if (fill === "inside") {
        // X 내부만
        if (op === "paint") {
          ctx.globalCompositeOperation = "source-over";
          ctx.strokeStyle = "#fff";
          strokeX();
        } else {
          ctx.globalCompositeOperation = "destination-out";
          ctx.strokeStyle = "#000"; // 색은 의미없음
          strokeX();
        }
      } else {
        // outside: “X를 제외한 바깥” 영역
        if (op === "paint") {
          // 1) 면 전체 칠함
          ctx.globalCompositeOperation = "source-over";
          ctx.fillStyle = "#fff";
          ctx.fillRect(r.x, r.y, r.w, r.h);
          // 2) X 부분만 도려내기
          ctx.globalCompositeOperation = "destination-out";
          ctx.strokeStyle = "#000";
          strokeX();
        } else {
          // erase + outside 조합은 "X를 제외한 영역"을 지우는 의미.
          // = 바깥만 투명화
          ctx.globalCompositeOperation = "destination-out";
          // outside 영역을 만들기 위해 evenodd 사용:
          ctx.beginPath();
          // 전체
          ctx.rect(r.x, r.y, r.w, r.h);
          // X를 '구멍'으로 만들기 위해, 라인을 두꺼운 다각형으로 근사
          // 간단 근사: X 주변에 직사각형 대각 띠 두 개
          // (fillRect는 안 되므로, 대각 띠를 Path로 생성)
          const k = lw / Math.SQRT2; // 대각선 폭 보정
          // \ 대각 띠
          ctx.moveTo(r.x - k, r.y + k);
          ctx.lineTo(r.x + k, r.y - k);
          ctx.lineTo(r.x + r.w + k, r.y + r.h - k);
          ctx.lineTo(r.x + r.w - k, r.y + r.h + k);
          ctx.closePath();
          // / 대각 띠
          ctx.moveTo(r.x + r.w - k, r.y - k);
          ctx.lineTo(r.x + r.w + k, r.y + k);
          ctx.lineTo(r.x + k, r.y + r.h + k);
          ctx.lineTo(r.x - k, r.y + r.h - k);
          ctx.closePath();

          ctx.fill("evenodd");
        }
      }

      ctx.restore();
      break;
    }
  }

  ctx.restore();
}
