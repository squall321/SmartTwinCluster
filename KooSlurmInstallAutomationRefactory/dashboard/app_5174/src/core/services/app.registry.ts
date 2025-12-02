/**
 * App Registry
 *
 * 앱 등록 및 관리 시스템
 */

import type { AppRegistration, AppMetadata } from '@core/types';

/**
 * 등록된 앱 저장소
 */
const registry = new Map<string, AppRegistration>();

/**
 * App Registry API
 */
export const appRegistry = {
  /**
   * 앱 등록
   */
  register(registration: AppRegistration): void {
    const { metadata } = registration;

    if (registry.has(metadata.id)) {
      console.warn(`[AppRegistry] App already registered: ${metadata.id}`);
    }

    registry.set(metadata.id, registration);
    console.log(`[AppRegistry] Registered app: ${metadata.id} (${metadata.name})`);
  },

  /**
   * 앱 등록 해제
   */
  unregister(appId: string): boolean {
    const result = registry.delete(appId);
    if (result) {
      console.log(`[AppRegistry] Unregistered app: ${appId}`);
    }
    return result;
  },

  /**
   * 앱 조회
   */
  get(appId: string): AppRegistration | undefined {
    return registry.get(appId);
  },

  /**
   * 앱 존재 여부
   */
  has(appId: string): boolean {
    return registry.has(appId);
  },

  /**
   * 모든 앱 목록
   */
  list(): AppRegistration[] {
    return Array.from(registry.values());
  },

  /**
   * 앱 메타데이터만 조회
   */
  listMetadata(): AppMetadata[] {
    return Array.from(registry.values()).map((reg) => reg.metadata);
  },

  /**
   * 카테고리별 앱 조회
   */
  getByCategory(category: string): AppRegistration[] {
    return Array.from(registry.values()).filter(
      (reg) => reg.metadata.category === category
    );
  },

  /**
   * 태그로 앱 검색
   */
  searchByTags(tags: string[]): AppRegistration[] {
    return Array.from(registry.values()).filter((reg) => {
      const appTags = reg.metadata.tags || [];
      return tags.some((tag) => appTags.includes(tag));
    });
  },

  /**
   * 앱 검색 (이름, 설명)
   */
  search(query: string): AppRegistration[] {
    const lowerQuery = query.toLowerCase();
    return Array.from(registry.values()).filter((reg) => {
      const { name, description } = reg.metadata;
      return (
        name.toLowerCase().includes(lowerQuery) ||
        description?.toLowerCase().includes(lowerQuery)
      );
    });
  },

  /**
   * 앱 컴포넌트 동적 로드
   */
  async loadComponent(appId: string): Promise<React.ComponentType<any> | null> {
    const registration = registry.get(appId);
    if (!registration) {
      console.error(`[AppRegistry] App not found: ${appId}`);
      return null;
    }

    try {
      const loaded = await registration.component();
      // Handle both default export and direct export
      return ('default' in loaded) ? (loaded as any).default : loaded;
    } catch (error) {
      console.error(`[AppRegistry] Failed to load app component: ${appId}`, error);
      return null;
    }
  },

  /**
   * 레지스트리 초기화
   */
  clear(): void {
    registry.clear();
    console.log('[AppRegistry] Cleared all apps');
  },

  /**
   * 통계
   */
  stats(): {
    total: number;
    byCategory: Record<string, number>;
  } {
    const apps = Array.from(registry.values());
    const byCategory: Record<string, number> = {};

    apps.forEach((reg) => {
      const category = reg.metadata.category || 'uncategorized';
      byCategory[category] = (byCategory[category] || 0) + 1;
    });

    return {
      total: apps.length,
      byCategory,
    };
  },
};
