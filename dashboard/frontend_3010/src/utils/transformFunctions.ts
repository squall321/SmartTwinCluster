/**
 * Transform Functions for Command Template Variables
 *
 * Slurm 설정값을 다양한 형식으로 변환하는 함수들
 * DynamicVariable의 transform 필드에서 사용
 */

/**
 * 메모리 문자열을 KB로 변환
 * @example "16G" -> 16777216, "512M" -> 524288, "1024K" -> 1024
 */
export function memory_to_kb(memory: string): number {
  const match = memory.match(/^(\d+(?:\.\d+)?)\s*([KMGT]?)$/i);
  if (!match) {
    throw new Error(`Invalid memory format: ${memory}`);
  }

  const value = parseFloat(match[1]);
  const unit = match[2].toUpperCase();

  switch (unit) {
    case 'K':
      return Math.floor(value);
    case 'M':
      return Math.floor(value * 1024);
    case 'G':
      return Math.floor(value * 1024 * 1024);
    case 'T':
      return Math.floor(value * 1024 * 1024 * 1024);
    case '':
      // 단위 없으면 MB로 가정 (Slurm 기본값)
      return Math.floor(value * 1024);
    default:
      throw new Error(`Unknown memory unit: ${unit}`);
  }
}

/**
 * 메모리 문자열을 MB로 변환
 * @example "16G" -> 16384, "512M" -> 512, "1024K" -> 1
 */
export function memory_to_mb(memory: string): number {
  return Math.floor(memory_to_kb(memory) / 1024);
}

/**
 * 메모리 문자열을 GB로 변환
 * @example "16G" -> 16, "512M" -> 0.5, "1024K" -> 0.001
 */
export function memory_to_gb(memory: string): number {
  return memory_to_kb(memory) / (1024 * 1024);
}

/**
 * 시간 문자열을 초로 변환
 * @example "01:30:00" -> 5400, "00:45:00" -> 2700
 */
export function time_to_seconds(time: string): number {
  const parts = time.split(':').map(p => parseInt(p, 10));

  if (parts.length === 3) {
    // HH:MM:SS
    const [hours, minutes, seconds] = parts;
    return hours * 3600 + minutes * 60 + seconds;
  } else if (parts.length === 2) {
    // MM:SS
    const [minutes, seconds] = parts;
    return minutes * 60 + seconds;
  } else if (parts.length === 1) {
    // SS
    return parts[0];
  } else {
    throw new Error(`Invalid time format: ${time}`);
  }
}

/**
 * 시간 문자열을 분으로 변환
 * @example "01:30:00" -> 90, "00:45:00" -> 45
 */
export function time_to_minutes(time: string): number {
  return Math.floor(time_to_seconds(time) / 60);
}

/**
 * 시간 문자열을 시간으로 변환
 * @example "01:30:00" -> 1.5, "00:45:00" -> 0.75
 */
export function time_to_hours(time: string): number {
  return time_to_seconds(time) / 3600;
}

/**
 * 파일 경로에서 파일명만 추출
 * @example "/path/to/file.txt" -> "file.txt"
 */
export function basename(path: string): string {
  return path.split('/').pop() || path;
}

/**
 * 파일 경로에서 디렉토리 경로만 추출
 * @example "/path/to/file.txt" -> "/path/to"
 */
export function dirname(path: string): string {
  const parts = path.split('/');
  parts.pop();
  return parts.join('/') || '/';
}

/**
 * 파일명에서 확장자 제거
 * @example "simulation.py" -> "simulation", "data.tar.gz" -> "data.tar"
 */
export function remove_extension(filename: string): string {
  const lastDot = filename.lastIndexOf('.');
  if (lastDot === -1 || lastDot === 0) {
    return filename;
  }
  return filename.substring(0, lastDot);
}

/**
 * 파일명에서 모든 확장자 제거
 * @example "data.tar.gz" -> "data"
 */
export function remove_all_extensions(filename: string): string {
  const firstDot = filename.indexOf('.');
  if (firstDot === -1 || firstDot === 0) {
    return filename;
  }
  return filename.substring(0, firstDot);
}

/**
 * 문자열을 대문자로 변환
 * @example "hello" -> "HELLO"
 */
export function uppercase(str: string): string {
  return str.toUpperCase();
}

/**
 * 문자열을 소문자로 변환
 * @example "HELLO" -> "hello"
 */
export function lowercase(str: string): string {
  return str.toLowerCase();
}

/**
 * 숫자를 문자열로 변환 (포맷팅)
 * @example 1000 -> "1000", 1.5 -> "1.5"
 */
export function to_string(value: number): string {
  return String(value);
}

/**
 * 숫자를 정수로 변환
 * @example 1.7 -> 1, "42" -> 42
 */
export function to_int(value: number | string): number {
  return Math.floor(Number(value));
}

/**
 * 값을 그대로 반환 (기본 변환)
 * @example "value" -> "value"
 */
export function identity(value: any): any {
  return value;
}

/**
 * Transform 함수 매핑 테이블
 */
export const TRANSFORM_FUNCTIONS: Record<string, (value: any) => any> = {
  memory_to_kb,
  memory_to_mb,
  memory_to_gb,
  time_to_seconds,
  time_to_minutes,
  time_to_hours,
  basename,
  dirname,
  remove_extension,
  remove_all_extensions,
  uppercase,
  lowercase,
  to_string,
  to_int,
  identity,
};

/**
 * Transform 함수 실행
 * @param transformName - 변환 함수 이름
 * @param value - 변환할 값
 * @returns 변환된 값
 * @throws Error if transform function not found
 */
export function applyTransform(transformName: string | undefined, value: any): any {
  if (!transformName || transformName === 'identity') {
    return value;
  }

  const transformFn = TRANSFORM_FUNCTIONS[transformName];
  if (!transformFn) {
    throw new Error(`Transform function not found: ${transformName}`);
  }

  return transformFn(value);
}

/**
 * 여러 Transform 함수를 체인으로 실행
 * @example applyTransformChain(["uppercase", "remove_extension"], "hello.txt") -> "HELLO"
 */
export function applyTransformChain(transforms: string[], value: any): any {
  return transforms.reduce((acc, transformName) => {
    return applyTransform(transformName, acc);
  }, value);
}
