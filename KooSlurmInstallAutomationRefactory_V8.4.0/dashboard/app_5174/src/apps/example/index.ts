/**
 * Example Apps Registry
 *
 * 예제 앱 등록
 */

import { appRegistry } from '@core/services/app.registry';

/**
 * GEdit 앱 등록
 */
export function registerGEditApp() {
  appRegistry.register({
    metadata: {
      id: 'gedit',
      name: 'GEdit',
      version: '1.0.0',
      description: 'Simple GNOME text editor for Linux',
      category: 'editor',
      tags: ['text', 'editor', 'document', 'gnome'],
    },
    defaultConfig: {
      resources: {
        cpus: 2,
        memory: '4Gi',
        gpu: false,
      },
      display: {
        type: 'novnc',
        width: 1280,
        height: 720,
      },
      container: {
        image: 'gedit-vnc',
        command: '/start-gedit.sh',
      },
    },
    component: () => import('./GEditApp'),
  });

  console.log('[Registry] GEdit app registered');
}

/**
 * 모든 예제 앱 등록
 */
export function registerExampleApps() {
  registerGEditApp();

  // 추가 앱 등록은 여기에...
  // registerGimpApp();
  // registerTerminalApp();
}

// Export
export { GEditApp } from './GEditApp';
