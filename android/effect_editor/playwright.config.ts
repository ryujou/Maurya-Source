import {defineConfig, devices} from '@playwright/test';

export default defineConfig({
  testDir: './tests',
  testIgnore: '**/*.unit.test.ts',
  timeout: 30_000,
  use: {
    baseURL: 'http://127.0.0.1:4307',
    ...devices['Pixel 5'],
    locale: 'zh-CN',
  },
  webServer: {
    command: 'npx vite --host 127.0.0.1 --port 4307',
    url: 'http://127.0.0.1:4307',
    reuseExistingServer: true,
  },
});
