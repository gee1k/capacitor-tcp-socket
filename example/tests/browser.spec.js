import { test, expect } from '@playwright/test';

test('example imports the real plugin and reports unsupported browser TCP', async ({ page }) => {
  const errors = [];
  page.on('pageerror', (error) => errors.push(error.message));
  await page.goto('/');
  await page.getByRole('button', { name: 'Connect', exact: true }).click();
  await expect(page.locator('#log-area')).toContainText('TCP sockets are not supported in web browsers.');
  await expect(page.locator('#status-text')).toHaveText('Disconnected');
  await expect(page.getByRole('button', { name: 'Disconnect', exact: true })).toBeDisabled();
  expect(errors).toEqual([]);
});

test('native smoke action also uses the real plugin in a browser', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: 'Run TCP smoke test' }).click();
  await expect(page.locator('#log-area')).toContainText(
    'Smoke test failed: TCP sockets are not supported in web browsers.',
  );
});
